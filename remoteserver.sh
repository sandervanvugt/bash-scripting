#!/bin/bash

# scanning hosts on $NETWORK
echo enter the IP address of the network that you want to scan for available hosts
read NETWORK

# enabling some debugging so that we see what happens
set -x 
hosts=()
# below IFS is set at the same line as the read statement to make sure it affects the read statement only
# IFS is set to a space to make sure that as long as it finds a space after an item the script continues
while IFS= read -r line; do
	hosts+=( "$line" )
done < <( nmap -sn ${NETWORK}/24 | grep ${NETWORK%.*} | awk '{ print $5 }')
set +x

# the two lines below are for debugging only
echo press enter to continue
read

# and here we check that the array works as intended
for value in "${hosts[@]}"
do
	echo $value
done
