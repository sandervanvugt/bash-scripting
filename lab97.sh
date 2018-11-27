#!/bin/bash

userdel -rf linda
groupdel -rf linda
groupadd -g 1101 linda
useradd -u 1101 -g 1101 linda
echo password | passwd --stdin

sed -i 's/linda:x:1101:1101::\/home\/linda:\/bin\/bash/linda:x:1101:::\/home\/linda:\/bin\/bash/' /etc/passwd
