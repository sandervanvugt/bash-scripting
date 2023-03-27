#!/bin/bash

# exploring how to send script line output to STDERR
# first run without any arguments, will show all
# next run this script with 2> /dev/null, and it will not show the >&2 line

echo "start" >&2
echo "continuing" &>2
echo "this is an error"
echo "end"

