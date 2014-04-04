#!/bin/bash

SOURCE_DIR=${1}
TARGET_DIR=${2}

function usage()
{
    echo "$(basename $0) initramfs_dir target_dir"
    exit 0
}

if [ -z ${SOURCE_DIR} ] || [ -z ${TARGET_DIR} ]; then
    usage
fi

pushd $(pwd)
cd ${SOURCE_DIR}
find . | cpio -H newc -o > /tmp/initramfs.cpio
popd
out_file="$(realpath ${TARGET_DIR})/$(basename ${SOURCE_DIR}).img.gz"
echo "out_file: ${out_file}"
cat /tmp/initramfs.cpio | gzip > ${out_file}
echo "make success: ${out_file}"
