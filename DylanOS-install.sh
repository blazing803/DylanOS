#!/bin/bash

# ASCII Art for DylanOS 4.0
cat << "EOF"
  _____        _              ____   _____   _  _    ___  
 |  __ \      | |            / __ \ / ____| | || |  / _ \ 
 | |  | |_   _| | __ _ _ __ | |  | | (___   | || |_| | | |
 | |  | | | | | |/ _` | '_ \| |  | |\___ \  |__   _| | | |
 | |__| | |_| | | (_| | | | | |__| |____) |    | |_| |_| |
 |_____/ \__, |_|\__,_|_| |_|\____/|_____/     |_(_)\___/ 
          __/ |                                           
         |___/                                            

                2023-2024
EOF

# Wait for 3 seconds
echo "Starting installation in 3 seconds..."
sleep 3

# Prompt for Variables (User input)
read -p "Enter the disk (e.g., /dev/sda): " DISK
read -p "Enter the username: " USER
read -sp "Enter the password for $USER (input hidden): " PASSWORD
echo
read -p "Enter your timezone (e.g., Region/City): " TIMEZONE

# Function for checking if a command exists
check_command() {
    command -v "$1" >/dev/null 2>&1 || { echo "$1 is required but not installed. Exiting."; exit 1; }
}

# Check if required commands exist
check_command cfdisk
check_command git
check_command pacstrap
check_command arch-chroot

# User Input Validation for Disk
while true; do
    if [[ -b "$DISK" ]]; then
        break
    else
        echo "Invalid disk name. Please enter a valid block device."
        read -p "Enter the disk (e.g., /dev/sda): " DISK
    fi
done

# Use cfdisk for manual partitioning
echo "Launching cfdisk for manual partitioning of $DISK..."
cfdisk $DISK || { echo "Failed to launch cfdisk. Exiting."; exit 1; }

# Prompt user for partition details (EFI and root partition)
read -p "Enter the EFI partition (e.g., /dev/sda1): " EFI_PART
read -p "Enter the root partition (e.g., /dev/sda2): " ROOT_PART

# Formatting the partitions
echo "Formatting partitions..."
mkfs.fat -F32 $EFI_PART || { echo "Failed to format EFI partition."; exit 1; }
mkfs.ext4 $ROOT_PART || { echo "Failed to format root partition."; exit 1; }

# Mount partitions
echo "Mounting partitions..."
mount $ROOT_PART /mnt || { echo "Failed to mount root partition."; exit 1; }
mkdir /mnt/boot
mount $EFI_PART /mnt/boot || { echo "Failed to mount EFI partition."; exit 1; }

# Install base packages using pacstrap
echo "Installing base system packages..."
pacstrap -K /mnt base linux linux-firmware base-devel sof-firmware || {
    echo "Failed to install base packages."
    exit 1
}

# Clone the configs repository to get pacman.conf
echo "Cloning configs repository to get pacman.conf..."
git clone https://github.com/blazing803/configs.git /mnt/tmp/configs || {
    echo "Failed to clone configs repository."
    exit 1
}

# Move pacman.conf to the correct location
mv /mnt/tmp/configs/pacman/pacman.conf /mnt/etc/pacman.conf || {
    echo "Failed to move pacman.conf."
    exit 1
}

# Install additional packages using pacman
echo "Installing additional packages..."
pacman -Sy --noconfirm lightdm lightdm-gtk-greeter i3 xfce4 picom plank \
    wget git nano htop ntp dhcpcd \
    openssh alacritty iwd wpa_supplicant \
    networkmanager dmidecode nitrogen unzip ark network-manager-applet leafpad || {
    echo "Failed to install additional packages."
    exit 1
}

# Install Yay (AUR helper)
echo "Installing Yay..."
su - $USER -c "git clone https://aur.archlinux.org/yay.git /tmp/yay && cd /tmp/yay && makepkg -si --noconfirm && cd .. && rm -rf /tmp/yay" || {
    echo "Failed to install Yay."
    exit 1
}

# Install Google Chrome
echo "Installing Google Chrome..."
su - $USER -c "yay -S google-chrome --noconfirm" || {
    echo "Failed to install Google Chrome."
    exit 1
}

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot into the installed system
arch-chroot /mnt /bin/bash <<EOF

# Set hostname based on user input
echo "$USER" > /etc/hostname

# Append to /etc/hosts for proper resolution
cat <<EOL >> /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   $USER.localdomain $USER
EOL

# Update /etc/os-release
cat <<EOL > /etc/os-release
NAME="DylanOS"
VERSION="4.0"
ID=dylanos
ID_LIKE=arch
PRETTY_NAME="DylanOS 4.0"
EOL

# Set timezone
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# Localization
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Install bootloader (systemd-boot for UEFI)
if ! bootctl install; then
    echo "Failed to install systemd-boot."
    exit 1
fi

# Create bootloader entry
cat <<BOOTEOF > /boot/loader/entries/dylanos.conf
title   DylanOS 4.0
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=PARTUUID=\$(blkid -s PARTUUID -o value $ROOT_PART) rw
BOOTEOF

# Set root password
echo "root:$PASSWORD" | chpasswd

# Create a new user with the provided username
useradd -m -G wheel -s /bin/bash $USER
echo "$USER:$PASSWORD" | chpasswd

# Allow wheel group to use sudo
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers

# Enable NTP service and set time synchronization
systemctl enable ntpd.service
systemctl start ntpd.service
timedatectl set-ntp true

# Enable services directly
systemctl enable NetworkManager
systemctl enable dhcpcd
systemctl enable lightdm
systemctl enable wpa_supplicant
systemctl enable iwd

# Clone configuration repositories from GitHub
echo "Cloning configuration repositories from GitHub..."
git clone https://github.com/blazing803/configs.git /tmp/configs || {
    echo "Failed to clone configs repository, exiting."
    exit 1
}

# Function to copy configuration files
copy_config() {
    local app_name="\$1"
    local config_dir="\$2"
    echo "Copying \$app_name configuration..."
    mkdir -p "/home/$USER/.config/\$config_dir"
    cp -r "/tmp/configs/\$config_dir/"* "/home/$USER/.config/\$config_dir/"
    chown -R "$USER:$USER" "/home/$USER/.config/\$config_dir"
}

# Copy configurations for various applications
copy_config "XFCE4" "xfce4"
copy_config "i3" "i3"
copy_config "Plank" "plank"
copy_config "Nitrogen" "nitrogen"

# Clean up cloned configuration repository
rm -rf /tmp/configs

# Download wallpapers
echo "Downloading wallpapers..."
git clone https://github.com/blazing803/wallpapers /tmp/wallpapers || {
    echo "Failed to clone wallpapers repository, exiting."
    exit 1
}

# Ensure the wallpapers directory exists
echo "Ensuring the directory /usr/share/backgrounds exists..."
mkdir -p /usr/share/backgrounds/

# Copy wallpapers to /usr/share/backgrounds/
echo "Copying wallpapers to /usr/share/backgrounds..."
cp -r /tmp/wallpapers/* /usr/share/backgrounds/

# Set proper permissions for the wallpapers
chmod -R 755 /usr/share/backgrounds/

# Clean up wallpapers repository
rm -rf /tmp/wallpapers

echo "DylanOS installation and setup completed successfully!"
EOF

# Unmount partitions
umount -R /mnt || echo "Failed to unmount partitions."

# Reboot system
echo "DylanOS installation is complete! You can now reboot."
