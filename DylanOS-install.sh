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

# Update the system clock
timedatectl set-ntp true

# User Input Variables
read -p "Enter the disk (e.g., /dev/nvme0n1 or /dev/sda): " DISK
read -p "Is this an NVMe disk? (yes/no): " NVME_RESPONSE
read -sp "Enter your root password: " password
echo  # To move to a new line after the password prompt
read -p "Enter your username: " username
read -sp "Enter password for user \$username: " user_password
echo  # To move to a new line after the user password prompt
read -p "Enter hostname for the system: " hostname
read -p "Enter your timezone (e.g., America/New_York): " timezone

# Update system clock
timedatectl set-ntp true

if [[ "$PARTITIONING_METHOD" == "1" ]]; then
	echo "Automatically partitioning the disk using fdisk..."
    
	# Partition the disk using fdisk
echo "Partitioning the disk with fdisk..."
if ! fdisk "$DISK" <<< $'g\nn\n\n\n+'"$EFI_SIZE"'\nt\n1\nn\n\n+'"$SWAP_SIZE"'\nt\n2\nn\n\n\n\nw' 2>&1; then
    echo "fdisk failed. Attempting to partition with parted..."
    parted "$DISK" mklabel gpt
    parted "$DISK" mkpart primary fat32 1MiB "$EFI_SIZE"
    parted "$DISK" mkpart primary linux-swap "$EFI_SIZE" "$SWAP_SIZE"
    parted "$DISK" mkpart primary ext4 "$SWAP_SIZE" 100% || { echo "Parted partitioning failed."; exit 1; }
fi

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

# Check disk selection
echo "You selected $DISK for installation. All data on this disk will be erased!"
read -p "Are you sure you want to proceed? (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
	echo "Installation aborted."
	exit 1
fi

# Format partitions
echo "Formatting partitions..."
mkfs.fat -F32 "$EFI_PART"  # EFI partition
mkswap "$SWAP_PART"     	# Swap partition
mkfs.ext4 "$ROOT_PART"  	# Root partition (the rest of the disk)

# Mount filesystem
echo "Mounting filesystem..."
mount "$ROOT_PART" /mnt
mkdir -p /mnt/boot
mount "$EFI_PART" /mnt/boot  # Mount EFI partition
swapon "$SWAP_PART"       	# Enable swap

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

# Configure PipeWire
echo "Configuring PipeWire..."
mkdir -p /etc/pipewire/media-session.d
cat <<EOL > /etc/pipewire/pipewire.conf
context.modules = [
	{   name = libpipewire-module-protocol-pulse
    	args = { socket = [ "pulseaudio.socket" ] }
	},
	{   name = libpipewire-module-protocol-native },
	{   name = libpipewire-module-client-node },
	{   name = libpipewire-module-adapter }
]
EOL

cat <<EOL > /etc/pipewire/media-session.d/media-session.conf
context {
	# Configure the default media session
	# Adjust the configuration as needed
}
EOL

# Generate fstab
echo "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot into the new system
echo "Entering new system..."
arch-chroot /mnt /bin/bash <<'EOF'

# Function to enable systemd services
enable_service() {
	if [[ -d /run/systemd/system ]]; then
    	systemctl enable "$1"
	else
    	systemctl --global enable "$1"
	fi
}

# Create service directories if they don't exist
create_service_dir() {
	local dir="/etc/systemd/system/$1"
	if [[ ! -d "$dir" ]]; then
    	mkdir -p "$dir"
    	echo "Created service directory: $dir"
	fi
}

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

# Create necessary service directories
create_service_dir "lightdm.service.d"
create_service_dir "wpa_supplicant.service.d"
create_service_dir "iwd.service.d"
create_service_dir "NetworkManager.service.d"
create_service_dir "sshd.service.d"
create_service_dir "pipewire.service.d"
create_service_dir "pipewire-pulse.service.d"

# Enable and start services
enable_service lightdm
enable_service wpa_supplicant
enable_service iwd
enable_service NetworkManager
enable_service sshd

# Enable PipeWire services
enable_service pipewire
enable_service pipewire-pulse

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

# Copy all configuration directories to .config for all users and root
echo "Setting up configuration for all users..."
CONFIG_SOURCE="/tmp/configs"

# Copy for regular users
for USER_HOME in /home/*; do
	USERNAME=$(basename "$USER_HOME")
	USER_CONFIG_DIR="$USER_HOME/.config"
    
	# Create the user's .config directory if it doesn't exist
	mkdir -p "$USER_CONFIG_DIR"
    
	# Copy all subdirectories from the configs repo to the user's .config
	cp -r "$CONFIG_SOURCE/"* "$USER_CONFIG_DIR/" || { echo "Failed to copy configurations to $USER_CONFIG_DIR"; exit 1; }
    
	# Set ownership to the user
	chown -R "$USERNAME:$USERNAME" "$USER_CONFIG_DIR"
done

# Copy configuration for the root user
ROOT_CONFIG_DIR="/root/.config"
mkdir -p "$ROOT_CONFIG_DIR"
cp -r "$CONFIG_SOURCE/"* "$ROOT_CONFIG_DIR/" || { echo "Failed to copy configurations to $ROOT_CONFIG_DIR"; exit 1; }

# Clean up the cloned configuration repository
rm -rf /tmp/configs



# Install GRUB and efibootmgr
echo "Installing GRUB and efibootmgr..."
arch-chroot /mnt pacman -Sy grub efibootmgr || { echo "GRUB and efibootmgr installation failed."; exit 1; }

# Install GRUB
echo "Installing GRUB..."
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=DylanOS || { echo "GRUB installation failed."; exit 1; }
grub-mkconfig -o /boot/grub/grub.cfg || { echo "GRUB configuration generation failed."; exit 1; }
sed -i 's/Arch Linux/DylanOS 4.0/g' /boot/grub/grub.cfg || { echo "Failed to update grub.cfg"; exit 1; }

# Final message
echo "Installation completed successfully! You can now reboot into DylanOS."

exit


