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

# Prompt for the required inputs upfront
echo "Please answer the following prompts."

read -p "Enter the drive name (e.g., /dev/sda or /dev/nvme0n1): " drive_name
read -p "Is this an NVMe drive? (y/n): " is_nvme
read -p "Enter your timezone (e.g., America/New_York): " timezone
read -p "Enter your preferred hostname (e.g., arch): " hostname
read -p "Enter the username for your non-root user: " username
read -p "Enter the swap file size in MB (e.g., 2048 for 2GB): " swap_size

# Confirm partitioning
echo "Partitioning the disk $drive_name using fdisk..."
read -p "Are you sure you want to partition $drive_name? This will erase all data on the disk. (y/n): " confirm
if [[ "$confirm" != "y" ]]; then
    echo "Aborting partitioning."
    exit 1
fi

# Set partition names based on whether the drive is NVMe
if [[ "$is_nvme" == "y" || "$is_nvme" == "Y" ]]; then
    # If NVMe, use 'p1', 'p2' for partitions
    part1="${drive_name}p1"
    part2="${drive_name}p2"
else
    # If SATA, use '1', '2' for partitions
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
    # For NVMe drives
    mkfs.fat -F32 $part1  # EFI system partition
    mkfs.ext4 $part2      # Root partition
else
    # For SATA drives
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
echo "Installing base system, sof-firmware, base-devel..."
pacstrap /mnt base linux linux-firmware vim networkmanager sof-firmware base-devel sudo git

# Install the additional packages you requested
echo "Installing LXQt, XFCE4 panel, i3-gaps, and other utilities..."
pacstrap /mnt lxqt-session lxqt-panel xfce4-panel i3-gaps xorg-server plank nitrogen picom pcmanfm ark firefox konsole notepadqq

# Clone the repository containing /etc/skel
echo "Cloning /etc/skel from GitHub..."
cd /tmp
git clone https://github.com/blazing803/configs.git

# Copy the contents of the skel directory to /etc/skel
echo "Copying /etc/skel from the repository..."
cp -r /tmp/configs/skel/* /etc/skel/

# Copy /etc/skel to the root user's home directory
echo "Copying /etc/skel to the root user's home directory..."
cp -r /etc/skel/* /root/

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

# Download the DylanOS logo image
echo "Downloading DylanOS-logo.png from GitHub..."
cd /tmp
wget https://github.com/blazing803/icons/raw/main/DyOS-icon.png -O /tmp/DylanOS-logo.png

# Create the /usr/share/pixmaps directory if it doesn't exist
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

# Set root password
echo "Setting root password..."
passwd

# Create a new user
echo "Creating a new user..."
useradd -m -G wheel -s /bin/bash $username

# Set password for the new user
echo "Setting password for $username..."
passwd $username

# Add user to sudoers
echo "Allowing $username to use sudo..."
echo "$username ALL=(ALL) ALL" > /etc/sudoers.d/$username

# Swap file setup
echo "Setting up swap file..."
dd if=/dev/zero of=/swapfile bs=1M count=$swap_size status=progress
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile

# Add swap entry to /etc/fstab for persistence
echo "Adding swap entry to /etc/fstab..."
echo '/swapfile none swap defaults 0 0' >> /etc/fstab

# Install systemd-boot
echo "Installing systemd-boot..."
bootctl --path=/boot install

# Create a systemd-boot entry for Arch
echo "Creating systemd-boot entry..."
cat <<EOF > /boot/loader/entries/arch.conf
title   DylanOS 5.0
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options root=PARTUUID=$(blkid -s PARTUUID -o value $part2) rw
EOF

# Enable NetworkManager service
echo "Enabling NetworkManager service..."
systemctl enable NetworkManager

# Exit chroot
exit
EOF

# Unmount the partitions
echo "Unmounting partitions..."
umount -R /mnt

echo "Installation complete! Reboot and remove the installation media."
