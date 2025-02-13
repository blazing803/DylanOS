***if you are lost and don't know how to get the Dylan OS install script up and running follow the instructions below you should be running the latest Arch Linux installer ISO if you are running anything like Debian or any other Linux system that isn't the Arch Linux installer ISO from the official Arch Linux website then download that ISO and Flash it to a USB and then go back and follow the instructions once booted into the Arch Linux installer ISO I will provide instructions in case you already have a Arch Linux ISO and what to do to bypass the outdated restrictions such as things not being able to download properly***
----------------------------------------------------------------------------------------------------------------**this is the only instructions you should have to follow if you're on the latest Arch Linux installer ISO**

pacman -S dos2unix git wget

git clone https://github.com/blazing803/DylanOS

cd DylanOS

dos2unix DylanOS-install.sh

chmod +x DylanOS-install.sh

./DylanOS-install.sh
----------------------------------------------------------------------------------------------------------------
**to use an out-of-date Arch Linux ISO follow these instructions and then the instructions you would use for the latest ISO**

**find the section in your pacman.conf file that looks like below and make sure the options that are set to never in this readme file are set to never in your pac-man.conf**

use vim or nano

$textediter /etc/pacman.conf

SigLevel    = Never
LocalFileSigLevel = 
#RemoteFileSigLevel = Never
---------------------------------------------------------------------------------------------------------------
**additionally what is below this text is usually commented out you can uncomment it if you want access to more up-to-date packages but warning these packages might be unstable and might break your Dylan OS system if you're not careful but if you do want 32-bit applications but no unstable applications just don't uncomment anything with the "-testing" label**

[core-testing]
Include = /etc/pacman.d/mirrorlist

[core]
Include = /etc/pacman.d/mirrorlist

[extra-testing]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist

# If you want to run 32 bit applications on your x86_64 system,
# enable the multilib repositories as required here.

[multilib-testing]
Include = /etc/pacman.d/mirrorlist

[multilib]
Include = /etc/pacman.d/mirrorlist






