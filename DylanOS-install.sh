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
# systemctl enable bluetooth.service  # Enable Bluetooth service
# systemctl enable sshd.service        # Enable SSH daemon
# systemctl enable cups.service         # Enable CUPS for printing
# systemctl enable cronie.service       # Enable cron service

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

# Configure i3 with the specified settings
cat <<EOF4 > /home/$USERNAME/.config/i3/config
# i3 configuration settings...
# (Existing i3 config content goes here)
EOF4

# Set ownership of the i3 config directory and file
chown -R $USERNAME:$USERNAME /home/$USERNAME/.config/i3

EOF

# Install and configure GRUB
echo "Installing GRUB..."
arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --recheck
arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg

# Unmount partitions after installation
umount -R /mnt

echo "Installation complete! Please reboot."
