#!/bin/sh
sudo fastboot flash partmap result/partmap.txt
sudo fastboot flash 2ndboot result/2ndboot.bin
sudo fastboot flash bootloader result/u-boot.bin
sudo fastboot flash boot result/boot.img
sudo fastboot flash system result/system.img
sudo fastboot flash cache result/cache.img
sudo fastboot flash userdata result/userdata.img
sudo fastboot reboot
