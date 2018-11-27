#!/bin/bash
#
# verified on Fedora 28 Server


# add vbox repo
rm -f /etc/yum.repos.d/vbox.repo

cat << REPO >> /etc/yum.repos.d/vbox.repo
[virtualbox]
name=Fedora $releasever - $basearch - VirtualBox
baseurl=http://download.virtualbox.org/virtualbox/rpm/fedora/\$releasever/\$basearch
enabled=1
gpgcheck=0
repo_gpgcheck=0
gpgkey=https://www.virtualbox.org/download/oracle_vbox.asc
REPO

dnf clean all
dnf upgrade

# install vbox
echo installing virtualbox
dnf install make perl kernel-devel gcc elfutils-libelf-devel -y
dnf install VirtualBox-5.2 -y
