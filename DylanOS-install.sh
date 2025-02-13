#!/bin/bash

# Display ASCII art
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
                     2023-2025(2/13/2025 bata) 
EOF

# Collect user input
echo "Please answer the following prompts."

read -p "Enter the drive name (e.g., /dev/sda or /dev/nvme0n1): " drive_name
read -p "Is this an NVMe drive? (y/n): " is_nvme
read -p "Enter your timezone (e.g., America/New_York): " timezone
read -p "Enter your preferred hostname (e.g., arch): " hostname
read -p "Enter the username for your non-root user: " username

# Get root and user passwords
read -sp "Enter root password: " root_password
echo
read -sp "Enter $username password: " user_password
echo

# ZRAM swap size selection
echo "Please select the ZRAM swap size:"
echo "1) 2GB"
echo "2) 4GB"
echo "3) 8GB"
echo "4) 16GB"
read -p "Enter your choice (1, 2, 3, or 4): " swap_choice

# Map swap choice to MB value
case "$swap_choice" in
    1)
        swap_size=2048  # 2GB
        ;;
    2)
        swap_size=4096  # 4GB
        ;;
    3)
        swap_size=8192  # 8GB
        ;;
    4)
        swap_size=16384 # 16GB
        ;;
    *)
        echo "Invalid choice. Defaulting to 2GB."
        swap_size=2048  # Default to 2GB
        ;;
esac

# Check for required utilities
required_apps=("fdisk" "git" "pacstrap" "wget" "partprobe" "mkfs.fat" "mkfs.ext4" "chpasswd")
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
mkdir /mnt/boot/efi
mount $part1 /mnt/boot/efi

# Install base system and packages
echo "Installing base system..."
pacstrap -K /mnt base linux linux-firmware 

# Generate fstab
echo "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# Install other utilities
echo "Installing DylanOS base..."
pacstrap -K /mnt lxqt-session lxqt-panel \
 xfce4-panel i3-gaps xorg-server plank nitrogen \
 picom konsole git wget sudo git adwaita-icon-theme 

# Chroot into the installed system
echo "Chrooting into the new system..."    
arch-chroot /mnt << "EOF"

# Set time zone and locale
echo "Setting timezone..."
ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
hwclock --systohc

echo "Setting locale..."
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Set hostname
echo "Setting hostname..."
echo "$hostname" > /etc/hostname
echo "127.0.1.1  $hostname.localdomain  $hostname" >> /etc/hosts

# Update OS information
echo "Changing OS name and version..."

# /etc/issue file
echo "DylanOS 5.0" > /etc/issue

# /etc/os-release file
cat << "EOF" > /etc/os-release
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

# install extra DylanOS apps
pacman -S --noconfirm pcmanfm ark firefox  notepadqq vim sof-firmware base-devel

# Create /usr/share/backgrounds directory if it doesn't exist
echo "Creating /usr/share/backgrounds directory..."
mkdir -p /usr/share/backgrounds

# Clone the wallpaper repository from GitHub
echo "Cloning wallpapers from the repository..."
git clone https://github.com/blazing803/wallpapers /tmp/wallpapers

# Copy the wallpapers to /usr/share/backgrounds
echo "Copying wallpapers to /usr/share/backgrounds..."
cp -r /tmp/wallpapers/* /usr/share/backgrounds/

# Clean up the cloned repository
echo "Cleaning up..."
rm -rf /tmp/wallpapers

git clone https://github.com/blazing803/configs.git /tmp/configs
mkdir -p ~/.config
cp -r /tmp/configs/* ~/.config/
sudo cp -r ~/.config /root/
sudo cp -r ~/.config /etc/skel/

# Create a new user and give them sudo permissions
echo "Creating new user: $username..."
useradd -m -G wheel -s /bin/bash $username
echo "$username ALL=(ALL) ALL" > /etc/sudoers.d/$username

ls -la /home/ $username

# Enable NetworkManager
echo "installing and Enabling NetworkManager..."
pacman -S --noconfirm networkmanager
systemctl enable NetworkManager

# Set up ZRAM swap
echo "installing and Setting up ZRAM swap..."
pacman -S --noconfirm zram-generator
echo "ZRAM_SIZE=${swap_size}M" > /etc/systemd/zram-generator.conf
systemctl enable systemd-zram-setup@zram0.service

# Install and configure GRUB
echo "Installing and configuring GRUB..."
pacman -S --noconfirm grub efibootmgr
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=DylanOS-5.0 --recheck
grub-mkconfig -o /boot/grub/grub.cfg

# Enable LightDM
echo "installing and Enabling LightDM..."
pacman -S --noconfirm lightdm lightdm-gtk-greeter
systemctl enable lightdm.service

EOF

exit

# Unmount partitions
echo "Unmounting partitions..."
umount -R /mnt

# Function to ask if the user wants to chroot into the new system
chroot_prompt() {
    echo "Would you like to chroot into the system now? (y/n)"
    read -p "Enter your choice: " chroot_choice

    if [[ "$chroot_choice" == "y" || "$chroot_choice" == "Y" ]]; then
        echo "Chrooting into the new system..."
        mount $part2 /mnt && arch-chroot /mnt
    else
        echo "You chose not to chroot into the system."
    fi
}

echo "Installation complete! We Hope check for errors and thanks for using the bata DylanOS install script."

