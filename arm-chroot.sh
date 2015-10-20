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

SUBDIR='rootfs'

# require root
if [[ $(id -u) -ne 0 ]]
  then
    echo 'run as root'
    exit 1
fi

CMD='/bin/bash'

if [[ -n "$1" ]]
  then
    CMD="$@"
fi

BASEDIR="$(dirname "$0")"

DIR="${BASEDIR}/${SUBDIR}"

if [[ -d stuff ]]
  then
    mkdir -p "${DIR}/mnt/stuff"
    mount -o bind stuff/ "${DIR}/mnt/stuff"
fi

cd "$DIR"

install -Dm755 /usr/bin/qemu-arm-static usr/bin/qemu-arm-static

mv etc/resolv.conf etc/resolv.conf.bak
cp /etc/resolv.conf etc/

mount -t proc proc proc/
mount -t sysfs sys sys/
mount -o bind /dev dev/

chroot . $CMD

umount dev/
umount sys/
umount proc/

mv etc/resolv.conf.bak etc/resolv.conf

rm usr/bin/qemu-arm-static

cd "$BASEDIR"

if [[ -d stuff ]]
  then
    umount "${DIR}/mnt/stuff"
    rm -r "${DIR}/mnt/stuff"
fi

