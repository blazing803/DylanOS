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

# Function to check if the system is using UEFI
check_efi() {
    if [ -d /sys/firmware/efi ]; then
        return 0  # EFI detected
    else
        return 1  # BIOS detected
    fi
}

# Check if required commands exist
check_command() {
    command -v "$1" >/dev/null 2>&1 || { echo "$1 is required but not installed. Exiting."; exit 1; }
}

# Check if required commands exist
for cmd in cfdisk git pacstrap arch-chroot; do
    check_command "$cmd"
done

# Get input for dual-booting option
read -p "Do you want to set up dual boot (yes/no)? " DUALBOOT
DUALBOOT=${DUALBOOT:-no}  # Default to no

# Get input for enabling UFW firewall
read -p "Do you want to enable UFW firewall (yes/no)? " ENABLE_UFW
ENABLE_UFW=${ENABLE_UFW:-no}  # Default to no

# Get input for timezone (optional, you can customize this as needed)
read -p "Enter your timezone (e.g., 'America/New_York'): " TIMEZONE
TIMEZONE=${TIMEZONE:-"America/New_York"}  # Default to 'America/New_York'

# Get input for username and password
read -p "Enter your username: " USER
read -sp "Enter your password: " PASSWORD
echo

# Get input for disk to install to (e.g., /dev/sda)
read -p "Enter the disk you want to install to (e.g., /dev/sda): " DISK

# Check if the system is using UEFI or BIOS
check_efi
if [ $? -eq 0 ]; then
    # EFI detected
    echo "UEFI detected. Installing systemd-boot for UEFI..."
    pacman -S --noconfirm systemd-boot efibootmgr dosfstools os-prober

    # Install systemd-boot for UEFI systems
    bootctl --path=/mnt/boot install || { echo "Failed to install systemd-boot for UEFI. Exiting."; exit 1; }

    # Generate systemd-boot configuration for EFI
    cp /mnt/boot/loader/loader.conf /mnt/boot/loader/entries/arch.conf
    echo "default arch" > /mnt/boot/loader/loader.conf
    echo "timeout 4" >> /mnt/boot/loader/loader.conf

else
    # BIOS detected
    echo "BIOS detected. Installing GRUB bootloader for BIOS..."
    pacman -S --noconfirm grub os-prober

    # Install GRUB for BIOS systems (Legacy)
    grub-install --target=i386-pc --recheck --boot-directory=/mnt/boot /dev/sda || { echo "Failed to install GRUB for BIOS. Exiting."; exit 1; }

    # Generate GRUB configuration for BIOS
    grub-mkconfig -o /mnt/boot/grub/grub.cfg || { echo "Failed to generate GRUB configuration for BIOS. Exiting."; exit 1; }

    echo "GRUB for BIOS has been installed and configured."
fi

# Partition Automation (Automatic Partitioning)
if [ "$DUALBOOT" == "yes" ]; then
    echo "Creating partitions for dual-boot setup..."
    # Here, you would create partitions for both systems. For example:
    echo -e "o\nn\np\n1\n\n+1G\nt\n1\nn\np\n2\n\n\nw" | fdisk $DISK || { echo "Failed to partition disk. Exiting."; exit 1; }
else
    echo "Creating partitions for single boot setup..."
    # Create the partitions for a single system setup.
    echo -e "o\nn\np\n1\n\n+1G\nt\n1\nn\np\n2\n\n\nw" | fdisk $DISK || { echo "Failed to partition disk. Exiting."; exit 1; }
fi

# Formatting the partitions
echo "Formatting partitions..."
mkfs.fat -F32 "$DISK"1 || { echo "Failed to format EFI partition. Exiting."; exit 1; }
mkfs.ext4 "$DISK"2 || { echo "Failed to format root partition. Exiting."; exit 1; }

# Mount partitions
echo "Mounting partitions..."
mount "$DISK"2 /mnt || { echo "Failed to mount root partition. Exiting."; exit 1; }
mkdir -p /mnt/boot
mount "$DISK"1 /mnt/boot || { echo "Failed to mount EFI partition. Exiting."; exit 1; }

# Install Arch Linux base packages using pacstrap
echo "Installing base system packages..."
pacstrap -K /mnt base linux linux-firmware base-devel sof-firmware || { echo "Failed to install base packages. Exiting."; exit 1; }

# Clone the configs repository to get pacman.conf
echo "Cloning configs repository to get pacman.conf..."
git clone --depth 1 https://github.com/blazing803/configs.git /mnt/tmp/configs || { echo "Failed to clone configs repository. Exiting."; exit 1; }

# Move pacman.conf to the correct location
mv /mnt/tmp/configs/pacman/pacman.conf /mnt/etc/pacman.conf || { echo "Failed to move pacman.conf. Exiting."; exit 1; }

# Additional packages installation (modify as necessary)
PACKAGES=(
    i3blocks lightdm lightdm-gtk-greeter pavucontrol wireless_tools gvfs i3lock
    wpa_supplicant htop nano vim i3-wm iwd openssh wget xdg-utils alacritty ark
    git xfce4-cpufreq-plugin xfce4-diskperf-plugin xfce4-fsguard-plugin
    xfce4-mount-plugin xfce4-netload-plugin xfce4-places-plugin xfce4-sensors-plugin
    xfce4-weather-plugin xfce4-clipman-plugin xfce4-notes-plugin xfce4-panel
    xfce4-appfinder xfce4-power-manager xfce4-screenshooter xorg firefox picom
    nitrogen ntp dhcpcd networkmanager dmidecode unzip leafpad pulseaudio 
    network-manager-applet plank papirus-icon-theme arc-gtk-theme vlc gimp git docker
)

# Install DylanOS packages with pacstrap
pacstrap -K /mnt "${PACKAGES[@]}" || { echo "Failed to install DylanOS packages. Exiting."; exit 1; }

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot into the installed system
arch-chroot /mnt /bin/bash <<EOF

# Set hostname
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

# Enable ZRAM swap
echo "Enabling ZRAM for swap..."
modprobe zram
echo -e "zram0\n" > /sys/block/zram0/comp_algorithm
echo "1000000000" > /sys/block/zram0/disksize
mkswap /dev/zram0
swapon /dev/zram0

# Firewall Setup (optional)
if [ "$ENABLE_UFW" == "yes" ]; then
    echo "Setting up firewall..."
    pacman -S --noconfirm ufw
    systemctl enable ufw
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow ssh
    ufw enable
else
    echo "Skipping firewall setup."
fi

# Clone configuration repositories from GitHub
echo "Cloning configuration repositories from GitHub..."
git clone --depth 1 https://github.com/blazing803/configs.git /tmp/configs || { echo "Failed to clone configuration repository. Exiting."; exit 1; }

# Function to copy configuration files
copy_config() {
	local app_name="$1"
	local config_dir="$2"
	echo "Copying $app_name configuration..."
	mkdir -p "/home/$USER/.config/$config_dir"
	cp -r "/tmp/configs/$config_dir/"* "/home/$USER/.config/$config_dir/"
	chown -R "$USER:$USER" "/home/$USER/.config/$config_dir"
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
git clone --depth 1 https://github.com/blazing803/wallpapers /tmp/wallpapers || { echo "Failed to clone wallpapers repository. Exiting."; exit 1; }

# Ensure the wallpapers directory exists
echo "Ensuring the directory /usr/share/backgrounds exists..."
mkdir -p /usr/share/backgrounds/

# Copy wallpapers to /usr/share/backgrounds/
echo "Copying wallpapers to /usr/share/backgrounds..."
cp -r /tmp/wallpapers/* /usr/share/backgrounds/ || { echo "Failed to copy wallpapers. Exiting."; exit 1; }

# Set proper permissions for the wallpapers
chmod -R 755 /usr/share/backgrounds/

# Clean up wallpapers repository
rm -rf /tmp/wallpapers

# Clone the icons repository to get the panel icon
echo "Cloning icons repository..."
git clone --depth 1 https://github.com/blazing803/icons /tmp/icons || { echo "Failed to clone icons repository. Exiting."; exit 1; }

# Ensure the directory /usr/share/pixmaps exists
echo "Ensuring the directory /usr/share/pixmaps exists..."
mkdir -p /usr/share/pixmaps/

# Copy the DyOS-icon.png to /usr/share/pixmaps
echo "Copying DyOS-icon.png to /usr/share/pixmaps..."
cp /tmp/icons/DyOS-icon.png /usr/share/pixmaps/ || { echo "Failed to copy DyOS icon. Exiting."; exit 1; }

# Set proper permissions for the icon
chmod 644 /usr/share/pixmaps/DyOS-icon.png || { echo "Failed to set permissions for DyOS icon. Exiting."; exit 1; }

# Clean up icons repository
rm -rf /tmp/icons
# Install yay or paru
read -p "Would you like to install an AUR helper (yay/paru/none)? " AUR_HELPER
AUR_HELPER=${AUR_HELPER:-none}  # Default to "none" if no input is given

if [ "$AUR_HELPER" == "yay" ]; then
    # Install yay from AUR
    git clone https://aur.archlinux.org/cgit/aur.git/commit/?h=yay /home/$USER/yay || { echo "Failed to clone yay. Exiting."; exit 1; }
    su - $USER -c "cd ~/yay && makepkg -si" || { echo "Failed to install yay. Exiting."; exit 1; }
elif [ "$AUR_HELPER" == "paru" ]; then
    # Install paru from AUR
    git clone https://aur.archlinux.org/cgit/aur.git/commit/?h=paru /home/$USER/paru || { echo "Failed to clone paru. Exiting."; exit 1; }
    su - $USER -c "cd ~/paru && makepkg -si" || { echo "Failed to install paru. Exiting."; exit 1; }
elif [ "$AUR_HELPER" == "none" ]; then
    echo "Skipping AUR helper installation."
else
    echo "Invalid option. Skipping AUR helper installation."
fi

# End of script
EOF

echo "Installation complete. Reboot into your new system!"
