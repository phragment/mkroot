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

BASEDIR="$(dirname "$0")"

DIR="${BASEDIR}/${SUBDIR}"

if [[ $(id -u) -ne 0 ]]
  then
    echo 'run as root'
    exit 1
fi

cd "$BASEDIR"

# check if NOTHING is mounted here anymore!
# TODO allow DIR to be a mountpoint
if [[ -e 'rootfs' ]]
  then
    if grep -qs 'rootfs' /proc/mounts
      then
        echo 'error: stuff mounted'
        exit 1
    fi
    rm -rf rootfs
fi

mkdir rootfs

mkdir -p rootfs/var/lib/pacman
mkdir -p rootfs/var/cache/pacman/pkg/

if [[ ! -d upstream ]]
  then
    mkdir upstream
fi

if [[ ! -d stuff ]]
  then
    mkdir stuff
fi

pacman -Sy base --noconfirm --noscriptlet --config upstream.conf

PKGS='base base-devel'
while read PKG
  do
    PKGS="$PKGS $PKG"
  done << INPUT
$(cat list.pkgs)
INPUT

./arm-chroot.sh bash << PRE
sed -i 's/^CheckSpace/#CheckSpace/g' /etc/pacman.conf
sed -i 's/^Color/Color/g' /etc/pacman.conf
PRE

mount -o bind upstream rootfs/var/cache/pacman/pkg/

./arm-chroot.sh pacman -S $PKGS --noconfirm || exit 1

umount rootfs/var/cache/pacman/pkg/

if [[ ! -e stuff/id_mkroot ]]
  then
    ssh-keygen -q -t ed25519 -f stuff/id_mkroot -P '' -C mkroot
fi

# qemu: Unsupported syscall: 384
# this error comes up if mkroot is run on a partition without xattr support

## post install
./arm-chroot.sh bash << POST

# hostname
echo 'alarm' > /etc/hostname

# time zone
ln -s /usr/share/zoneinfo/Europe/Berlin /etc/localtime

# locale
echo 'en_US.UTF-8 UTF-8' > /etc/locale.gen
locale-gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf
echo 'LC_COLLATE=C' >> /etc/locale.conf

# keymap
echo 'KEYMAP=de-latin1-nodeadkeys' > /etc/vconsole.conf

# I2C
# i2cdetect -F 0
# i2cdetect -y -r 0
groupadd -r i2c
echo 'KERNEL=="i2c-[0-9]*", GROUP="i2c"' > /etc/udev/rules.d/00-i2c.rules

# create system account
groupadd -r -g 1000 toor
useradd -r -u 1000 -m -g toor -G wheel,systemd-journal,power,users,i2c toor
echo toor:toor | chpasswd

# disable root account
passwd -l root

# add ssh key for user
mkdir -p /home/toor/.ssh
cat /mnt/stuff/id_mkroot.pub > /home/toor/.ssh/authorized_keys
chown -R toor:toor /home/toor/.ssh

#
yes | pwck
pwck -s
yes | grpck
grpck -s

#
cat > /etc/systemd/system/startup.target <<FOO
[Unit]
Description=Startup
Requires=multi-user.target
After=multi-user.target
Conflicts=rescue.target
AllowIsolate=yes
FOO

systemctl set-default startup

cat > /etc/systemd/system/rc-local.service <<FOO
[Unit]
Description=/etc/rc.local Compatibility
ConditionFileIsExecutable=/etc/rc.local
ConditionFileIsExecutable=/etc/rc.local.shutdown
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/etc/rc.local
ExecStop=/etc/rc.local.shutdown
TimeoutSec=0
RemainAfterExit=yes

[Install]
WantedBy=startup.target
FOO

systemctl enable rc-local.service

cat > /etc/rc.local <<EOF
#!/bin/bash

echo 'none' > /sys/class/leds/beaglebone\:green\:heartbeat/trigger
echo 'none' > /sys/class/leds/beaglebone\:green\:mmc0/trigger
echo 'none' > /sys/class/leds/beaglebone\:green\:usr2/trigger
echo 'default-on' > /sys/class/leds/beaglebone\:green\:usr3/trigger
EOF

chmod +x /etc/rc.local

cat > /etc/rc.local.shutdown <<EOF
#!/bin/bash

echo 'heartbeat' > /sys/class/leds/beaglebone\:green\:usr3/trigger
EOF

chmod +x /etc/rc.local.shutdown

# enable systemd coredump handling
echo 'kernel.core_pattern=|/usr/lib/systemd/systemd-coredump %p %u %g %s %t %e' > /etc/sysctl.d/50-coredump.conf
echo 'Storage=journal' >> /etc/systemd/coredump.conf

# persistent journal
# enabled by default
#   Storage=auto in /etc/systemd/journald.conf
#   ls /var/log
#   drwxr-sr-x 3 root systemd-journal 4.0K 1970-01-01 01:00 journal

## network
# systemd-networkd
cat > /etc/systemd/network/10-dhcp.network <<EOF
[Match]
Name=e*

[Network]
DHCP=yes

EOF
cat > /etc/systemd/network/20-static.network <<EOF
[Match]
Name=e*

[Network]
Address=192.168.1.2/24
Gateway=192.168.1.1

EOF
systemctl enable systemd-networkd.service

# this is a hack! see arm-chroot.sh
ln -fs /run/systemd/resolve/resolv.conf /etc/resolv.conf.bak
systemctl enable systemd-resolved.service

# netctl
#cat > /etc/netctl/static <<EOF
#Description='static fallback'
#Interface=eth0
#Connection=ethernet
#IP=static
#Address=('172.27.0.2/24')
#Gateway='172.27.0.1'
#DNS=('8.8.8.8' '8.8.4.4')
#SkipNoCarrier=yes
#EOF

#cat > /etc/netctl/dhcp <<EOF
#Description='default dhcp'
#Interface=eth0
#Connection=ethernet
#IP=dhcp
#EOF

#systemctl enable netctl-ifplugd@eth0.service

# dhcpcd
#sed -i 's/^require dhcp_server_identifier/#require dhcp_server_identifier/g' /etc/dhcpcd.conf

# ntp
sed -i 's/^.*Servers=.*/Servers=0.europe.pool.ntp.org 1.europe.pool.ntp.org 2.europe.pool.ntp.org 3.europe.pool.ntp.org/g' /etc/systemd/timesyncd.conf
systemctl enable systemd-timesyncd.service

# sudo
cat > /etc/sudoers.d/default <<EOF
Defaults lecture=never, editor=/usr/bin/vim
%wheel ALL=(ALL) ALL
%power ALL=(ALL) NOPASSWD: /usr/bin/poweroff, /usr/bin/reboot
EOF

# avahi
sed -i 's/^browse-domains=.*/browse-domains=/g' /etc/avahi/avahi-daemon.conf
sed -i 's/^enable-wide-area=.*/enable-wide-area=no/g' /etc/avahi/avahi-daemon.conf
sed -i 's/^.disable-user-service-publishing=.*/disable-user-service-publishing=no/g' /etc/avahi/avahi-daemon.conf
systemctl enable avahi-daemon

# nss-mdns
sed -i 's/^hosts:.*/hosts: files mdns_minimal [NOTFOUND=return] dns myhostname/g' /etc/nsswitch.conf

# openssh
sed -i 's/^.UseDNS.*/UseDNS no/g' /etc/ssh/sshd_config
sed -i 's/^.HostKey.*//g' /etc/ssh/sshd_config
cat >> /etc/ssh/sshd_config <<EOF
# enforce sane crypto (OpenSSH 6.6p1)
Protocol 2
PasswordAuthentication no
PermitEmptyPasswords no
PermitRootLogin no
StrictModes yes
HostKey /etc/ssh/ssh_host_rsa_key
HostKey /etc/ssh/ssh_host_ed25519_key
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes128-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com,hmac-sha2-512,hmac-sha2-256,hmac-ripemd160
KexAlgorithms curve25519-sha256@libssh.org,diffie-hellman-group-exchange-sha256,diffie-hellman-group14-sha1,diffie-hellman-group-exchange-sha1
EOF
systemctl enable sshd

# screen
cat > /home/toor/.screenrc <<EOF
autodetach on
startup_message off
vbell off
defscrollback 10000
caption always "%{= #000000#00FF00} %-w%{+b}%n %t%{-}%+w"
EOF
chown toor:toor /home/toor/.screenrc

# vim
cat > /home/toor/.vimrc <<EOF
set nobackup
set ignorecase
set smartcase
set noexpandtab
set wrap
set history=0
set viminfo=
set laststatus=2
syn on
set fileencodings=utf-8
set encoding=utf-8
setglobal fileencoding=utf-8
EOF
chown toor:toor /home/toor/.vimrc

# bash
cat >> /home/toor/.bashrc <<EOF

#
export HISTCONTROL=ignoreboth
export EDITOR=vim
export PAGER=vimpager
complete -cf sudo
alias ls='/usr/bin/ls -lh --group-directories-first --time-style=long-iso'
alias poweroff='sudo poweroff'
alias reboot='sudo reboot'
EOF

# fix reinstall problem with ca-certificates scriptlet
update-ca-trust

# update man page index
echo '=> updating mandb'
mandb --quiet

POST

echo '=> creating tarball...'
DATE="$(date +%Y-%m-%d)"
tar -cJpf "rootfs_${DATE}.tar.xz" rootfs --numeric-owner
ln -fs "rootfs_${DATE}.tar.xz" rootfs.tar.xz

