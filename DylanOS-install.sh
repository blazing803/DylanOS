#!/bin/bash 

set -e  # Exit immediately if a command exits with a non-zero status

# Variables
HOSTNAME="dylanos-critus"
LOCALE="en_US.UTF-8"
TIMEZONE="America/New_York"
DISTRIBUTION_NAME="DylanOS Critus 4.0"

# Prompt the user to select the drive
read -p "Enter the drive for installation (e.g., /dev/sda): " DRIVE

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

# Prompt the user to enter additional packages
read -p "Enter additional packages (space-separated): " PACKAGES

# Calculate root partition size (half of the remaining drive size)
DRIVE_SIZE=$(blockdev --getsize64 "$DRIVE")
ROOT_SIZE=$((DRIVE_SIZE / 2))
ROOT_PART_SIZE=$((ROOT_SIZE / 1024 / 1024))  # Convert to MiB

# Format the partitions
parted -s "$DRIVE" mklabel gpt \
  mkpart primary fat32 1MiB 512MiB \
  set 1 esp on \
  mkpart primary linux-swap 512MiB "$((512 + ROOT_PART_SIZE))MiB" \
  mkpart primary ext4 "$((512 + ROOT_PART_SIZE))MiB" 100%

# Set partition variables
ROOT_PART="${DRIVE}3"
EFI_PART="${DRIVE}1"
SWAP_PART="${DRIVE}2"

# Format partitions
mkfs.fat -F32 "$EFI_PART"
mkswap "$SWAP_PART"
mkfs.ext4 "$ROOT_PART"

# Mount the partitions
mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot/efi
mount "$EFI_PART" /mnt/boot/efi
swapon "$SWAP_PART"

# Install base system
echo "Installing base system..."
pacstrap /mnt base linux linux-firmware sof-firmware base-devel grub efibootmgr nano networkmanager git lightdm lightdm-gtk-greeter xterm ${PACKAGES} mesa nvidia virtualbox-guest-utils xf86-video-vmware xfce4-panel plank picom nitrogen i3 

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot into the installed system
arch-chroot /mnt <<EOF
# Set timezone
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# Locale configuration
sed -i '/^#en_US.UTF-8 UTF-8/s/^#//' /etc/locale.gen
echo "LANG=$LOCALE" > /etc/locale.conf
locale-gen

# Hostname and locale
echo "$HOSTNAME" > /etc/hostname
sed -i '/^# %wheel ALL=(ALL) ALL/s/^# //' /etc/sudoers

# Set root password
echo "root:$PASSWORD" | chpasswd

# Create user and set password
useradd -mG wheel -s /bin/bash "$USERNAME"
echo "$USERNAME:$PASSWORD" | chpasswd

# Enable services
echo "Enabling services..."
systemctl enable lightdm
systemctl enable NetworkManager
systemctl enable vboxservice
systemctl enable ntpd.service
systemctl enable bluetooth.service  # Enable Bluetooth service
systemctl enable sshd.service        # Enable SSH daemon
systemctl enable cups.service         # Enable CUPS for printing
systemctl enable cronie.service       # Enable cron service

timedatectl set-ntp true

# Update /etc/os-release
echo "Updating /etc/os-release..."
cat <<EOF2 > /etc/os-release
NAME="$DISTRIBUTION_NAME"
VERSION="4.0"
ID=dylanos
ID_LIKE=arch
EOF2

# Update GRUB to reflect new distribution name
echo "Updating GRUB..."
sed -i "s/Arch Linux/$DISTRIBUTION_NAME/" /etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg

# Create wallpapers directory and download wallpapers
echo "Setting up wallpapers directory..."
cd /home/$USERNAME

# Clone the repository for wallpapers
git clone https://github.com/D3Ext/aesthetic-wallpapers.git

# Set the wallpapers directory path
WALLPAPER_DIR="/home/$USERNAME/aesthetic-wallpapers"

# Configure Nitrogen to use the first wallpaper found in the directory
echo "Configuring Nitrogen..."
mkdir -p /home/$USERNAME/.config/nitrogen

# Use the first .jpg or .png file found in the cloned directory
DEFAULT_WALLPAPER=$(find "$WALLPAPER_DIR" -type f \( -iname "*.jpg" -o -iname "*.png" \) | head -n 1)

if [[ -n "$DEFAULT_WALLPAPER" ]]; then
  cat <<EOF3 > /home/$USERNAME/.config/nitrogen/bg-saved.cfg
[DEFAULT]
file=$DEFAULT_WALLPAPER
EOF3
  chown $USERNAME:$USERNAME /home/$USERNAME/.config/nitrogen/bg-saved.cfg
else
  echo "No wallpapers found in $WALLPAPER_DIR."
fi

# Create i3 configuration directory
mkdir -p /home/$USERNAME/.config/i3

# Configure i3 with the specified settings
cat <<EOF4 > /home/$USERNAME/.config/i3/config
# This file has been auto-generated by i3-config-wizard(1).
# It will not be overwritten, so edit it as you like.
#
# Should you change your keyboard layout some time, delete
# this file and re-run i3-config-wizard(1).
#

set \$mod Mod4

font pango:monospace 8

exec --no-startup-id dex --autostart --environment i3

exec --no-startup-id xss-lock --transfer-sleep-lock -- i3lock --nofork

exec --no-startup-id nm-applet

set \$refresh_i3status killall -SIGUSR1 i3status
bindsym XF86AudioRaiseVolume exec --no-startup-id pactl set-sink-volume @DEFAULT_SINK@ +10% && \$refresh_i3status
bindsym XF86AudioLowerVolume exec --no-startup-id pactl set-sink-volume @DEFAULT_SINK@ -10% && \$refresh_i3status
bindsym XF86AudioMute exec --no-startup-id pactl set-sink-mute @DEFAULT_SINK@ toggle && \$refresh_i3status
bindsym XF86AudioMicMute exec --no-startup-id pactl set-source-mute @DEFAULT_SOURCE@ toggle && \$refresh_i3status

floating_modifier \$mod
tiling_drag modifier titlebar

bindsym \$mod+Return exec i3-sensible-terminal
bindsym \$mod+Shift+q kill
bindsym \$mod+d exec --no-startup-id dmenu_run

bindsym \$mod+j focus left
bindsym \$mod+k focus down
bindsym \$mod+l focus up
bindsym \$mod+semicolon focus right

bindsym \$mod+Shift+j move left
bindsym \$mod+Shift+k move down
bindsym \$mod+Shift+l move up
bindsym \$mod+Shift+semicolon move right

bindsym \$mod+h split h
bindsym \$mod+v split v

bindsym \$mod+f fullscreen toggle
bindsym \$mod+s layout stacking
bindsym \$mod+w layout tabbed
bindsym \$mod+e layout toggle split
bindsym \$mod+Shift+space floating toggle
bindsym \$mod+space focus mode_toggle
bindsym \$mod+a focus parent

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

bindsym \$mod+Shift+c reload
bindsym \$mod+Shift+r restart
bindsym \$mod+Shift+e exec "i3-nagbar -t warning -m 'You pressed the exit shortcut. Do you really want to exit i3? This will end your X session.' -B 'Yes, exit i3' 'i3-msg exit'"

mode "resize" {
    bindsym j resize shrink width 10 px or 10 ppt
    bindsym k resize grow height 10 px or 10 ppt
    bindsym l resize shrink height 10 px or 10 ppt
    bindsym semicolon resize grow width 10 px or 10 ppt

    bindsym Return mode "default"
    bindsym Escape mode "default"
}

bindsym \$mod+r mode "resize"

exec xfce4-panel
exec plank
exec picom
exec nitrogen --restore

for_window [class="^.*"] border pixel 0

gaps inner 10
gaps outer 10
EOF4

# Set ownership of the i3 config directory and file
chown -R $USERNAME:$USERNAME /home/$USERNAME/.config/i3

EOF

# Unmount partitions after installation
umount -R /mnt

echo "Installation complete! Please reboot."
