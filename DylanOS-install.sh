
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

# Prompt for the disk and type
read -p "Enter the disk (e.g., /dev/nvme0n1 or /dev/sda): " DISK
read -p "Is this an NVMe disk? (yes/no): " NVME_RESPONSE

# Determine if the disk is NVMe based on user input
USE_NVME=${NVME_RESPONSE,,} # Lowercase the response
if [[ "$USE_NVME" == "yes" || "$USE_NVME" == "y" ]]; then
    ROOT_PART="${DISK}p1"
    SWAP_PART="${DISK}p2"
    EFI_PART="${DISK}p3"
else
    ROOT_PART="${DISK}1"
    SWAP_PART="${DISK}2"
    EFI_PART="${DISK}3"
fi

# Confirm with the user before partitioning
read -p "This will delete all data on $DISK. Proceed? (y/n): " confirm
if [[ ! $confirm =~ ^[yY]$ ]]; then
    echo "Operation canceled."
    exit 1
fi

# Partition the disk
if ! fdisk $DISK <<EOF
g
n
1

+1G
n
2

+4G
n
3


w
EOF
then
    echo "Partitioning failed. Please check the disk and try again."
    exit 1
fi

# Format the partitions
mkfs.fat -F 32 $EFI_PART || { echo "Failed to format EFI partition."; exit 1; }
mkswap $SWAP_PART || { echo "Failed to create swap partition."; exit 1; }
mkfs.ext4 $ROOT_PART || { echo "Failed to format root partition."; exit 1; }

# Mount the file systems
mount $ROOT_PART /mnt || { echo "Failed to mount root partition."; exit 1; }
mkdir -p /mnt/boot
mount $EFI_PART /mnt/boot || { echo "Failed to mount EFI partition."; exit 1; }
swapon $SWAP_PART || { echo "Failed to enable swap."; exit 1; }

# Install essential packages
pacstrap -K /mnt \
    base linux linux-firmware base-devel sof-firmware \
    i3-wm i3blocks i3status i3lock lightdm lightdm-gtk-greeter \
    pavucontrol wireless_tools gvfs wget git nano vim \
    htop xfce4-panel xfce4-appfinder xfce4-power-manager \
    xfce4-screenshooter xfce4-cpufreq-plugin xfce4-diskperf-plugin \
    xfce4-fsguard-plugin xfce4-mount-plugin xfce4-netload-plugin \
    xfce4-places-plugin xfce4-sensors-plugin xfce4-weather-plugin \
    xfce4-clipman-plugin xfce4-notes-plugin firefox \
    openssh alacritty iwd wpa_supplicant plank picom || { echo "Package installation failed."; exit 1; }

# Generate fstab
genfstab -U /mnt > /mnt/etc/fstab

# Chroot into the new system
arch-chroot /mnt /bin/bash <<EOF
# Set timezone
echo "Available timezones:"
ls /usr/share/zoneinfo
read -p "Enter your timezone (e.g., America/New_York): " timezone
ln -sf /usr/share/zoneinfo/\$timezone /etc/localtime
hwclock --systohc

# Localization
sed -i 's/^#\\(en_US\\.UTF-8\\)/\\1/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Set hostname
read -p "Enter hostname for the system: " hostname
echo "\$hostname" > /etc/hostname

# Initramfs
mkinitcpio -P

# Set root password
read -sp "Enter your root password: " password
echo "root:\$password" | chpasswd

# Create a new user
read -p "Enter your username: " username
read -sp "Enter password for user \$username: " user_password
useradd -m -G wheel "\$username"
echo "\$username:\$user_password" | chpasswd

# Enable and start services
systemctl enable lightdm
systemctl start lightdm
systemctl enable wpa_supplicant
systemctl start wpa_supplicant
systemctl enable iwd
systemctl start iwd
systemctl --user enable pulseaudio
systemctl --user start pulseaudio
systemctl enable NetworkManager
systemctl enable ssh

# Install GRUB
pacman -S --noconfirm grub efibootmgr

# Create GRUB configuration
cat << EOF2 > /boot/grub/grub.cfg
set default=0
set timeout=5

# Menu entry for DylanOS
menuentry "DylanOS 4.0" {
    set root=(hd0,gpt1)  # Adjust according to your EFI partition
    echo "Loading DylanOS 4.0..."
    linux /vmlinuz-linux root=$ROOT_PART rw
    initrd /initramfs-linux.img
}

# Advanced options
menuentry "Advanced options for DylanOS 4.0" {
    set root=(hd0,gpt1)  # Adjust according to your EFI partition
    echo "Loading Advanced options for DylanOS 4.0..."
    linux /vmlinuz-linux root=$ROOT_PART rw
    initrd /initramfs-linux.img
}

# Recovery mode
menuentry "Recovery mode for DylanOS 4.0" {
    set root=(hd0,gpt1)  # Adjust according to your EFI partition
    echo "Loading Recovery mode for DylanOS 4.0..."
    linux /vmlinuz-linux root=$ROOT_PART rw single
    initrd /initramfs-linux.img
}
EOF2

# Install GRUB
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=DylanOS

# Update /etc/os-release
echo "NAME=\"DylanOS\"" > /etc/os-release
echo "VERSION=\"4.0\"" >> /etc/os-release
echo "ID=dylanos" >> /etc/os-release
echo "ID_LIKE=arch" >> /etc/os-release

# Create a basic i3 config
mkdir -p /home/$username/.config/i3
cat << EOF3 > /home/$username/.config/i3/config
# i3 config
set \$mod Mod1  # Use Alt as the mod key

# Start applications
exec --no-startup-id xfce4-panel
exec --no-startup-id plank
exec --no-startup-id picom
exec --no-startup-id nitrogen --restore

# Start a terminal
bindsym \$mod+Return exec i3-sensible-terminal

# Additional i3 key bindings can go here...
EOF3

# Change ownership of the i3 config
chown -R \$username:\$username /home/\$username/.config

EOF

# Exit the chroot environment
exit
