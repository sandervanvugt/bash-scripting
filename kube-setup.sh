#!/bin/bash
#
# verified on Fedora Server

if grep -i fedora /etc/redhat-release
then
	echo you\'re running Fedora, good, lets continue
else
	echo you\'re on the wrong OS
	echo this script only works on Fedora
	exit 66
fi

echo press enter to continue
read

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

# configure K8s
echo installing kubectl
dnf install kubernetes-client -y
echo downloading minikube, check version
curl -Lo minikube https://storage.googleapis.com/minikube/releases/v0.28.2/minikube-linux-amd64

chmod +x minikube
cp minikube /usr/local/bin

### automatically rebooting to complete procedure

echo WARNING! This script is going to reboot now to complete the procedure
echo After reboot, log in as root to perform the final steps.
echo Press Ctrl-C now to stop this script in case you don\'t want to reboot

cat << REBOOT >> /root/completeme.sh
vboxconfig
minikube start
REBOOT

chmod +x /root/completeme.sh
cp /etc/profile /etc/profile.bak
echo /root/completeme.sh >> /etc/profile

rm -f /etc/profile
mv /etc/profile.bak /etc/profile

reboot
