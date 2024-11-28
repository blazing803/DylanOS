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

# Display current time settings
timedatectl

# Function: Check if the system is using UEFI
check_efi() {
    if [ -d /sys/firmware/efi ]; then
        return 0  # EFI detected
    else
        return 1  # BIOS detected
    fi
}

# Function: Check if a command exists
check_command() {
    command -v "$1" >/dev/null 2>&1 || { echo "$1 is required but not installed. Exiting."; exit 1; }
}

# Check required commands
for cmd in cfdisk git pacstrap arch-chroot; do
    check_command "$cmd"
done

# User Inputs
read -p "Do you want to set up dual boot (yes/no)? " DUALBOOT
DUALBOOT=${DUALBOOT:-no}

read -p "Do you want to enable UFW firewall (yes/no)? " ENABLE_UFW
ENABLE_UFW=${ENABLE_UFW:-no}

read -p "Enter your timezone (e.g., 'America/New_York'): " TIMEZONE
TIMEZONE=${TIMEZONE:-"America/New_York"}

read -p "Enter your username: " USER

read -sp "Enter your password: " PASSWORD

read -p "Enter the disk you want to install to (e.g., /dev/sda): " DISK

read -p "Do you want to wipe the partition table on $DISK? (yes/no) " WIPE_PARTITION
WIPE_PARTITION=${WIPE_PARTITION:-no}

# Function to delete the partition table by wiping the first 1MB of the disk
delete_partition_table() {
  # Unmount partitions before wiping
  echo "Unmounting any mounted partitions on $DISK..."
  umount "${DISK}"* || { echo "Failed to unmount partitions. Exiting."; exit 1; }

  # Wipe the partition table on $DISK
  echo "Wiping the partition table on $DISK..."
  dd if=/dev/zero of=$DISK bs=512 count=2048 status=progress
  if [ $? -eq 0 ]; then
    echo "Partition table deleted successfully on $DISK."
  else
    echo "Failed to delete the partition table on $DISK."
    exit 1
  fi
}

# Wipe partition table if requested
if [ "$WIPE_PARTITION" == "yes" ]; then
    delete_partition_table
fi

# Partition Automation
if [ "$DUALBOOT" == "yes" ]; then
    echo "Creating partitions for dual-boot setup..."
    echo -e "o\nn\np\n1\n\n+1G\nt\n1\nn\np\n2\n\n\nw" | fdisk "$DISK" || { echo "Failed to partition disk. Exiting."; exit 1; }
else
    echo "Creating partitions for single boot setup..."
    echo -e "o\nn\np\n1\n\n+1G\nt\n1\nn\np\n2\n\n\nw" | fdisk "$DISK" || { echo "Failed to partition disk. Exiting."; exit 1; }
fi

# Formatting Partitions
echo "Formatting partitions..."
mkfs.fat -F32 "$DISK"1 || { echo "Failed to format EFI partition. Exiting."; exit 1; }
mkfs.ext4 "$DISK"2 || { echo "Failed to format root partition. Exiting."; exit 1; }

# Mounting Partitions
echo "Mounting partitions..."
mount "$DISK"2 /mnt || { echo "Failed to mount root partition. Exiting."; exit 1; }
mount --mkdir "$DISK"1 /mnt/boot || { echo "Failed to mount EFI partition. Exiting."; exit 1; }

# Installing Base System
echo "Installing base system packages..."
pacstrap -K /mnt base linux linux-firmware base-devel sof-firmware \
    i3-wm i3blocks i3status i3lock lightdm lightdm-gtk-greeter \
    pavucontrol wireless_tools gvfs wget git nano vim \
    htop xfce4-panel xfce4-appfinder xfce4-power-manager \
    xfce4-screenshooter xfce4-cpufreq-plugin xfce4-diskperf-plugin \
    xfce4-fsguard-plugin xfce4-mount-plugin xfce4-netload-plugin \
    xfce4-places-plugin xfce4-sensors-plugin xfce4-weather-plugin \
    xfce4-clipman-plugin xfce4-notes-plugin firefox \
    openssh alacritty iwd wpa_supplicant plank picom \
    pulseaudio networkmanager dmidecode grub nitrogen unzip efibootmgr pcmanfm wget || { echo "Package installation failed."; exit 1; }

# Cloning Configuration Repository
echo "Cloning configs repository to get pacman.conf..."
git clone --depth 1 https://github.com/blazing803/configs.git /mnt/tmp/configs || { echo "Failed to clone configs repository. Exiting."; exit 1; }
mv /mnt/tmp/configs/pacman/pacman.conf /mnt/etc/pacman.conf || { echo "Failed to move pacman.conf. Exiting."; exit 1; }

# Generating fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot Configuration
arch-chroot /mnt /bin/bash <<EOF
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

# Set hostname
HOSTNAME=\$(dmidecode -s system-product-name || echo "dylanos")
echo "\$HOSTNAME" > /etc/hostname

cat <<EOL >> /etc/hosts
127.0.0.1   localhost
::1         localhost
127.0.1.1   $USER.localdomain $USER
EOL
echo "root:$PASSWORD" | chpasswd
useradd -m -G wheel -s /bin/bash $USER
echo "$USER:$PASSWORD" | chpasswd
echo "%wheel ALL=(ALL) ALL" >> /etc/sudoers
systemctl enable ntpd.service
systemctl start ntpd.service
systemctl enable lightdm
EOF

# Enabling Services
systemctl enable NetworkManager
systemctl enable dhcpcd
systemctl enable lightdm
systemctl enable wpa_supplicant
systemctl enable iwd

mkdir -p /mnt/home/$USER/.config
chown -R $USER:$USER /mnt/home/$USER/.config

# Download wallpapers from GitHub
echo "Downloading wallpapers..."
wget https://github.com/blazing803/wallpapers/archive/refs/heads/main.zip -O /tmp/wallpapers.zip || { echo "Failed to download wallpapers."; exit 1; }

# Extract wallpapers
unzip /tmp/wallpapers.zip -d /tmp || { echo "Failed to unzip wallpapers."; exit 1; }
cp -r /tmp/wallpapers-main/* /usr/share/backgrounds/ || { echo "Failed to copy wallpapers."; exit 1; }

# Clean up
rm -rf /tmp/wallpapers.zip /tmp/wallpapers-main

# Configure nitrogen to use wallpaper4.png
mkdir -p /home/$USER/.config/nitrogen
cat << EOF4 > /home/$USER/.config/nitrogen/bg-saved.cfg
[xin_-1]
file=/usr/share/backgrounds/wallpaper4.png
mode=0
bgcolor=#000000
EOF4

# Change ownership of nitrogen config
chown -R $USER:$USER /home/$USER/.config/nitrogen

# Configuration Management
git clone --depth 1 https://github.com/blazing803/configs.git /tmp/configs
copy_config() {
    local app_name="$1"
    local config_dir="$2"
    echo "Copying $app_name configuration..."
    mkdir -p "/mnt/home/$USER/.config/$config_dir"
    cp -r "/tmp/configs/$config_dir/"* "/mnt/home/$USER/.config/$config_dir/"
    chown -R "$USER:$USER" "/mnt/home/$USER/.config/$config_dir"
}
copy_config "i3" "i3"
copy_config "Plank" "plank"
rm -rf /tmp/configs

# Update /etc/os-release
echo "NAME=\"DylanOS\"" > /mnt/etc/os-release
echo "VERSION=\"4.0\"" >> /mnt/etc/os-release
echo "ID=dylanos" >> /mnt/etc/os-release
echo "ID_LIKE=arch" >> /mnt/etc/os-release

# Bootloader Installation: Install GRUB and configure it based on UEFI or BIOS
check_efi
if [ $? -eq 0 ]; then
    # UEFI system: Install GRUB and EFIBootMgr
    pacman -S --noconfirm grub efibootmgr
    # Install GRUB for UEFI systems
    grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
else
    # BIOS system: Install GRUB for legacy BIOS
    pacman -S --noconfirm grub
    # Install GRUB for BIOS systems
    grub-install --target=i386-pc --recheck "$DISK"
fi

# Generate GRUB configuration file
echo "Generating GRUB configuration..."
grub-mkconfig -o /boot/grub/grub.cfg || { echo "GRUB configuration generation failed."; exit 1; }

# Change "Arch Linux" to "DylanOS 4.0" in grub.cfg and GRUB settings
sed -i 's/GRUB_DISTRIBUTOR="Arch"/GRUB_DISTRIBUTOR="DylanOS"/' /etc/default/grub
sed -i 's/Arch Linux/DylanOS 4.0/g' /boot/grub/grub.cfg

echo "Installation complete! Please reboot."
