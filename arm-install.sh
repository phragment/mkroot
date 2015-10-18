#!/bin/bash

# Copyright © 2014-2015 Thomas Krug
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

# check for effective user id
if [[ $(id -u) -ne 0 ]]
  then
    echo 'error: run as root'
    exit 1
fi

if [[ -e "$1" ]]
  then
    BD="$1"
  else
    echo "error: no such device $1"
    exit 1
fi

if grep -qs "$PART_BOOT" /proc/mounts
  then
    echo 'error: device is mounted'
    exit 1
fi

if [[ "$(cat /sys/block/$(basename $BD)/size)" -eq 0 ]]
  then
    echo 'error: no space on device'
    exit 1
fi

# remove partition table and uboot partition
dd if=/dev/zero of="$BD" bs=1M count=66

# create partitions
fdisk "$BD" << PART
o
n
p
1

+64M
t
e
a
n
p
2


w
PART

# find partitions (/dev/sdXY /dev/mmcblkXpY /dev/loopXpY)
# TODO is there a better way? (no screen scraping)
if [[ -e "${BD}1" ]]
  then
    BD_BOOT="${BD}1"
  else
    if [[ -e "${BD}p1" ]]
      then
        BD_BOOT="${BD}p1"
      else
        echo 'boot partition not found'
        exit 1
    fi
fi

if [[ -e "${BD}2" ]]
  then
    BD_ROOT="${BD}2"
  else
    if [[ -e "${BD}p2" ]]
      then
        BD_ROOT="${BD}p2"
      else
        echo 'root partition not found'
        exit 1
    fi
fi

#
mkfs.vfat -F 16 "$BD_BOOT"

#
mkfs.ext4 "$BD_ROOT"

# mountpoints
PART_BOOT="$(mktemp -d -t arm-install-XXX)"
PART_ROOT="$(mktemp -d -t arm-install-XXX)"

mount "$BD_BOOT" "$PART_BOOT"
mount "$BD_ROOT" "$PART_ROOT"

#
tar -xJpf rootfs.tar.xz -C "${PART_ROOT}/" --numeric-owner --strip-components=1

# TODO recheck
# mv "${PART_ROOT}/boot/*"          "${PART_BOOT}/"
mv "${PART_ROOT}/boot/MLO"        "${PART_BOOT}/"
mv "${PART_ROOT}/boot/u-boot.img" "${PART_BOOT}/"
mv "${PART_ROOT}/boot/uEnv.txt"   "${PART_BOOT}/"

sync -f "$PART_BOOT"
sync -f "$PART_ROOT"

umount "$PART_BOOT"
umount "$PART_ROOT"

# remove mountpoints if correctly unmounted
if ! mountpoint -q "$PART_BOOT"
  then
    rm -r "$PART_BOOT"
  else
    echo "$PART_BOOT still mounted"
fi

if ! mountpoint -q "$PART_ROOT"
  then
    rm -r "$PART_ROOT"
  else
    echo "$PART_ROOT still mounted"
fi

