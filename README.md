mkroot
======

This will create an Arch Linux ARM based root filesystem tarball.

Prerequisites
-------------

The arm-chroot script uses the binfmt_misc feature of the Linux kernel.
Using Arch Linux the fastest way is to install qemu-user-static and
binfmt-qemu-static from AUR.

Ubuntu (Trusty 14.04)
sudo apt-get install binfmt-support qemu-user-static

Usage
-----

````
# ./mkroot.sh
# ./arm-install.sh /dev/sdc
````

