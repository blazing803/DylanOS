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

# User Input Variables
read -p "Enter the disk (e.g., /dev/nvme0n1 or /dev/sda): " DISK
read -p "Choose partitioning method (1: Automatic, 2: Manual): " PARTITIONING_METHOD

# Check for root privileges
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root" 
    exit 1
fi

# Update system clock
timedatectl set-ntp true

if [[ "$PARTITIONING_METHOD" == "1" ]]; then
    echo "Automatically partitioning the disk using fdisk..."
    
    # Use fdisk to create partitions in one-liner
    echo -e "g\nn\n\n\n+1G\nt\n1\nn\n\n+4G\nt\n2\nn\n\n\n\nw" | fdisk "$DISK"

    # Define partition variables
    if [[ "$DISK" == /dev/nvme* ]]; then
        EFI_PART="${DISK}p1"
        SWAP_PART="${DISK}p2"
        ROOT_PART="${DISK}p3"
    else
        EFI_PART="${DISK}1"
        SWAP_PART="${DISK}2"
        ROOT_PART="${DISK}3"
    fi

elif [[ "$PARTITIONING_METHOD" == "2" ]]; then
    echo "You chose manual partitioning."
    # Manual partitioning using cfdisk
    cfdisk "$DISK"
    
    # Define partition variables after manual partitioning
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
mkswap "$SWAP_PART"         # Swap partition
mkfs.ext4 "$ROOT_PART"      # Root partition (the rest of the disk)

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
    openssh alacritty iwd wpa_supplicant plank picom \
    pipewire pipewire-alsa pipewire-pulse wireplumber \
    networkmanager dmidecode grub nitrogen \
    unzip efibootmgr pacmanfm ark network-manager-applet leafpad || { \
        echo "Package installation failed."; exit 1; }

# Generate fstab
echo "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot into the new system
echo "Entering new system..."
arch-chroot /mnt /bin/bash <<EOF

# Prompt for root password
read -sp "Enter root password: " ROOT_PASSWORD
echo

# Create a new user
read -p "Enter username: " USERNAME
read -sp "Enter user password: " USER_PASSWORD
echo

# Set root password
echo "Setting root password..."
echo "root:\$ROOT_PASSWORD" | chpasswd

useradd -m -G wheel "\$USERNAME"
echo "\$USERNAME:\$USER_PASSWORD" | chpasswd

# Set hostname
HOSTNAME=\$(dmidecode -s system-product-name)
echo "\$HOSTNAME" > /etc/hostname

# Enable and start services
systemctl enable lightdm
systemctl enable wpa_supplicant
systemctl enable iwd
systemctl enable NetworkManager
systemctl enable sshd

# Enable services for user sessions
systemctl --user enable --now pipewire
systemctl --user enable --now pipewire-pulse
systemctl --user enable --now wireplumber

# Ensure PipeWire is used as the default sound server
mkdir -p /etc/pipewire
cat <<EOL > /etc/pipewire/pipewire.conf
context.modules = [
    {   name = libpipewire-module-protocol-pulse
        args = { socket = [ "pulseaudio.socket" ] }
    }
]
EOL

# Set timezone
ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime
hwclock --systohc

# Localization
sed -i 's/^#\\(en_US\\.UTF-8\\)/\\1/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Keymap configuration
echo "KEYMAP=us" > /etc/vconsole.conf

# Update /etc/os-release
echo "NAME=\"DylanOS\"" > /etc/os-release
echo "VERSION=\"4.0\"" >> /etc/os-release
echo "ID=dylanos" >> /etc/os-release
echo "ID_LIKE=arch" >> /etc/os-release

# Clone configuration from GitHub
echo "Cloning configuration from GitHub..."
git clone https://github.com/blazing803/configs.git /tmp/configs || { echo "Failed to clone repository."; exit 1; }

# Set up configuration directories
declare -a CONFIG_DIRS=("xfce4" "i3" "plank" "nitrogen")
for dir in "\${CONFIG_DIRS[@]}"; do
    echo "Setting up \$dir configuration..."
    mkdir -p /home/\$USERNAME/.config/\$dir
    cp -r /tmp/configs/\$dir/* /home/\$USERNAME/.config/\$dir/ || { echo "Failed to copy \$dir configuration."; exit 1; }
    chown -R \$USERNAME:\$USERNAME /home/\$USERNAME/.config/\$dir
done

# Clone the icons repository
echo "Cloning icons repository..."
git clone https://github.com/blazing803/icons.git /tmp/icons || { echo "Failed to clone icons repository."; exit 1; }

# Copy the DyOS icon to the pixmaps directory
echo "Copying DyOS icon to /usr/share/pixmaps..."
cp /tmp/icons/DyOS-icon.png /usr/share/pixmaps/ || { echo "Failed to copy DyOS icon."; exit 1; }

# Set permissions to ensure everyone can use DyOS-icon.png
chmod 644 /usr/share/pixmaps/DyOS-icon.png || { echo "Failed to set permissions for DyOS icon."; exit 1; }

# Download wallpapers from GitHub
echo "Downloading wallpapers..."
git clone https://github.com/blazing803/wallpapers /tmp/wallpapers || { echo "Failed to clone wallpapers repository."; exit 1; }

# Ensure the wallpapers directory exists
echo "Ensuring the directory /usr/share/backgrounds exists..."
mkdir -p /usr/share/backgrounds/

# Copy wallpapers to /usr/share/backgrounds/
echo "Copying wallpapers to /usr/share/backgrounds..."
cp -r /tmp/wallpapers/* /usr/share/backgrounds/ || { echo "Failed to copy wallpapers."; exit 1; }

# Set permissions for wallpapers
chmod -R 644 /usr/share/backgrounds/* || { echo "Failed to set permissions for wallpapers."; exit 1; }

# Clean up
rm -rf /tmp/configs /tmp/wallpapers /tmp/icons

# Install GRUB
echo "Installing GRUB..."
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=DylanOS || { echo "GRUB installation failed."; exit 1; }

# Generate GRUB configuration file
echo "Generating GRUB configuration..."
grub-mkconfig -o /boot/grub/grub.cfg || { echo "GRUB configuration generation failed."; exit 1; }

# Change "Arch Linux" to "DylanOS 4.0" in grub.cfg
sed -i 's/Arch Linux/DylanOS 4.0/g' /boot/grub/grub.cfg || { echo "Failed to update grub.cfg"; exit 1; }

EOF

# Unmount and reboot
echo "Unmounting and rebooting..."
umount -R /mnt
reboot
