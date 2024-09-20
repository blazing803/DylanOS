#!/bin/bash 

set -e  # Exit immediately if a command exits with a non-zero status

# Variables
HOSTNAME="dylanos-critus"
LOCALE="en_US.UTF-8"
TIMEZONE="America/New_York"
DISTRIBUTION_NAME="DylanOS Critus 4.0"

# Prompt the user to select the drive
read -p "Enter the drive for installation (e.g., /dev/sda): " DRIVE

# Validate the specified drive
if [ ! -b "$DRIVE" ]; then
  echo "Invalid drive: $DRIVE. Exiting."
  exit 1
fi

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

# Sizes in MB
EFI_SIZE=1024  # Size of the EFI partition in MB
SWAP_SIZE=4096  # Size of the swap partition in MB (4 GB)

# Calculate the remaining size for the root partition
ROOT_PART_SIZE=$(( (blockdev --getsize64 "$DRIVE" / 1024 / 1024 / 1024) - EFI_SIZE - SWAP_SIZE ))

# Create the partition table and partitions using fdisk
(
echo n  # New partition
echo p  # Primary partition
echo 1  # Partition number
echo   # First sector (default)
echo +${EFI_SIZE}M  # Size of the EFI partition
echo t  # Change partition type
echo 1  # EFI partition type
echo n  # New partition
echo p  # Primary partition
echo 2  # Partition number
echo +${SWAP_SIZE}M  # Size of the swap partition
echo n  # New partition
echo p  # Primary partition
echo 3  # Partition number
echo   # First sector (default)
echo   # Last sector (default, uses remaining space)
echo w  # Write changes
) | fdisk "$DRIVE"

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

# Configure i3
cat <<EOF4 > /home/$USERNAME/.config/i3/config
# Set the modifier key
set \$mod Mod4

# Font for window titles and the bar
font pango:monospace 8

# Start XDG autostart .desktop files using dex
exec --no-startup-id dex --autostart --environment i3

# Lock the screen on sleep and start nm-applet
exec --no-startup-id xss-lock --transfer-sleep-lock -- i3lock --nofork
exec --no-startup-id nm-applet

# Volume control with PulseAudio
set \$refresh_i3status killall -SIGUSR1 i3status
bindsym XF86AudioRaiseVolume exec --no-startup-id pactl set-sink-volume @DEFAULT_SINK@ +10% && \$refresh_i3status
bindsym XF86AudioLowerVolume exec --no-startup-id pactl set-sink-volume @DEFAULT_SINK@ -10% && \$refresh_i3status
bindsym XF86AudioMute exec --no-startup-id pactl set-sink-mute @DEFAULT_SINK@ toggle && \$refresh_i3status
bindsym XF86AudioMicMute exec --no-startup-id pactl set-source-mute @DEFAULT_SOURCE@ toggle && \$refresh_i3status

# Use Mouse+\$mod to drag floating windows to their wanted position
floating_modifier \$mod
tiling_drag modifier titlebar

# Start a terminal
bindsym \$mod+Return exec i3-sensible-terminal

# Kill focused window
bindsym \$mod+Shift+q kill

# Start dmenu
bindsym \$mod+d exec --no-startup-id dmenu_run

# Change focus
bindsym \$mod+j focus left
bindsym \$mod+k focus down
bindsym \$mod+l focus up
bindsym \$mod+semicolon focus right

# Cursor key alternatives
bindsym \$mod+Left focus left
bindsym \$mod+Down focus down
bindsym \$mod+Up focus up
bindsym \$mod+Right focus right

# Move focused window
bindsym \$mod+Shift+j move left
bindsym \$mod+Shift+k move down
bindsym \$mod+Shift+l move up
bindsym \$mod+Shift+semicolon move right

# Split containers
bindsym \$mod+h split h
bindsym \$mod+v split v

# Fullscreen mode toggle
bindsym \$mod+f fullscreen toggle

# Change container layout
bindsym \$mod+s layout stacking
bindsym \$mod+w layout tabbed
bindsym \$mod+e layout toggle split

# Toggle floating mode
bindsym \$mod+Shift+space floating toggle

# Change focus between tiling/floating windows
bindsym \$mod+space focus mode_toggle

# Focus the parent container
bindsym \$mod+a focus parent

# Define workspace names
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

# Switch to workspaces
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

# Move focused container to workspace
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

# Reload and restart configuration
bindsym \$mod+Shift+c reload
bindsym \$mod+Shift+r restart
bindsym \$mod+Shift+e exec "i3-nagbar -t warning -m 'Do you really want to exit i3?' -B 'Yes, exit i3' 'i3-msg exit'"

# Resize windows
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

# Autostart applications
exec xfce4-panel
exec plank
exec picom
exec nitrogen --restore

# Window border settings
for_window [class="^.*"] border pixel 0

# Gaps between windows
gaps inner 10
gaps outer 10
EOF4

# Set ownership of the configuration files
chown -R $USERNAME:$USERNAME /home/$USERNAME/.config/i3

# Install and configure GRUB
echo "Installing GRUB..."
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --recheck
grub-mkconfig -o /boot/grub/grub.cfg

# Exit chroot
EOF

# Unmount partitions
umount -R /mnt

echo "Installation complete! Please reboot."
