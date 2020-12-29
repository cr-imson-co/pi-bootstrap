#!/bin/bash
#
# cr.imson.co
#
# raspberry pi node bootstrapper
# @author Damian Bushong <katana@odios.us>
#

# set sane shell env options
set -o errexit -o pipefail -o noclobber -o nounset
DIR="$(dirname "$(readlink -f "$0")")"

if [ "$EUID" -ne 0 ]; then
  echo !! script must be run as root, bailing.
  exit 1
fi

set +o nounset
if [ -z "$2" ]; then
    echo usage: $0 \<hostname\> \<ansible username\>
    exit 1
fi

HOSTNAME=$1
ANSIBLE_USERNAME=$2
set -o nounset

hostnamectl set-hostname --static $HOSTNAME.cr.imson.co

groupadd --system devops
groupadd --system ssh-enabled

# create ansible deployment user, group
useradd -U -m -c "ansible" -G sudo,adm,systemd-journal,staff,ssh-enabled,devops $ANSIBLE_USERNAME
passwd --delete $ANSIBLE_USERNAME

OLD_UMASK=$(umask)
umask 0077
mkdir /home/$ANSIBLE_USERNAME/.ssh/ || true
touch /home/$ANSIBLE_USERNAME/.ssh/authorized_keys || true
curl -s https://gitlab.cr.imson.co/cr.imson.co/ssh-keys/-/raw/master/ansible_keys >> /home/$ANSIBLE_USERNAME/.ssh/authorized_keys
umask $OLD_UMASK

chown -R $ANSIBLE_USERNAME:$ANSIBLE_USERNAME /home/$ANSIBLE_USERNAME/

# create a sudoers snippet that gives the ansible user NOPASSWD use of sudo
cat << EOH > /etc/sudoers.d/01-ansible
# Allow the group "ansible" to run sudo (ALL) with NOPASSWD
%devops       ALL=(ALL)       NOPASSWD: ALL
EOH

# bare-minimum sshd hardening
cat << EOH >> /etc/sshd_config
# cr.imson.co - custom sshd config options
AllowGroups ssh-enabled
DebianBanner no
DisableForwarding yes
IgnoreRhosts yes
PasswordAuthentication no
PermitRootLogin no
EOH

cat << EOH >| /etc/motd
-------------------------------------------------------------------------------
               UNAUTHORIZED ACCESS TO THIS DEVICE IS PROHIBITED

-------------------------------------------------------------------------------

     You must have explicit, authorized permission to access this device.
      Unauthorized attempts and actions to access or use this system may
                result in civil and/or criminal penalties.

     Any activities performed on this device may be logged and monitored.

-------------------------------------------------------------------------------

EOH

systemctl enable --now ssh.service

# finally, disable the default "pi" user
usermod --shell /sbin/nologin --lock --expiredate 1 pi
