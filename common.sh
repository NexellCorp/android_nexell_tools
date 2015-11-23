#!/bin/bash

set -e

#P_NAME=s5p6818
#PLAT_NAME=plat-s5p6818

function check_result()
{
    job=$1
    if [ $? -ne 0 ]; then
        echo "Error in job ${job}"
        exit 1
    fi
}

function set_android_toolchain_and_check()
{
    local toolchain_version=
    if [ ${ANDROID_VERSION_MAJOR} == "4" ]; then
        toolchain_version=4.6
    elif [ ${ANDROID_VERSION_MAJOR} == "5" ]; then
        toolchain_version=4.8
    else
        echo "ANDROID_VERSION_MAJOR is abnormal!!! ==> ${ANDROID_VERSION_MAJOR}"
        exit 1
    fi

    if [ ! -d prebuilts/gcc/linux-x86/arm/arm-eabi-${toolchain_version}/bin ]; then
        echo "Error: can't find android toolchain!!!"
        echo "Check android source"
        exit 1
    fi

    echo "PATH setting for android toolchain"
    export PATH=${TOP}/prebuilts/gcc/linux-x86/arm/arm-eabi-${toolchain_version}/bin/:$PATH
    arm-eabi-gcc -v
    if [ $? -ne 0 ]; then
        echo "Error: can't check arm-eabi-gcc"
        echo "Check android source"
        exit 1
    fi
}

function choice {
    CHOICE=''
    local prompt="$*"
    local answer
    read -p "$prompt" answer
    case "$answer" in
        [yY1] ) CHOICE='y';;
        [nN0] ) CHOICE='n';;
        *     ) CHOICE="$answer";;
    esac
} # end of function choic

function vmsg()
{
    local verbose=${VERBOSE:-"false"}
    if [ ${verbose} == "true" ]; then
        echo "$1"
    fi
}

# arg : prompt message
function get_userinput_number()
{
    local prompt="$*"
    local answer
    read -p "$prompt" answer
    case "$answer" in
        [0-9]* ) echo ${answer} ;;
        *      ) echo "invalid" ;;
    esac
}

function get_available_board()
{
    cd ${TOP}/device/nexell
    local boards=$(ls)
    boards=${boards/tools/}
    cd ${TOP}
    echo ${boards} | tr ' ' ','
}


# check board directory
function check_board_name()
{
    local board_name=${1}

    if [ -z ${board_name} ]; then
        echo "Fail: You must specify board name!!!"
        exit 1
    fi

    if [ ! -d device/nexell/${board_name} ]; then
        echo "Fail: ${board_name} is not exist at device/nexell directory"
        exit 1
    fi
}

function check_wifi_device()
{
    local wifi_device_name=${1}

    if [ ${wifi_device_name} != "rtl8188" ]; then
        if [ ${VERBOSE} == "true" ]; then
            echo ""
            echo -e -n "check wifi device: ${wifi_device_name}...\t"
        fi

        if [ ${VERBOSE} == "true" ]; then
            echo "Success"
        fi
    fi
}

# copy device's bmp files to result dir boot directory
# arg1 : board_name
function copy_bmp_files_to_boot()
{
    local board_name=${1}

    if [ -f ${TOP}/device/nexell/${board_name}/boot/logo.bmp ]; then
        cp ${TOP}/device/nexell/${board_name}/boot/logo.bmp $RESULT_DIR/boot
    fi
    if [ -f ${TOP}/device/nexell/${board_name}/boot/battery.bmp ]; then
        cp ${TOP}/device/nexell/${board_name}/boot/battery.bmp $RESULT_DIR/boot
    fi
    if [ -f ${TOP}/device/nexell/${board_name}/boot/update.bmp ]; then
        cp ${TOP}/device/nexell/${board_name}/boot/update.bmp $RESULT_DIR/boot
    fi
}

# check number
# arg1 : number
# return : "valid" or ""
function is_valid_number()
{
    local re='^[0-9]+$'
    if [ -z ${1} ] || ! [[ ${1} =~ ${re} ]] || [ ${1} -eq 0 ]; then
        echo ""
    else
        echo "valid"
    fi
}

function get_partition_size()
{
    local board_name=${1}
    local partition_name=${2}
    local src_file=${TOP}/device/nexell/${board_name}/BoardConfig.mk
    local partition_name_upper=$(echo ${partition_name} | tr '[[:lower:]]' '[[:upper:]]')
    local partition_size=$(grep "BOARD_${partition_name_upper}IMAGE_PARTITION_SIZE" ${src_file} | awk '{print $3}')
    echo -n "${partition_size}"
}

# make ext4 image by android tool 'mkuserimg.sh'
# arg1 : board name
# arg2 : partition name
# option arg3 : partition size
function make_ext4()
{
    local board_name=${1}
    local partition_name=${2}
    local partition_size=

    if [ ! -z $3 ]; then
        partition_size=${3}
    else
        local src_file=${TOP}/device/nexell/${board_name}/BoardConfig.mk
        local partition_name_upper=$(echo ${partition_name} | tr '[[:lower:]]' '[[:upper:]]')
        partition_size=$(grep "BOARD_${partition_name_upper}IMAGE_PARTITION_SIZE" ${src_file} | awk '{print $3}')
    fi

    vmsg "partition name: ${partition_name}, partition name upper: ${partition_name_upper}, partition_size: ${partition_size}"

    local android_version=$(get_android_version_major)
    if [ ${android_version} == "5" ] && [ ${partition_name} == "system" ]; then
        local host_out_dir="${TOP}/out/host/linux-x86"
        PATH=${host_out_dir}/bin:$PATH \
            && mkuserimg.sh -s ${RESULT_DIR}/${partition_name} ${RESULT_DIR}/${partition_name}.img ext4 ${partition_name} ${partition_size} ${RESULT_DIR}/root/file_contexts
    else
        local host_out_dir="${TOP}/out/host/linux-x86"
        PATH=${host_out_dir}/bin:$PATH \
            && mkuserimg.sh -s ${RESULT_DIR}/${partition_name} ${RESULT_DIR}/${partition_name}.img ext4 ${partition_name} ${partition_size}
    fi
}

# arg1 : board_name
function get_nand_sizes_from_config_file()
{
    local board_name=${1}
    local config_file=${TOP}/device/nexell/${board_name}/cfg_nand_size.ini
    if [ -f ${config_file} ]; then
        local page_size=$(awk '/page/{print $2}' ${config_file})
        local block_size=$(awk '/block/{print $2}' ${config_file})
        local total_size=$(awk '/total/{print $2}' ${config_file})
        echo "${page_size} ${block_size} ${total_size}"
    else
        echo ""
    fi
}

# arg1 : board_name
# arg2 : page size
# arg3 : block size
# arg4 : total size
function update_nand_config_file()
{
    local config_file=${TOP}/device/nexell/${board_name}/cfg_nand_size.ini
    rm -f ${config_file}
    echo "page ${page_size}" > ${config_file}
    echo "block ${block_size}" >> ${config_file}
    echo "total ${total_size}" >> ${config_file}
}

# get partition offset for nand from kernel source(arch/arm/${PLAT_NAME}/board_name/device.c)
# arg1 : board_name
# arg2 : partition_name
function get_offset_size_for_nand()
{
    local board_name=${1}
    local partition_name=${2}

    local src_file=${TOP}/kernel/arch/arm/${PLAT_NAME}/${board_name}/device.c
    local offset=$(awk '/"'"${partition_name}"'",$/{ getline; print $3}' ${src_file})

    if [ $(is_valid_number ${size_mb}) ]; then
        echo "${offset}"
    else
        echo ""
    fi
}

# get partition size for nand from kernel source(arch/arm/${PLAT_NAME}/board_name/device.c)
# arg1 : board_name
# arg2 : partition_name
# arg3 : nand total size in mega bytes
function get_partition_size_for_nand()
{
    local board_name=${1}
    local partition_name=${2}
    local total_size_in_mb=${3}

    local src_file=${TOP}/kernel/arch/arm/${PLAT_NAME}/${board_name}/device.c
    local size_mb=$(awk '/"'"${partition_name}"'",$/{ getline; getline; print $3}' ${src_file})

    if [ $(is_valid_number ${size_mb}) ]; then
        echo "${size_mb}"
    else
        # last field
        local nand_offset=0
        local system_offset=$(get_offset_size_for_nand ${board_name} system)
        if [ ${system_offset} ]; then
            let nand_offset+=system_offset
        fi
        local tmp_size=$(get_partition_size_for_nand ${board_name} system ${total_size_in_mb})
        if [ ${tmp_size} ]; then
            let nand_offset+=tmp_size
        fi
        tmp_size=$(get_partition_size_for_nand ${board_name} cache ${total_size_in_mb})
        if [ ${tmp_size} ]; then
            let nand_offset+=tmp_size
        fi
        let size_mb=total_size_in_mb-nand_offset
        echo "${size_mb}"
    fi
}

# arg1 : board_name
function query_nand_sizes()
{
    local board_name=${1}

    local page_size=
    local block_size=
    local total_size=

    local nand_sizes=$(get_nand_sizes_from_config_file ${board_name})
    if (( ${#nand_sizes} > 0 )); then
        page_size=$(echo ${nand_sizes} | awk '{print $1}')
        block_size=$(echo ${nand_sizes} | awk '{print $2}')
        total_size=$(echo ${nand_sizes} | awk '{print $3}')
    fi
    echo "${page_size} ${block_size} ${total_size}"

    local is_right=false
    until [ ${is_right} == "true" ]; do
        if [ -z ${page_size} ] || [ -z ${block_size} ] || [ -z ${total_size} ]; then
            page_size=
            until [ ${page_size} ]; do
                input=$(get_userinput_number "===> Enter your nand device's Page Size in Bytes(if you don't know, type h): ")
                if [ ${input} == "invalid" ]; then
                    ${TOP}/device/nexell/tools/nand_list.sh
                    echo "You must enter only Number!!!, see upper list's PAGE tab"
                else
                    page_size=${input}
                fi
            done

            block_size=
            until [ ${block_size} ]; do
                input=$(get_userinput_number "===> Enter your nand device's Block Size in KiloBytes(if you don't know, type h): ")
                if [ ${input} == "invalid" ]; then
                    ${TOP}/device/nexell/tools/nand_list.sh
                    echo "You must enter only Number!!!, see upper list's BLOCK tab"
                else
                    block_size=${input}
                fi
            done

            total_size=
            until [ ${total_size} ]; do
                input=$(get_userinput_number "===> Enter your nand device's Total Size in MegaBytes(if you don't know, type h): ")
                if [ ${input} == "invalid" ]; then
                    ${TOP}/device/nexell/tools/nand_list.sh
                    echo "You must enter only Number!!!, see upper list's TOTAL tab"
                else
                    total_size=${input}
                fi
            done
        fi

        printf "%-20.30s %10s %s\n" "NAND Page Size in Bytes" ":" "${page_size}"
        printf "%-20.30s %5s %s\n" "NAND Block Size in KiloBytes" ":" "${block_size}"
        printf "%-20.30s %5s %s\n" "NAND Total Size in MegaBytes" ":" "${total_size}"

        choice "is right?[Y/n] "
        if [ -z ${CHOICE} ] || [ ${CHOICE} == "y" ] || [ ${CHOICE} == "Y" ]; then
            is_right=true
        fi

        if [ ${is_right} == "false" ]; then
            page_size=
            block_size=
            total_size=
        fi
    done

    update_nand_config_file ${board_name} ${page_size} ${block_size} ${total_size}
}

# arg1 : partition_name
# arg2 : size in mega bytes
function create_tmp_ubi_cfg()
{
    local tmp_file="/tmp/tmp_ubi.cfg"
    rm -rf ${tmp_file}
    touch ${tmp_file}
    if [ ! -f ${tmp_file} ]; then
        echo "can't create tmp file for ubi cfg: ${tmp_file}"
        exit 1
    fi

    local partition=${1:?"Error, you must set partition name!!!" $(exit 1)}
    local size_mb=${2:?"Error, you must set partition size in MiB!!!" $(exit 1)}

    echo "[ubifs]" > ${tmp_file}
    echo "mode=ubi" >> ${tmp_file}
    echo "image=fs.${partition}.img" >> ${tmp_file}
    echo "vol_id=0" >> ${tmp_file}
    echo "vol_size=${size_mb}MiB" >> ${tmp_file}
    echo "vol_type=dynamic" >> ${tmp_file}
    echo "vol_name=data" >> ${tmp_file}
    echo "vol_flags=autoresize" >> ${tmp_file}

    echo ${tmp_file}
}

# arg1 : board_name
# arg2 : partition_name
function make_ubi_image_for_nand()
{
    local board_name=${1}
    local partition_name=${2}
    local nand_sizes=$(get_nand_sizes_from_config_file ${board_name})
    local page_size=$(echo ${nand_sizes} | awk '{print $1}')
    local block_size=$(echo ${nand_sizes} | awk '{print $2}')
    local total_size=$(echo ${nand_sizes} | awk '{print $3}')

    local partition_size=$(get_partition_size_for_nand ${board_name} ${partition_name} ${total_size})

    vmsg "======================="
    vmsg "make_ubi_image_for_nand"
    vmsg "board: ${board_name}, partition: ${partition_name}, page_size: ${page_size}, block_size: ${block_size}, total_size: ${total_size}, partition_size: ${partition_size}"
    vmsg "======================="

    if [ -z $(is_valid_number ${partition_size}) ]; then
        echo "invalid ${partition_name}'s size: ${partition_size}"
        exit 1
    fi

    local ubi_cfg_file=$(create_tmp_ubi_cfg ${partition_name} ${partition_size})

    sudo ${TOP}/linux/platform/${P_NAME}/tools/bin/mk_ubifs.sh \
        -p ${page_size} \
        -s ${page_size} \
        -b ${block_size} \
        -l ${partition_size} \
        -r ${RESULT_DIR}/${partition_name} \
        -i ${ubi_cfg_file} \
        -c ${RESULT_DIR} \
        -t ${TOP}/linux/platform/${P_NAME}/tools/bin/mtd-utils \
		-f ${total_size} \
        -v ${partition_name} \
        -n ${partition_name}.img

    rm -f ${RESULT_DIR}/fs.${partition_name}.img
    rm -f ${ubi_cfg_file}
}

function query_board()
{
    if [ -z ${BOARD} ]; then
        echo "===================================="
        echo "Select Your Board: "
        local boards=$(get_available_board | tr ',' ' ')
        select board in ${boards}; do
            if [ -n "${board}" ]; then
                vmsg "you select ${board}"
                BOARD=${board}
                break
            else
                echo "You must select board!!!"
            fi
        done
        echo -n
    fi
}

# arg1 : board name
function get_camera_number()
{
    local camera_number=0
    local board=${1}
	local PLAT_NAME=${2}
    if [ -z "${1}" ]; then
        echo "Error: you must give arg1(board_name)"
        echo -n
    fi
    if [ -z "${2}" ]; then
        echo "Error: you must give arg2(Platform name)"
        echo -n
    fi

    local src_file=${TOP}/kernel/arch/arm/${PLAT_NAME}/${board}/device.c
    grep back_camera ${src_file} &> /dev/null
    [ $? -eq 0 ] && let camera_number++
    grep front_camera ${src_file} &> /dev/null
    [ $? -eq 0 ] && let camera_number++
    echo -n ${camera_number}
}

function get_kernel_source_board_list()
{
    local src_dir=${TOP}/device/nexell/
    local boards=$(find $src_dir -maxdepth 1 -type d | awk -F'/' '{print $NF}' | sed -e '/tools*/d')
    echo $boards
}

function get_kernel_board_list()
{
    local src_dir=${TOP}/kernel/arch/arm/${PLAT_NAME}
    local boards=$(find $src_dir -maxdepth 1 -type d | awk -F'/' '{print $NF}' | sed -e '/'${PLAT_NAME}'/d' -e '/common/d')
    echo $boards
}

function apply_kernel_initramfs()
{
    local src_file=${TOP}/kernel/.config

    if [ ! -e ${src_file} ]; then
        echo "No kernel .config file!!!"
        exit 1
    fi

    local escape_top=$(echo ${TOP} | sed -e 's/\\/\\\\/g' -e 's/\//\\\//g')
    sed -i 's/CONFIG_INITRAMFS_SOURCE=.*/CONFIG_INITRAMFS_SOURCE=\"'${escape_top}'\/result\/root\"/g' ${src_file}
    cd ${TOP}/kernel
    yes "" | make ARCH=arm oldconfig
    make ARCH=arm uImage -j8
    cp arch/arm/boot/uImage ${RESULT_DIR}/boot
    cd ${TOP}
}

function get_sd_device_number()
{
    local f="$1"
    local dev_num=$(cat $f | grep /system | tail -n1 | awk '{print $1}' | awk -F'/' '{print $5}')
    dev_num=$(echo ${dev_num#dw_mmc.})
    echo "${dev_num}"
}

function is_valid_uImage()
{
    local uImage=${1}
    local magicword1=$(dd if=${uImage} ibs=1 count=4 | hexdump -v -e '4/1 "%02X"')
    if [ ${magicword1} == '27051956' ]; then
        echo -n "true"
    else
        echo -n "false"
    fi
}

function get_zImage()
{
     local uImage=${1}
     local zImage=/tmp/zImage
     dd if=${uImage} of=${zImage} bs=64 skip=1 2>/dev/null >/dev/null
     echo -n "${zImage}"
}

function ungzip_kernel()
{
     local zImage=${1}
     local image_gz=/tmp/kernel_image.gz
     local image=/tmp/kernel_image
     local pos=$(grep -P -a -b -m 1 --only-matching '\x1F\x8B\x08' $zImage | cut -f 1 -d :)
     if [ ! -z ${pos} ]; then
         dd if=${zImage} of=${image_gz} bs=1 skip=$pos 2>/dev/null >/dev/null
         gunzip -qf ${image_gz}
         echo -n "${image}"
     else
         echo -n "false"
     fi
}

function replace_uImage_initramfs()
{
    local src_kernel_image=${1}
    local replace_initramfs=${2}

    echo "src_kernel_image: ${src_kernel_image}, replace_initramfs: ${replace_initramfs}"
    if [ -z ${src_kernel_image} ] || [ -z ${replace_initramfs} ]; then
        echo "usage: replace_uImage_initramfs uImage_file initramfs_file"
        echo -n "false"
        return
    fi

    if [ ! -f ${src_kernel_image} ] || [ ! -f ${replace_initramfs} ]; then
        echo "invalid argument: check uImage(${src_kernel_image}) or initramfs(${replace_initramfs})"
        echo -n "false"
        return
    fi

    # checking valid uImage
    local is_uImage=$(is_valid_uImage ${src_kernel_image})
    if [ ${is_uImage} == "false" ]; then
        echo "${src_kernel_image} is not valid uImage"
        echo -n "false"
        return
    fi
    local zImage=$(get_zImage ${src_kernel_image})
    echo "zImage: ${zImage}"
    local image=$(ungzip_kernel ${zImage})
    echo "image: ${image}"

    if [ ${image} == "false" ]; then
        echo "this uImage is not compressed!!!"
        mv ${zImage} /tmp/kernel_image
        image=/tmp/kernel_image
    fi

    local cpio_start=$(grep -a -b -m 1 --only-matching '070701' ${image} | head -1 | cut -f 1 -d :)
    local cpio_end=$(grep -a -b -m 1 -o -P '\x54\x52\x41\x49\x4C\x45\x52\x21\x21\x21\x00\x00\x00\x00' ${image} | head -1 | cut -f 1 -d :)
    cpio_end=$((cpio_end + 14))
    local cpio_size=$((cpio_end - cpio_start))
    echo "cpio_start: ${cpio_start}, cpio_end: ${cpio_end}, cpio_size: ${cpio_size}"
    if [ ${cpio_size} -le '0' ]; then
        echo "This kernel image doesn't have initramfs!!!(${src_kernel_image})"
        echo -n "false"
        return
    fi

    local new_initramfs_size=$(ls -l ${replace_initramfs} | awk '{print $5}')
    if [ ${new_initramfs_size} -gt ${cpio_size} ]; then
        echo "replace initramfs size exceeds $((new_initramfs_size - cpio_size)) bytes!"
        echo -n "false"
        return
    fi

    local cpio_padding=$((cpio_size - new_initramfs_size))
    echo "cpio_padding: ${cpio_padding}"
    #dd if=/dev/zero bs=1 count=${cpio_padding} >> ${replace_initramfs} 2>/dev/null >/dev/null
    echo "padding to ${replace_initramfs} size ${cpio_padding}"
    dd if=/dev/zero bs=1 count=${cpio_padding} >> ${replace_initramfs}

    local image_new=/tmp/image_new
    #dd if=${image} bs=1 count=${cpio_start} of=${image_new} 2>/dev/null >/dev/null
    dd if=${image} bs=1 count=${cpio_start} of=${image_new}
    cat ${replace_initramfs} >> ${image_new}
    dd if=${image} bs=1 skip=${cpio_end} >> ${image_new}

    mkimage -A arm -O linux -T kernel -C none -a 40008000 -e 40008000 -d ${image_new} -n slsiap-linux-3.4.39 ${src_kernel_image}
    echo -n "true"
}

function get_cpu_variant2()
{
     board_config="device/nexell/$1/BoardConfig.mk"
     cpu_variant2=$(grep TARGET_CPU_VARIANT2 ${board_config} | awk '{print $3}')
     echo ${cpu_variant2}
}

function get_android_version_major()
{
     local version_file=${TOP}/build/core/version_defaults.mk
     local version_major=$(grep "PLATFORM_VERSION := " ${version_file} | awk '{print $3}' | awk -F. '{print $1}')
     echo ${version_major}
}

function str_to_4byte_hex()
{
    # a="12345" && b="0x${a}" && printf "%08x" $b
    local src_str=${1}
    local hex_str="0x${src_str}"
    local hex_4byte_str=$(printf "%08x" ${hex_str})
    echo -n ${hex_4byte_str}
}

function make_ecid()
{
    local ecid0=${1}
    local ecid1=${2}
    local ecid2=${3}
    local ecid3=${4}

    local hex_ecid0=$(str_to_4byte_hex ${ecid0})
    local hex_ecid1=$(str_to_4byte_hex ${ecid1})
    local hex_ecid2=$(str_to_4byte_hex ${ecid2})
    local hex_ecid3=$(str_to_4byte_hex ${ecid3})

    local ecid="${hex_ecid3}${hex_ecid2}${hex_ecid1}${hex_ecid0}"
    echo -n ${ecid}
}

function make_hdcp_keyfile()
{
    local src_file=${1}
    local dst_file=${2}
    local ecid=${3}

    local tmpfile1="/tmp/tmpfile1"
    local tmpfile2="/tmp/tmpfile2"

    dd if=${src_file} of=${tmpfile1} bs=1 count=288
    dd if=${tmpfile1} of=${tmpfile2} bs=1 count=5
    dd if=${tmpfile1} of=${tmpfile2} skip=8 seek=5 bs=1 count=280
    echo -n -e '\x00\x00\x00' >> ${tmpfile2}

    openssl enc -aes-128-ecb -e -in ${tmpfile2} -out ${dst_file}   -K "${ecid}" -salt

    rm -f ${tmpfile1}
    rm -f ${tmpfile2}
}
