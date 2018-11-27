#!/bin/bash
[ -b /dev/sdb ] || (echo  no /dev/sdb && exit)

echo this lab needs full access to /dev/sdb and will corrupt the /dev/sdb1 file system
echo press enter if that\'s OK
read

umount /dev/sdb1 >/dev/null >/dev/null
umount /dev/sdb2 >/dev/null >/dev/null

dd if=/dev/zero of=/dev/sdb bs=1M count=100 >/dev/null >/dev/null
parted --script /dev/sdb mklabel msdos mkpart primary  1MiB 200MiB >/dev/null
parted --script /dev/sdb mkpart primary 200MiB 500MiB >/dev/null

partprobe /dev/sdb >/dev/null
mkfs.ext4 /dev/sdb1 >/dev/null

dd if=/dev/zero of=/dev/sdb1 bs=1024 count=4 >/dev/null
echo b >/proc/sysrq-trigger
