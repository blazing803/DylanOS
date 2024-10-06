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

echo "Starting installation in 3 seconds..."
sleep 3

# User Input Variables
read -p "Enter the disk (e.g., /dev/nvme0n1 or /dev/sda): " DISK
read -p "Is this an NVMe disk? (yes/no): " NVME_RESPONSE
read -sp "Enter your root password: " password
echo  # Move to a new line after the password prompt
read -p "Enter your username: " username
read -sp "Enter password for user $username: " user_password
echo  # Move to a new line after the user password prompt
read -p "Enter your timezone (e.g., America/New_York): " timezone

# Update the system clock
timedatectl set-ntp true

# Check disk selection
echo "You selected $DISK for installation. All data on this disk will be erased!"
read -p "Are you sure you want to proceed? (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
    echo "Installation aborted."
    exit 1
fi

# Wipe the drive and create a new GPT partition table using fdisk
echo "Wiping the drive $DISK and creating a new GPT partition table..."
if ! fdisk "$DISK" <<< $'g\nw'; then
    echo "Failed to wipe the disk and create a new GPT partition table."
    exit 1
fi

# Choose partitioning method
read -p "Choose partitioning method (1 for automatic, 2 for manual): " PARTITIONING_METHOD

if [[ "$PARTITIONING_METHOD" == "1" ]]; then
    echo "Automatically partitioning the disk..."
    
    # Define partition sizes
    EFI_SIZE="1G"  # Set size for EFI partition to 1GB
    SWAP_SIZE="4G"  # Set size for Swap partition to 4GB

    # Partition the disk with fdisk
    echo "Partitioning the disk with fdisk..."
    if ! fdisk "$DISK" <<< $'n\n\n\n\n+'"$EFI_SIZE"'\nt\n1\nn\n\n+'"$SWAP_SIZE"'\nt\n2\nn\n\n\n\nw' 2>&1; then
        echo "fdisk failed to partition the disk."
        exit 1
    fi

elif [[ "$PARTITIONING_METHOD" == "2" ]]; then
    echo "You chose manual partitioning."
    
    # Manual partitioning using cfdisk
    cfdisk "$DISK"

    # After manual partitioning, ensure the partitions are set
    if [[ "$DISK" == /dev/nvme* ]]; then
        EFI_PART="${DISK}p1"
        SWAP_PART="${DISK}p2"
        ROOT_PART="${DISK}p3"
    else
        EFI_PART="${DISK}1"
        SWAP_PART="${DISK}2"
        ROOT_PART="${DISK}3"
    fi

else
    echo "Invalid option selected. Exiting."
    exit 1
fi

# Format partitions
echo "Formatting partitions..."
mkfs.fat -F32 "$EFI_PART"  # EFI partition
mkswap "$SWAP_PART"        # Swap partition
mkfs.ext4 "$ROOT_PART"     # Root partition (the rest of the disk)

# Mount filesystem
echo "Mounting filesystem..."
mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot
mount "$EFI_PART" /mnt/boot  # Mount EFI partition
swapon "$SWAP_PART"           # Enable swap

# Install essential packages
echo "Installing essential packages..."
pacstrap -K /mnt base linux linux-firmware base-devel sof-firmware \
    i3-wm i3blocks i3status i3lock lightdm lightdm-gtk-greeter \
    pavucontrol wireless_tools gvfs wget git nano \
    htop xfce4-panel xfce4-appfinder xfce4-power-manager \
    xfce4-screenshooter xfce4-cpufreq-plugin xfce4-diskperf-plugin \
    xfce4-fsguard-plugin xfce4-mount-plugin xfce4-netload-plugin \
    xfce4-places-plugin xfce4-sensors-plugin xfce4-weather-plugin \
    xfce4-clipman-plugin xfce4-notes-plugin firefox \
    pipewire pipewire-alsa pipewire-pulse pipewire-jack \
    pipewire-media-session helvum alsa-utils \
    openssh alacritty iwd wpa_supplicant plank picom \
    networkmanager dmidecode nitrogen pavucontrol \
    unzip pcmanfm ark network-manager-applet leafpad || { \
    echo "Package installation failed."; exit 1; }

# Clone pacman.conf from GitHub
echo "Cloning pacman.conf..."
git clone https://github.com/blazing803/configs.git /tmp/configs || { \
    echo "Failed to clone pacman.conf repository."; exit 1; }

# Ensure the /mnt/etc directory exists before moving pacman.conf
mkdir -p /mnt/etc

# Move pacman.conf to /mnt/etc
mv /tmp/configs/pacman/pacman.conf /mnt/etc/pacman.conf || { \
    echo "Failed to move pacman.conf."; exit 1; }

# Clean up the cloned repository
rm -rf /tmp/configs

# Generate fstab
echo "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot into the new system
echo "Entering new system..."
arch-chroot /mnt /bin/bash <<'EOF'

# Ensure necessary directories exist
mkdir -p /etc/systemd/system/lightdm.service.d
mkdir -p /etc/systemd/system/wpa_supplicant.service.d
mkdir -p /etc/systemd/system/iwd.service.d
mkdir -p /etc/systemd/system/NetworkManager.service.d
mkdir -p /etc/systemd/system/sshd.service.d
mkdir -p /etc/systemd/system/pipewire.service.d
mkdir -p /etc/systemd/system/pipewire-pulse.service.d

# Prompt for root password
read -sp "Enter root password: " ROOT_PASSWORD
echo

# Create a new user
read -p "Enter username: " USERNAME
read -sp "Enter user password: " USER_PASSWORD
echo

# Set root password
echo "Setting root password..."
echo "root:$ROOT_PASSWORD" | chpasswd

useradd -m -G wheel "$USERNAME"
echo "$USERNAME:$USER_PASSWORD" | chpasswd

# Set timezone
ln -sf /usr/share/zoneinfo/"$timezone" /etc/localtime
hwclock --systohc

# Localization
sed -i 's/^#\(en_US\.UTF-8\)/\1/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Keymap configuration
echo "KEYMAP=us" > /etc/vconsole.conf

# Update /etc/os-release
echo "NAME=\"DylanOS\"" > /etc/os-release
echo "VERSION=\"4.0\"" >> /etc/os-release
echo "ID=dylanos" >> /etc/os-release
echo "ID_LIKE=arch" >> /etc/os-release

# Enable and start services directly with systemctl
systemctl enable lightdm
systemctl enable wpa_supplicant
systemctl enable iwd
systemctl enable NetworkManager
systemctl enable sshd
systemctl enable pipewire
systemctl enable pipewire-pulse

# Install GRUB and efibootmgr
echo "Installing GRUB and efibootmgr..."
pacman -Sy grub efibootmgr || { echo "GRUB and efibootmgr installation failed."; exit 1; }

# Install GRUB
echo "Installing GRUB..."
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=DylanOS || { echo "GRUB installation failed."; exit 1; }
grub-mkconfig -o /boot/grub/grub.cfg || { echo "GRUB configuration generation failed."; exit 1; }
sed -i 's/Arch Linux/DylanOS 4.0/g' /boot/grub/grub.cfg || { echo "Failed to update grub.cfg"; exit 1; }

# Final message
echo "Installation completed successfully! You can now proceed with your setup."

exit
EOF

