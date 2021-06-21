#!/bin/bash

# RHCSA labs grading script - SvV
# version 0.1

# verify password settings
grep 'PASS_MIN_LEN      6' /etc/login.defs >/dev/null 2>&1 || echo you did not set minimal password length to 6
grep 'PASS_MAX_DAYS     90' /etc/login.defs >/dev/null 2>&1 || echo max password validity is not set to 90 days

# verify new users
for i in anna audrey linda lisa
do
        grep $i /etc/passwd >/dev/null 2>&1 || echo user $i does not exist
done

#verify new file in user homedirs
for i in anna audrey linda lisa
do
        ls /home/$i/newfile >/dev/null 2>&1 || echo no newfile in $i home directory
done

# verify user group membership
id anna | grep profs >/dev/null 2>&1 || echo anna is not a member of group profs
id audrey | grep profs >/dev/null 2>&1 || echo audrey is not a member of group profs
id linda | grep sales >/dev/null 2>&1 || echo linda is not a member of group sales
id lisa | grep sales >/dev/null 2>&1 || echo lisa is not a member of group sales

# check that accounts linda and lisa are locked
passwd -S linda | grep locked >/dev/null 2>&1|| echo user linda password is not locked
passwd -S lisa | grep locked>/dev/null 2>&1 || echo user linda password is not locked

# evaluate passwords for anna and audrey
sshpass -p "password" ssh -o StrictHostKeyChecking=no anna@localhost exit >/dev/null 2>&1 || echo password for anna not set correctly
sshpass -p "password" ssh -o StrictHostKeyChecking=no audrey@localhost exit >/dev/null 2>&1 || echo password for audrey not set correctly

echo grading completed
