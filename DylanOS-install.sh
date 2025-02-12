#!/bin/bash

# Display ASCII art constantly at the top
clear
cat << "EOF"
                                              
  _____        _              ____   _____   _____  ___  
 |  __ \      | |            / __ \ / ____| | ____|/ _ \ 
 | |  | |_   _| | __ _ _ __ | |  | | (___   | |__ | | | |                                            
 | |  | | | | | |/ _` | '_ \| |  | |\___ \  |___ \| | | |                                                         
 | |__| | |_| | | (_| | | | | |__| |____) |  ___) | |_| |
 |_____/ \__, |_|\__,_|_| |_|\____/|_____/  |____(_)___/ 
          __/ |                                          
         |___/ 
                 ................                 
               .+=  ....   .    -=..              
            .-. .+######-.######+   -.            
          .#= *##+=====#..#+===++*#*  #.          
         **  -%#+======#..#+=====+#%+  ==.        
        +  %%  +##+====#..#+===+###  %%  =.       
       +:.#**##  -##+==#..#+=+#%*  ###*#..=.      
      .* #*===+##. .%#+#..#*#%+  ##*===+# =.      
      * =#======+##. .%#=.#%-  ##*======#= +.     
      # *############*  ... :############# #.     
                     2023-2025
EOF

# User input prompts (moved below the ASCII art)
echo "Please answer the following prompts."

read -p "Enter the drive name (e.g., /dev/sda or /dev/nvme0n1): " drive_name
read -p "Is this an NVMe drive? (y/n): " is_nvme
read -p "Enter your timezone (e.g., America/New_York): " timezone
read -p "Enter your preferred hostname (e.g., arch): " hostname
read -p "Enter the username for your non-root user: " username
read -p "Enter the swap size in GB (e.g., 2 for 2GB): " swap_size_gb
read -p "Enter root password: " root_password
read -p "Enter $username password: " user_password

# Convert swap size from GB to MB (1 GB = 1024 MB)
swap_size=$((swap_size_gb * 1024))

# Check if required utilities are installed
required_apps=("fdisk" "git" "pacstrap" "grub" "wget" "partprobe" "mkfs.fat" "mkfs.ext4" "efibootmgr" "networkmanager" "lightdm" "lightdm-gtk-greeter" "zramctl" "chpasswd")
missing_apps=()

for app in "${required_apps[@]}"; do
    if ! command -v "$app" &> /dev/null; then
        missing_apps+=("$app")
    fi
done

if [ ${#missing_apps[@]} -gt 0 ]; then
    echo "The following required applications are missing:"
    for app in "${missing_apps[@]}"; do
        echo "- $app"
    done
    echo "Please install the missing applications before running the script."
    exit 1
fi

# Confirm partitioning
echo "Partitioning the disk $drive_name using fdisk..."
read -p "Are you sure you want to partition $drive_name? This will erase all data on the disk. (y/n): " confirm
if [[ "$confirm" != "y" ]]; then
    echo "Aborting partitioning."
    exit 1
fi

# Set partition names based on whether the drive is NVMe
if [[ "$is_nvme" == "y" || "$is_nvme" == "Y" ]]; then
    part1="${drive_name}p1"
    part2="${drive_name}p2"
else
    part1="${drive_name}1"
    part2="${drive_name}2"
fi

# Create a GPT partition table
echo -e "g\nw" | fdisk $drive_name

# Create EFI system partition (300MB, type EF00)
echo -e "n\n\n\n+300M\nt\n1\nw" | fdisk $drive_name

# Create a root partition (the rest of the disk)
echo -e "n\n\n\n\nw" | fdisk $drive_name

# Inform the OS of partition table changes
partprobe $drive_name

# Format the partitions
echo "Formatting partitions..."
if [[ "$is_nvme" == "y" || "$is_nvme" == "Y" ]]; then
    mkfs.fat -F32 $part1  # EFI system partition
    mkfs.ext4 $part2      # Root partition
else
    mkfs.fat -F32 $part1  # EFI system partition
    mkfs.ext4 $part2      # Root partition
fi

# Mount the root partition
echo "Mounting the root partition..."
mount $part2 /mnt

# Mount the EFI system partition
echo "Mounting the EFI system partition..."
mkdir /mnt/boot
mount $part1 /mnt/boot

# Install base system and additional packages
echo "Installing base system, icon theme, and additional packages..."
pacstrap /mnt base linux linux-firmware vim networkmanager sof-firmware base-devel sudo git adwaita-icon-theme grub efibootmgr lightdm lightdm-gtk-greeter zram-generator

# Install LXQt, XFCE4 panel, i3-gaps, and other utilities
echo "Installing LXQt, XFCE4 panel, i3-gaps, and other utilities..."
pacstrap /mnt lxqt-session lxqt-panel xfce4-panel i3-gaps xorg-server plank nitrogen picom pcmanfm ark firefox konsole notepadqq

# Clone the repository containing /etc/skel
echo "Cloning /etc/skel from GitHub..."
cd /tmp
git clone https://github.com/blazing803/configs.git

# Create .config folder inside /etc/skel
echo "Moving configurations to /etc/skel/.config..."
mkdir -p /etc/skel/.config
cp -r /tmp/configs/* /etc/skel/.config/

# Clean up the cloned repository
echo "Cleaning up temporary files..."
rm -rf /tmp/configs

# Download wallpapers and set them up
echo "Cloning the wallpapers repository from GitHub..."
cd /tmp
git clone https://github.com/blazing803/wallpapers.git

# Create the /usr/share/backgrounds directory if it doesn't exist
echo "Creating /usr/share/backgrounds if it doesn't already exist..."
mkdir -p /usr/share/backgrounds

# Copy the wallpapers to /usr/share/backgrounds
echo "Copying wallpapers to /usr/share/backgrounds..."
cp -r /tmp/wallpapers/* /usr/share/backgrounds/

# Clean up the cloned repository
echo "Cleaning up temporary files..."
rm -rf /tmp/wallpapers

# Download the DylanOS logo image from the updated URL
echo "Downloading DylanOS-logo.png from GitHub..."
cd /tmp
wget https://raw.githubusercontent.com/blazing803/icons/main/DylanOS-logo.png -O /tmp/DylanOS-logo.png

# Create the /usr/share/pixmaps directory if it doesn't already exist
echo "Creating /usr/share/pixmaps if it doesn't already exist..."
mkdir -p /usr/share/pixmaps

# Copy the DylanOS logo image to /usr/share/pixmaps
echo "Copying DylanOS-logo.png to /usr/share/pixmaps..."
cp /tmp/DylanOS-logo.png /usr/share/pixmaps/

# Clean up the temporary files
echo "Cleaning up temporary files..."
rm -f /tmp/DylanOS-logo.png

# Generate fstab
echo "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# Chroot into the new system
echo "Chrooting into the new system..."
arch-chroot /mnt /bin/bash <<EOF

# Set time zone
echo "Setting timezone..."
ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
hwclock --systohc

# Localization
echo "Setting locale..."
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Set hostname
echo "Setting hostname..."
echo "$hostname" > /etc/hostname
echo "127.0.1.1  $hostname.localdomain  $hostname" >> /etc/hosts

# Change OS information to DylanOS 5.0
echo "Changing OS name and version..."

# /etc/issue file
echo "DylanOS 5.0" > /etc/issue

# /etc/os-release file
cat <<EOF > /etc/os-release
NAME="DylanOS"
VERSION="5.0"
ID=dylanos
ID_LIKE=arch
PRETTY_NAME="DylanOS 5.0"
VERSION_ID="5.0"
HOME_URL="https://dylanos.com"
SUPPORT_URL="https://dylanos.com/support"
BUG_REPORT_URL="https://dylanos.com/bugs"
EOF

# Set root password using chpasswd
echo "Setting root password..."
echo "root:$root_password" | chpasswd

# Set user password using chpasswd
echo "Setting password for $username..."
echo "$username:$user_password" | chpasswd

# Create a new user
echo "Creating a new user..."
useradd -m -G wheel -s /bin/bash $username

# Add user to sudoers
echo "Allowing $username to use sudo..."
echo "$username ALL=(ALL) ALL" > /etc/sudoers.d/$username

# Enable NetworkManager service
echo "Enabling NetworkManager service..."
systemctl enable NetworkManager

# Set up ZRAM for swap
echo "Setting up ZRAM swap..."
echo -e "ZRAM_SIZE=${swap_size}M" > /etc/systemd/zram-generator.conf
systemctl enable systemd-zram-setup@zram0.service

# Install GRUB and configure it
echo "Installing GRUB bootloader..."
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=DylanOS-5.0 --recheck

# Generate GRUB configuration
echo "Generating GRUB configuration..."
grub-mkconfig -o /boot/grub/grub.cfg

# Install LightDM and LightDM GTK Greeter
echo "Enabling LightDM..."
systemctl enable lightdm.service

# Exit chroot
exit
EOF

# Unmount the partitions
echo "Unmounting partitions..."
umount -R /mnt

echo "Installation complete! Reboot and remove the installation media."
