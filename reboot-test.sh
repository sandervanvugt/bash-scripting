cat << REBOOT >> /root/completeme.sh
touch /tmp/after-reboot

rm -f /etc/profile
mv /etc/profile.bak /etc/profile
echo DONE
REBOOT

chmod +x /root/completeme.sh
cp /etc/profile /etc/profile.bak
echo /root/completeme.sh >> /etc/profile

reboot


