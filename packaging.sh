#!/bin/sh

FASTBOOT_PATH=device/nexell/tools/
RESULT_DIR=result
SECONDBOOT_FILE=hardware/nexell/pyrope/boot/pyrope_2ndboot_SPI_Pyxis.bin
NSIH_FILE=hardware/nexell/pyrope/boot/NSIH.txt
SECONDBOOT_OUT_FILE=$RESULT_DIR/2ndboot.bin

python device/nexell/tools/make-pyrope-2ndboot-download-image.py $NSIH_FILE $SECONDBOOT_FILE $SECONDBOOT_OUT_FILE

sudo $FASTBOOT_PATH/fastboot flash 2ndboot $SECONDBOOT_OUT_FILE
#sudo $FASTBOOT_PATH/fastboot flash bootloader $RESULT_DIR/u-boot.bin
#sudo $FASTBOOT_PATH/fastboot flash boot $RESULT_DIR/boot.img
#sudo $FASTBOOT_PATH/fastboot flash system $RESULT_DIR/system.img
#sudo $FASTBOOT_PATH/fastboot flash cache $RESULT_DIR/cache.img
#sudo $FASTBOOT_PATH/fastboot flash userdata $RESULT_DIR/userdata.img
