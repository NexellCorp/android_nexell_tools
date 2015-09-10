#!/bin/sh

ROOTDEV=$1
NSIH=$2
SECONDBOOT=$3
UBOOT=$4

if [ $ROOTDEV ] && [ $NSIH ] && [ $SECONDBOOT ] && [ $UBOOT ]
then
    python make-pyrope-2ndboot-download-image.py $NSIH $SECONDBOOT 2ndboot.bin
    sudo dd bs=512 seek=1 if=2ndboot.bin of=$ROOTDEV
    sudo dd bs=512 seek=35 if=$UBOOT of=$ROOTDEV
    rm -f 2ndboot.bin
else
    echo "usage: $0 sd-dev-node nsih-file secondboot-file uboot-file"
fi
