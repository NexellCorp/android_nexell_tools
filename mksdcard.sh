#!/bin/bash

[ $# -ne 1 ] && \
	echo "USAGE: $0 <target-device>" && \
	echo "target-device: /dev/sd?" && \
	exit 1

DEVICE=$1

BASEDIR=$(pwd)
RESULTDIR=${BASEDIR}/result
DEVICEDIR=${BASEDIR}
if [ -d "${BASEDIR}/device/nexell/lynx" ]; then
	DEVICEDIR=${BASEDIR}/device/nexell/lynx
else
	RESULTDIR=${BASEDIR}/../../../result
fi

$(dirname $0)/format-sd.sh ${DEVICE}
[ $? -ne 0 ] && \
	echo "ERROR: format failed. ${DEVICE}" && \
	exit 1

if [ ! -d mnt ]; then
	mkdir mnt
	[ $? -ne 0 ] && \
		echo "ERROR: mkdir mnt failed." && \
		exit 1
fi

sudo mount ${DEVICE}1 ./mnt
[ $? -ne 0 ] && \
	echo "ERROR: mount failed. ${DEVICE}1" && \
	exit 1

sudo rsync -ar ${RESULTDIR}/system/ ./mnt/
[ $? -ne 0 ] && \
	echo "ERROR: copy failed. system to ${DEVICE}1" && \
	exit 1

sudo cp ${RESULTDIR}/boot/* ./mnt/
[ $? -ne 0 ] && \
	echo "ERROR: copy failed. boot to ${DEVICE}1" && \
	exit 1

sync
sudo umount mnt
[ $? -ne 0 ] && \
	echo "ERROR: unmount failed. ${DEVICE}1" && \
	exit 1

sudo mount ${DEVICE}4 ./mnt
[ $? -ne 0 ] && \
	echo "ERROR: mount failed. ${DEVICE}4" && \
	exit 1

sudo rsync -ar ${RESULTDIR}/data ./mnt/
[ $? -ne 0 ] && \
	echo "ERROR: copy failed. system to ${DEVICE}4" && \
	exit 1

sync
sudo umount mnt
[ $? -ne 0 ] && \
	echo "ERROR: unmount failed. ${DEVICE}4" && \
	exit 1

sync
sudo umount ${DEVICE}[0-9]
sudo eject ${DEVICE}

[ -d mnt ] && rmdir mnt
[ $? -ne 0 ] && \
	echo "ERROR: rmdir mnt failed." && \
	exit 1

