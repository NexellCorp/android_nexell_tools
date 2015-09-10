#!/bin/bash

ROOTDIR=$1
SIZE=$2

dd if=/dev/zero of=$ROOTDIR.img bs=1M count=${SIZE}
sudo losetup -f $ROOTDIR.img
sudo mkfs.ext2 /dev/loop0
sleep 1
mkdir -p mnt
sudo mount -t ext2 -o loop /dev/loop0 mnt
sudo cp -a $ROOTDIR/* mnt/
sleep 1
sudo umount mnt
sleep 1
sudo losetup -d /dev/loop0
rm -rf mnt
gzip -9 $ROOTDIR.img

