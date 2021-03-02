#!/bin/bash

COUNTER=$1
COUNTER=$(( COUNTER * 60 ))

minusone(){
	COUNTER=$(( COUNTER - 1 ))
	sleep 1
}

while [ $COUNTER -gt 0 ]
do
	echo you still have $COUNTER seconds left
	minusone
done

[ $COUNTER = 0 ] && echo time is up && minusone
[ $COUNTER = "-1" ] && echo you now are one second late && minusone

while true
do
	echo you now are ${COUNTER#-} seconds late
	minusone
done
