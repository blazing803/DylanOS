#!/bin/bash

# Variables
ROOT_PARTITION="/dev/sda3"
EFI_PARTITION="/dev/sda1"
SWAP_PARTITION="/dev/sda2"
HOSTNAME="dylanos-critus"
LOCALE="en_US.UTF-8"
TIMEZONE="America/New_York"
DISTRIBUTION_NAME="DylanOS Critus 4.0"

# Prompt for user credentials
read -p "Enter desired username: " USERNAME
read -sp "Enter desired password: " PASSWORD
echo
read -sp "Confirm password: " PASSWORD_CONFIRM
echo

# Check if passwords match
if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
  echo "Passwords do not match. Exiting."
  exit 1
fi

# Partition the disk
echo "Partitioning the disk..."
fdisk /dev/sda <<EOF
g
n


+100M
n


+4G
n


w
EOF

# Check if fdisk succeeded
if [ $? -ne 0 ]; then
  echo "Partitioning failed. Exiting."
  exit 1
fi

# Format partitions
echo "Formatting partitions..."
mkfs.fat -F 32 $EFI_PARTITION
mkswap $SWAP_PARTITION
mkfs.ext4 $ROOT_PARTITION

# Check if formatting succeeded
if [ $? -ne 0 ]; then
  echo "Formatting failed. Exiting."
  exit 1
fi

# Mount partitions
echo "Mounting partitions..."
mount $ROOT_PARTITION /mnt
mkdir -p /mnt/boot/efi
mount $EFI_PARTITION /mnt/boot/efi
swapon $SWAP_PARTITION

# Check if mounting succeeded
if [ $? -ne 0 ]; then
  echo "Mounting failed. Exiting."
  exit 1
fi

# Install base system
echo "Installing base system..."
pacstrap /mnt base linux linux-firmware sof-firmware base-devel grub efibootmgr nano networkmanager git

# Check if pacstrap succeeded
if [ $? -ne 0 ]; then
  echo "Base installation failed. Exiting."
  exit 1
fi

# Generate fstab
echo "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# Change root into the new system
arch-chroot /mnt /bin/bash <<EOF
# System configuration
echo "Configuring system..."
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# Locale configuration
sed -i '/^#en_US.UTF-8 UTF-8/s/^#//' /etc/locale.gen
echo "LANG=$LOCALE" > /etc/locale.conf
locale-gen

# Hostname and locale
echo "$HOSTNAME" > /etc/hostname
sed -i '/^# %wheel ALL=(ALL) ALL/s/^# //' /etc/sudoers

# Configure pacman
sed -i '/^\[multilib\]/,/^#Include/s/^#//' /etc/pacman.conf
sed -i 's/^#SigLevel = Required DatabaseOptional/SigLevel = Never/' /etc/pacman.conf

# Set root password
echo "root:$PASSWORD" | chpasswd

# Create user
useradd -m -G wheel -s /bin/bash $USERNAME
echo "$USERNAME:$PASSWORD" | chpasswd

# Install and configure GRUB
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=grub
grub-mkconfig -o /boot/grub/grub.cfg

# Install additional packages
pacman -Sy --needed mesa nvidia virtualbox-guest-utils xf86-video-vmware xfce4-panel plank picom nitrogen i3 lxqt

# Configure LXQt to use i3
mkdir -p /home/$USERNAME/.config/lxqt
cat <<EOF > /home/$USERNAME/.config/lxqt/lxqt.conf
[WindowManager]
window_manager=i3
EOF
chown $USERNAME:$USERNAME /home/$USERNAME/.config/lxqt/lxqt.conf

# Configure i3
mkdir -p /home/$USERNAME/.config/i3
cat <<EOF > /home/$USERNAME/.config/i3/config
set \$mod Mod4

# Font for window titles. Will also be used by the bar unless a different font
# is used in the bar {} block below.
font pango:monospace 8

# Start XDG autostart .desktop files using dex. See also
# https://wiki.archlinux.org/index.php/XDG_Autostart
exec --no-startup-id dex --autostart --environment i3

# The combination of xss-lock, nm-applet and pactl is a popular choice, so
# they are included here as an example. Modify as you see fit.
exec --no-startup-id xss-lock --transfer-sleep-lock -- i3lock --nofork
exec --no-startup-id nm-applet

# Use pactl to adjust volume in PulseAudio.
set \$refresh_i3status killall -SIGUSR1 i3status
bindsym XF86AudioRaiseVolume exec --no-startup-id pactl set-sink-volume @DEFAULT_SINK@ +10% && \$refresh_i3status
bindsym XF86AudioLowerVolume exec --no-startup-id pactl set-sink-volume @DEFAULT_SINK@ -10% && \$refresh_i3status
bindsym XF86AudioMute exec --no-startup-id pactl set-sink-mute @DEFAULT_SINK@ toggle && \$refresh_i3status
bindsym XF86AudioMicMute exec --no-startup-id pactl set-source-mute @DEFAULT_SOURCE@ toggle && \$refresh_i3status

# Use Mouse+\$mod to drag floating windows to their wanted position
floating_modifier \$mod
tiling_drag modifier titlebar

# start a terminal
bindsym \$mod+Return exec i3-sensible-terminal

# kill focused window
bindsym \$mod+Shift+q kill

# start dmenu (a program launcher)
bindsym \$mod+d exec --no-startup-id dmenu_run
# A more modern dmenu replacement is rofi:
# bindcode \$mod+40 exec "rofi -modi drun,run -show drun"
# There also is i3-dmenu-desktop which only displays applications shipping a
# .desktop file. It is a wrapper around dmenu, so you need that installed.
# bindcode \$mod+40 exec --no-startup-id i3-dmenu-desktop

# change focus
bindsym \$mod+j focus left
bindsym \$mod+k focus down
bindsym \$mod+l focus up
bindsym \$mod+semicolon focus right

# alternatively, you can use the cursor keys:
bindsym \$mod+Left focus left
bindsym \$mod+Down focus down
bindsym \$mod+Up focus up
bindsym \$mod+Right focus right

# move focused window
bindsym \$mod+Shift+j move left
bindsym \$mod+Shift+k move down
bindsym \$mod+Shift+l move up
bindsym \$mod+Shift+semicolon move right

# alternatively, you can use the cursor keys:
bindsym \$mod+Shift+Left move left
bindsym \$mod+Shift+Down move down
bindsym \$mod+Shift+Up move up
bindsym \$mod+Shift+Right move right

# split in horizontal orientation
bindsym \$mod+h split h

# split in vertical orientation
bindsym \$mod+v split v

# enter fullscreen mode for the focused container
bindsym \$mod+f fullscreen toggle

# change container layout (stacked, tabbed, toggle split)
bindsym \$mod+s layout stacking
bindsym \$mod+w layout tabbed
bindsym \$mod+e layout toggle split

# toggle tiling / floating
bindsym \$mod+Shift+space floating toggle

# change focus between tiling / floating windows
bindsym \$mod+space focus mode_toggle

# focus the parent container
bindsym \$mod+a focus parent

# Define names for default workspaces for which we configure key bindings later on.
set \$ws1 "1"
set \$ws2 "2"
set \$ws3 "3"
set \$ws4 "4"
set \$ws5 "5"
set \$ws6 "6"
set \$ws7 "7"
set \$ws8 "8"
set \$ws9 "9"
set \$ws10 "10"

# switch to workspace
bindsym \$mod+1 workspace number \$ws1
bindsym \$mod+2 workspace number \$ws2
bindsym \$mod+3 workspace number \$ws3
bindsym \$mod+4 workspace number \$ws4
bindsym \$mod+5 workspace number \$ws5
bindsym \$mod+6 workspace number \$ws6
bindsym \$mod+7 workspace number \$ws7
bindsym \$mod+8 workspace number \$ws8
bindsym \$mod+9 workspace number \$ws9
bindsym \$mod+0 workspace number \$ws10

# move focused container to workspace
bindsym \$mod+Shift+1 move container to workspace number \$ws1
bindsym \$mod+Shift+2 move container to workspace number \$ws2
bindsym \$mod+Shift+3 move container to workspace number \$ws3
bindsym \$mod+Shift+4 move container to workspace number \$ws4
bindsym \$mod+Shift+5 move container to workspace number \$ws5
bindsym \$mod+Shift+6 move container to workspace number \$ws6
bindsym \$mod+Shift+7 move container to workspace number \$ws7
bindsym \$mod+Shift+8 move container to workspace number \$ws8
bindsym \$mod+Shift+9 move container to workspace number \$ws9
bindsym \$mod+Shift+0 move container to workspace number \$ws10

# reload the configuration file
bindsym \$mod+Shift+c reload
# restart i3 inplace (preserves your layout/session, can be used to upgrade i3)
bindsym \$mod+Shift+r restart
# exit i3 (logs you out of your X session)
bindsym \$mod+Shift+e exec "i3-nagbar -t warning -m 'You pressed the exit shortcut. Do you really want to exit i3? This will end your X session.' -B 'Yes, exit i3' 'i3-msg exit'"

# resize window (you can also use the mouse for that)
mode "resize" {
        bindsym j resize shrink width 10 px or 10 ppt
        bindsym k resize grow height 10 px or 10 ppt
        bindsym l resize shrink height 10 px or 10 ppt
        bindsym semicolon resize grow width 10 px or 10 ppt

        bindsym Left resize shrink width 10 px or 10 ppt
        bindsym Down resize grow height 10 px or 10 ppt
        bindsym Up resize shrink height 10 px or 10 ppt
        bindsym Right resize grow width 10 px or 10 ppt

        bindsym Return mode "default"
        bindsym Escape mode "default"
        bindsym \$mod+r mode "default"
}

bindsym \$mod+r mode "resize"

exec xfce4-panel
exec plank
exec picom
exec nitrogen --restore

for_window [class="^.*"] border pixel 0

gaps inner 10
gaps outer 10
EOF
chown $USERNAME:$USERNAME /home/$USERNAME/.config/i3/config

# Create wallpapers directory and download wallpapers
echo "Setting up wallpapers directory..."
mkdir -p /home/$USERNAME/${USERNAME}_wallpapers
cd /home/$USERNAME/${USERNAME}_wallpapers

echo "Downloading wallpapers..."
git clone https://github.com/D3Ext/aesthetic-wallpapers ./
chown -R $USERNAME:$USERNAME /home/$USERNAME/${USERNAME}_wallpapers

# Function to pick a random wallpaper
pick_random_wallpaper() {
  local wallpaper_dir="/home/$USERNAME/${USERNAME}_wallpapers"
  local wallpapers=("$wallpaper_dir"/*.jpg "$wallpaper_dir"/*.png)
  local count=${#wallpapers[@]}
  if [ $count -gt 0 ]; then
    local random_index=$((RANDOM % count))
    echo "${wallpapers[$random_index]}"
  else
    echo "No wallpapers found"
  fi
}

# Configure nitrogen to use a random wallpaper
echo "Configuring Nitrogen..."
random_wallpaper=$(pick_random_wallpaper)
cat <<EOF > /home/$USERNAME/.config/nitrogen/bg-saved.cfg
[DEFAULT]
file=$random_wallpaper
EOF
chown $USERNAME:$USERNAME /home/$USERNAME/.config/nitrogen/bg-saved.cfg

# Create XFCE configuration for icon theme
echo "Configuring icon theme..."
mkdir -p /home/$USERNAME/.config/xfce4/xfconf/xfce-perchannel-xml
cat <<EOF > /home/$USERNAME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="last-image" type="string" value=""/>
  <property name="last-image-wp" type="string" value=""/>
  <property name="theme" type="string" value="Oxygen"/>
  <property name="icon-theme-name" type="string" value="oxygen"/>
</channel>
EOF
chown $USERNAME:$USERNAME /home/$USERNAME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml

# Update OS name in various places

# Update /etc/os-release
echo "Updating /etc/os-release..."
cat <<EOF > /mnt/etc/os-release
NAME="$DISTRIBUTION_NAME"
VERSION="4.0"
ID=dylanos
ID_LIKE=arch
EOF

# Update GRUB to reflect new distribution name
echo "Updating GRUB..."
sed -i "s/Arch Linux/$DISTRIBUTION_NAME/" /mnt/etc/default/grub
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

# Enable services
echo "Enabling services..."
arch-chroot /mnt systemctl enable NetworkManager
arch-chroot /mnt systemctl enable vboxservice
arch-chroot /mnt systemctl enable lightdm.service
arch-chroot /mnt systemctl enable ntpd.service
arch-chroot /mnt timedatectl set-ntp true

# Exit chroot environment
echo "Unmounting partitions and rebooting..."
umount -R /mnt

if [ $? -ne 0 ]; then
  echo "Unmounting failed. Please check manually."
  exit 1
fi

reboot
