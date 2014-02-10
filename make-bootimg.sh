#!/bin/sh
PATH=out/host/linux-x86/bin:$PATH && mkuserimg.sh -s result/boot result/boot.img ext4 boot 67108864
