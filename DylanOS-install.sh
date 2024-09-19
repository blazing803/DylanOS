#!/bin/bash
set -e

# Variables
HOSTNAME="dylanos-critus"
LOCALE="en_US.UTF-8"
TIMEZONE="America/New_York"

# Prompt for drive
read -p "Enter the drive for installation (default: /dev/sda): " DRIVE
DRIVE=${DRIVE:-/dev/sda}
EFI_PARTITION="${DRIVE}1"
SWAP_PARTITION="${DRIVE}2"
ROOT_PARTITION="${DRIVE}3"

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
fdisk $DRIVE <<EOF
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

# Function to install base system
install_base_system() {
    echo "Installing base system..."
    pacstrap /mnt base linux linux-firmware sof-firmware base-devel grub efibootmgr nano networkmanager lightdm lightdm-gtk-greeter ntp

    # Generate fstab
    echo "Generating fstab..."
    genfstab -U /mnt >> /mnt/etc/fstab
}

install_base_system

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

# Hostname and sudo configuration
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
cat <<EOL > /home/$USERNAME/.config/lxqt/lxqt.conf
[WindowManager]
window_manager=i3
EOL
chown $USERNAME:$USERNAME /home/$USERNAME/.config/lxqt/lxqt.conf

# Configure i3
mkdir -p /home/$USERNAME/.config/i3
cat <<EOL > /home/$USERNAME/.config/i3/config
set \$mod Mod4

# Font for window titles.
font pango:monospace 8

exec --no-startup-id dex --autostart --environment i3
exec --no-startup-id nm-applet

# Key bindings
# Add your i3 key bindings here...

EOL
chown $USERNAME:$USERNAME /home/$USERNAME/.config/i3/config

# Create wallpapers directory and download wallpapers
echo "Setting up wallpapers directory..."
mkdir -p /home/$USERNAME/wallpapers
cd /home/$USERNAME/wallpapers
echo "Downloading wallpapers..."
git clone https://github.com/D3Ext/aesthetic-wallpapers ./
chown -R $USERNAME:$USERNAME /home/$USERNAME/wallpapers

# Function to pick a random wallpaper
pick_random_wallpaper() {
  local wallpaper_dir="/home/$USERNAME/wallpapers"
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
cat <<EOL > /home/$USERNAME/.config/nitrogen/bg-saved.cfg
[DEFAULT]
file=$random_wallpaper
EOL
chown $USERNAME:$USERNAME /home/$USERNAME/.config/nitrogen/bg-saved.cfg

# Create XFCE configuration for icon theme
echo "Configuring icon theme..."
mkdir -p /home/$USERNAME/.config/xfce4/xfconf/xfce-perchannel-xml
cat <<EOL > /home/$USERNAME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="theme" type="string" value="Oxygen"/>
  <property name="icon-theme-name" type="string" value="oxygen"/>
</channel>
EOL
chown $USERNAME:$USERNAME /home/$USERNAME/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml

# Update OS name in various places
echo "Updating /etc/os-release..."
cat <<EOL > /mnt/etc/os-release
NAME="DylanOS"
VERSION="4.0"
ID=dylanos
ID_LIKE=arch
EOL

# Update GRUB to reflect new distribution name
echo "Updating GRUB..."
sed -i "s/Arch Linux/DylanOS/" /mnt/etc/default/grub
grub-mkconfig -o /boot/grub/grub.cfg

# Enable services
echo "Enabling services..."
systemctl enable NetworkManager
systemctl enable lightdm.service
systemctl enable ntpd.service
timedatectl set-ntp true

EOF

echo "Installation complete. Please reboot your system."
