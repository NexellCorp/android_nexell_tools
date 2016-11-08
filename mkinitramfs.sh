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
random=$(echo $$ | md5sum | md5sum)
tmpfile="initramfs.cpio.${random:2:8}"
find . | fakeroot cpio -H newc -o > /tmp/${tmpfile}
popd
echo "tmpfile: ${tmpfile}"
out_file="$(realpath ${TARGET_DIR})/$(basename ${SOURCE_DIR}).img.gz"
echo "out_file: ${out_file}"
cat /tmp/${tmpfile} | gzip > ${out_file}
rm -f /tmp/${tmpfile}
echo "make success: ${out_file}"
