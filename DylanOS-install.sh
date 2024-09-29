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

# Update the system clock
timedatectl set-ntp true

# User Input Variables
read -p "Enter the disk (e.g., /dev/nvme0n1 or /dev/sda): " DISK
read -p "Is this an NVMe disk? (yes/no): " NVME_RESPONSE
USE_NVME=${NVME_RESPONSE,,} # Lowercase the response
read -sp "Enter your root password: " password
echo  # New line
read -p "Enter your username: " username
read -sp "Enter password for user $username: " user_password
echo  # New line
read -p "Enter your timezone (e.g., America/New_York): " timezone

# Define partition variables based on NVMe detection
if [[ "$USE_NVME" == "yes" || "$USE_NVME" == "y" ]]; then
    EFI_PART="${DISK}p1"
    SWAP_PART="${DISK}p2"
    ROOT_PART="${DISK}p3"
else
    EFI_PART="${DISK}1"
    SWAP_PART="${DISK}2"
    ROOT_PART="${DISK}3"
fi

# Confirm with the user before partitioning
read -p "This will delete all data on $DISK. Proceed? (y/n): " confirm
if [[ ! $confirm =~ ^[yY]$ ]]; then
    echo "Operation canceled."
    exit 1
fi

# Partition the disk
echo "Partitioning the disk..."
if ! fdisk $DISK <<EOF
g
n
1

+1G         # EFI partition (1GB)
n
2

+4G         # Swap partition (4GB)
n
3

            # Root partition (use remaining space)
w
EOF
then
    echo "Partitioning failed. Please check the disk and try again."
    exit 1
fi

# Format the partitions
echo "Formatting partitions..."
mkfs.fat -F 32 $EFI_PART || { echo "Failed to format EFI partition."; exit 1; }
mkswap $SWAP_PART || { echo "Failed to create swap partition."; exit 1; }
mkfs.ext4 $ROOT_PART || { echo "Failed to format root partition."; exit 1; }

# Mount the file systems
echo "Mounting filesystems..."
mount $ROOT_PART /mnt || { echo "Failed to mount root partition."; exit 1; }
mount --mkdir $EFI_PART /mnt/boot || { echo "Failed to mount EFI partition."; exit 1; }
swapon $SWAP_PART || { echo "Failed to enable swap."; exit 1; }

# Install essential packages
echo "Installing essential packages..."
pacstrap -K /mnt \
    base linux linux-firmware base-devel sof-firmware \
    i3-wm i3blocks i3status i3lock lightdm lightdm-gtk-greeter \
    pavucontrol wireless_tools gvfs wget git nano vim \
    htop xfce4-panel xfce4-appfinder xfce4-power-manager \
    xfce4-screenshooter xfce4-cpufreq-plugin xfce4-diskperf-plugin \
    xfce4-fsguard-plugin xfce4-mount-plugin xfce4-netload-plugin \
    xfce4-places-plugin xfce4-sensors-plugin xfce4-weather-plugin \
    xfce4-clipman-plugin xfce4-notes-plugin firefox \
    openssh alacritty iwd wpa_supplicant plank picom \
    pulseaudio NetworkManager dmidecode || { echo "Package installation failed."; exit 1; }

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot into the new system
arch-chroot /mnt /bin/bash <<EOF
# Set timezone
ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
hwclock --systohc

# Set hostname to BIOS product name
hostname=\$(dmidecode -s system-product-name)
echo "\$hostname" > /etc/hostname

# Localization
sed -i 's/^#\\(en_US\\.UTF-8\\)/\\1/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Initramfs
mkinitcpio -P

# Set root password
echo "root:$password" | chpasswd

# Create a new user
useradd -m -G wheel "$username"
echo "$username:$user_password" | chpasswd

# Enable and start services
systemctl enable lightdm
systemctl enable wpa_supplicant
systemctl enable iwd
systemctl --user enable pulseaudio
systemctl enable NetworkManager
systemctl enable sshd

# Install GRUB
pacman -S --noconfirm grub efibootmgr

# Create GRUB configuration
cat << EOF2 > /boot/grub/grub.cfg
set default=0
set timeout=5

# Menu entry for DylanOS
menuentry "DylanOS 4.0" {
    set root=(hd0,gpt1)
    linux /vmlinuz-linux root=$ROOT_PART rw
    initrd /initramfs-linux.img
}

# Advanced options
menuentry "Advanced options for DylanOS 4.0" {
    set root=(hd0,gpt1)
    linux /vmlinuz-linux root=$ROOT_PART rw
    initrd /initramfs-linux.img
}

# Recovery mode
menuentry "Recovery mode for DylanOS 4.0" {
    set root=(hd0,gpt1)
    linux /vmlinuz-linux root=$ROOT_PART rw single
    initrd /initramfs-linux.img
}
EOF2

# Install GRUB
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=DylanOS || { echo "GRUB installation failed."; exit 1; }

# Update /etc/os-release
echo "NAME=\"DylanOS\"" > /etc/os-release
echo "VERSION=\"4.0\"" >> /etc/os-release
echo "ID=dylanos" >> /etc/os-release
echo "ID_LIKE=arch" >> /etc/os-release

# Download wallpapers from GitHub
echo "Downloading wallpapers..."
mkdir -p /etc/wallpapers
wget https://github.com/blazing803/wallpapers/archive/refs/heads/main.zip -O /tmp/wallpapers.zip || { echo "Failed to download wallpapers."; exit 1; }

# Extract wallpapers
unzip /tmp/wallpapers.zip -d /tmp || { echo "Failed to unzip wallpapers."; exit 1; }
cp -r /tmp/wallpapers-main/* /etc/wallpapers/ || { echo "Failed to copy wallpapers."; exit 1; }

# Clean up
rm -rf /tmp/wallpapers.zip /tmp/wallpapers-main

# Configure nitrogen to use wallpaper4.png
mkdir -p /home/$username/.config/nitrogen
cat << EOF4 > /home/$username/.config/nitrogen/bg-saved.cfg
[xin_-1]
file=/etc/wallpapers/wallpaper4.png
mode=0
bgcolor=#000000
EOF4

# Change ownership of nitrogen config
chown -R $username:$username /home/$username/.config/nitrogen

# Download i3 config from GitHub, rename it, and place it in ~/.config/i3
echo "Downloading i3 config..."
mkdir -p /home/$username/.config/i3
wget https://github.com/blazing803/configs/raw/main/i3-config -O /home/$username/.config/i3/i3-config || { echo "Failed to download i3 config."; exit 1; }

# Rename i3-config to config
mv /home/$username/.config/i3/i3-config /home/$username/.config/i3/config || { echo "Failed to rename i3-config to config."; exit 1; }

# Set ownership for the i3 config
chown -R $username:$username /home/$username/.config/i3

echo "i3 configuration has been successfully downloaded, renamed to 'config', and placed in /home/$username/.config/i3."
EOF

# Finalize and unmount
echo "Installation complete. Unmounting partitions..."
umount -R /mnt || { echo "Failed to unmount partitions."; exit 1; }
swapoff $SWAP_PART

echo "Installation complete. You can now reboot into DylanOS."
