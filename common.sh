#!/bin/bash

set -e

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
    if [ ! -d prebuilts/gcc/linux-x86/arm/arm-eabi-4.6/bin ]; then
        echo "Error: can't find android toolchain!!!"
        echo "Check android source"
        exit 1
    fi

    echo "PATH setting for android toolchain"
    export PATH=${TOP}/prebuilts/gcc/linux-x86/arm/arm-eabi-4.6/bin/:$PATH
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

# make ext4 image by android tool 'mkuserimg.sh'
# arg1 : board name
# arg2 : partition name
function make_ext4()
{
    local board_name=${1}
    local partition_name=${2}

    local src_file=${TOP}/device/nexell/${board_name}/BoardConfig.mk
    local partition_name_upper=$(echo ${partition_name} | tr '[[:lower:]]' '[[:upper:]]')
    local partition_size=$(grep "BOARD_${partition_name_upper}IMAGE_PARTITION_SIZE" ${src_file} | awk '{print $3}')

    vmsg "partition name: ${partition_name}, partition name upper: ${partition_name_upper}, partition_size: ${partition_size}"

    local host_out_dir="${TOP}/out/host/linux-x86"
    PATH=${host_out_dir}/bin:$PATH \
        && mkuserimg.sh -s ${RESULT_DIR}/${partition_name} ${RESULT_DIR}/${partition_name}.img ext4 ${partition_name} ${partition_size}
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

# get partition offset for nand from kernel source(arch/arm/plat-nxp4330/board_name/device.c)
# arg1 : board_name
# arg2 : partition_name
function get_offset_size_for_nand()
{
    local board_name=${1}
    local partition_name=${2}

    local src_file=${TOP}/kernel/arch/arm/plat-nxp4330/${board_name}/device.c
    local offset=$(awk '/"'"${partition_name}"'",$/{ getline; print $3}' ${src_file})

    if [ $(is_valid_number ${size_mb}) ]; then
        echo "${offset}"
    else
        echo ""
    fi
}

# get partition size for nand from kernel source(arch/arm/plat-nxp4330/board_name/device.c)
# arg1 : board_name
# arg2 : partition_name
# arg3 : nand total size in mega bytes
function get_partition_size_for_nand()
{
    local board_name=${1}
    local partition_name=${2}
    local total_size_in_mb=${3}

    local src_file=${TOP}/kernel/arch/arm/plat-nxp4330/${board_name}/device.c
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
                input=$(get_userinput_number "===> Enter your nand device's Page Size in Bytes: ")
                if [ ${input} == "invalid" ]; then
                    ${TOP}/device/nexell/tools/nand_list.sh
                    echo "You must enter only Number!!!, see upper list's PAGE tab"
                else
                    page_size=${input}
                fi
            done

            block_size=
            until [ ${block_size} ]; do
                input=$(get_userinput_number "===> Enter your nand device's Block Size in KiloBytes: ")
                if [ ${input} == "invalid" ]; then
                    ${TOP}/device/nexell/tools/nand_list.sh
                    echo "You must enter only Number!!!, see upper list's BLOCK tab"
                else
                    block_size=${input}
                fi
            done

            total_size=
            until [ ${total_size} ]; do
                input=$(get_userinput_number "===> Enter your nand device's Total Size in MegaBytes: ")
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
        if [ -z ${CHOICE} ] || [ ${CHOICE} == "y" ]; then
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

    sudo ${TOP}/device/nexell/tools/mk_ubifs.sh -p ${page_size} \
        -s ${page_size} \
        -b ${block_size} \
        -l ${partition_size} \
        -r ${RESULT_DIR}/${partition_name} \
        -i ${ubi_cfg_file} \
        -c ${RESULT_DIR} \
        -t ${TOP}/device/nexell/tools/mtd-utils \
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
    if [ -z "${1}" ]; then
        echo "Error: you must give arg1(board_name)"
        echo -n
    fi

    local src_file=${TOP}/kernel/arch/arm/plat-nxp4330/${board}/device.c
    grep back_camera ${src_file} &> /dev/null
    [ $? -eq 0 ] && let camera_number++
    grep front_camera ${src_file} &> /dev/null
    [ $? -eq 0 ] && let camera_number++
    echo -n ${camera_number}
}

function get_kernel_board_list()
{
    local src_dir=${TOP}/kernel/arch/arm/plat-nxp4330
    local boards=$(find $src_dir -maxdepth 1 -type d | awk -F'/' '{print $NF}' | sed -e '/plat-nxp4330/d' -e '/common/d')
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
