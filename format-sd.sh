#!/bin/bash

ROOTDEV=$1

function cleanup_sd {
	echo ""
	echo "Unmounting Partitions"
	echo ""

	NUM_MOUNTS=$(mount | grep -v none | grep "$ROOTDEV" | wc -l)

	for (( c=1; c<=$NUM_MOUNTS; c++ ))
	do  
		DRIVE=$(mount | grep -v none | grep "$ROOTDEV" | tail -1 | awk '{print $1}')
		sudo umount ${DRIVE} &> /dev/null || true
	done

	sudo dd if=/dev/zero of=$ROOTDEV bs=1M count=10
	sync
}

function format_sd()
{
	echo 
	echo '==============================================='
	echo "        Format SD: $ROOTDEV					 "
	echo '==============================================='	
	cleanup_sd
	sudo fdisk -H 255 -S 63 $ROOTDEV << END
n
p
1

+1G
n
p
2

+1G
n
p
3

+1G
n
p


w
END
	sync
	sudo mkfs.ext4 -L boot $ROOTDEV"1"
	sudo mkfs.ext4 -L system $ROOTDEV"2"
	sudo mkfs.ext4 -L cache $ROOTDEV"3"
	sudo mkfs.ext4 -L userdata $ROOTDEV"4"
	sync
}

if [ $ROOTDEV ]
then
	format_sd
else
	echo "Error!!! You must specify sd card device node (check df, normally /dev/sdb)"
	echo "Usage: $0 sdcard-device-node"
	echo "ex) $0 /dev/sdb"
fi
