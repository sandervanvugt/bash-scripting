#!/bin/bash

if test -z $1
then
	echo geef een aantal minuten
	read COUNTER
else 
	COUNTER=$1
fi

COUNTER=$(( COUNTER * 60 ))

while [ $COUNTER -gt 0 ]
do
	echo deze pauze duurt nog $COUNTER seconden
	COUNTER=$(( COUNTER - 1 __
	sleep 1
done

echo de pauze is nu over, we gaan verder
