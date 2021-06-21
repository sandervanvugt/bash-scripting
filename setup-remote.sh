#!/bin/bash

# generating SSH key for local user
[ -f $HOME/.ssh/id_rsa ] || ssh-keygen

# scanning hosts on $NETWORK
echo enter the IP address of the network that you want to scan for available hosts
read NETWORK

# you can fill an array with command output in two ways. The lines below are not as efficient but also work
#hosts=()
#while IFS= read -r line; do
#	hosts+=( "$line" )
#done < <( nmap -sn ${NETWORK}/24 | grep ${NETWORK%.*} | awk '{ print $5 }')

# alternative notation
mapfile -t hosts < <(nmap -sn ${NETWORK}/24 | grep ${NETWORK%.*} | awk '{ print $5 }')

# this line shows debug information; useful while developing but can be removed now
for value in "${hosts[@]}"
do
	echo $value
done

PS3='which host do you want to setup? (Ctrl-C to quit) '
select host in "${hosts[@]}"
do
	case $host in
		*)
			echo you selected $host
			set -v
			ssh-copy-id root@$host
			scp /etc/hosts root@$host:/etc
			set +v
			echo this is enough for the proof of concept script
			;;
	esac

done

