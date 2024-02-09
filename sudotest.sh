#!/bin/bash

sudo -u student -i << HERE
whoami
echo i am $USER
ls
exit
HERE

echo still in script
