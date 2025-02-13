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

[multilib-testing]
Include = /etc/pacman.d/mirrorlist

[multilib]
Include = /etc/pacman.d/mirrorlist
------------------------------------------------------------------------------------------------------------
**also I currently have school and the scripts may break a lot just to warn all of you that are trying out my project so if you successfully install Dylan OS let me know if anything is broken or needs to be fixed thanks
I hope you enjoy this Linux distribution it is been a Year's long project for me so let me know if you guys enjoy it anything on Arch Linux is reverse compatible if Dylan OS which means you can use the Aur the arch user repository on Dylan OS Dylan OS is not like Manjaro because Manjaro uses a modified version of the core repos Dylan OS uses the regular Arch Linux repos for everything and remember if you have problems look at the arch Wiki or directly ask me for help using GitHub requests and I will decide whether it's a Arch Linux issue or Dylan OS issue**
