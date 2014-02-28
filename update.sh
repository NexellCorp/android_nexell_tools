#!/bin/bash

set -e

TOP=$(pwd)
FASTBOOT=${TOP}/device/nexell/tools/fastboot
RESULT_DIR=${TOP}/result
export TOP RESULT_DIR

# user option
BOOT_DEVICE_TYPE=
UPDATE_ALL=true
UPDATE_2NDBOOT=false
UPDATE_UBOOT=false
UPDATE_KERNEL=false
UPDATE_ROOTFS=false
UPDATE_BMP=false
UPDATE_BOOT=false
UPDATE_SYSTEM=false
UPDATE_USERDATA=false
UPDATE_CACHE=false
VERBOSE=false

# dynamic config
BOARD_NAME=
ROOT_DEVICE_TYPE=

function check_top()
{
    if [ ! -d ${TOP}/.repo ]; then
        echo "You must execute this script at ANDROID TOP Directory"
        exit 1
    fi
}

function usage()
{
    echo "Usage: $0 -d <boot device type> [-t 2ndboot -t u-boot -t kernel -t rootfs -t bmp -t boot -t system -t userdata -t cache -v]"
    echo -e '\n -d <boot device type> : your main boot device type(spirom, sd0, sd1, nand)'
    echo " -t 2ndboot   : update 2ndboot"
    echo " -t u-boot    : update u-boot"
    echo " -t kernel    : update kernel"
    echo " -t rootfs    : update rootfs"
    echo " -t bmp       : update bmp files in device/nexell/${BOARD_NAME}/boot/*.bmp"
    echo " -t boot      : update boot partition"
    echo " -t system    : update system partition"
    echo " -t userdata  : update userdata partition"
    echo " -t cache     : update cache partition"
    echo " -v           : print verbose message"
}

function check_fastboot()
{
    #fastboot help >& /dev/null
    #fastboot help 2> /tmp/tmp.log
    local f=$(which fastboot)
    echo "fastboot: $f, ${#f}"
    if (( ${#f} == 0 )); then
        echo "Error: can't execute fastboot!!!, Do you install android sdk properly?"
        echo "enter shell # fastboot help "
        exit 1
    fi

    vmsg "fastboot properly working..."
    echo "fastboot properly working..."
}

function check_target_device()
{
    vmsg "check target device through fastboot"
    echo "check target device through fastboot"
}

function parse_args()
{
    TEMP=`getopt -o "d:t:hv" -- "$@"`
    eval set -- "$TEMP"

    while true; do
        case "$1" in
            -d ) BOOT_DEVICE_TYPE=$2; shift 2 ;;
            -t ) case "$2" in
                    2ndboot ) UPDATE_ALL=false; UPDATE_2NDBOOT=true ;;
                    u-boot  ) UPDATE_ALL=false; UPDATE_UBOOT=true ;;
                    kernel  ) UPDATE_ALL=false; UPDATE_KERNEL=true ;;
                    rootfs  ) UPDATE_ALL=false; UPDATE_ROOTFS=true ;;
                    bmp     ) UPDATE_ALL=false; UPDATE_BMP=true ;;
                    boot    ) UPDATE_ALL=false; UPDATE_BOOT=true ;;
                    system  ) UPDATE_ALL=false; UPDATE_SYSTEM=true ;;
                    userdata) UPDATE_ALL=false; UPDATE_USERDATA=true ;;
                    cache   ) UPDATE_ALL=false; UPDATE_CACHE=true ;;
                 esac
                 shift 2 ;;
            -h ) usage; exit 1 ;;
            -v ) VERBOSE=true; shift 1 ;;
            -- ) break ;;
            *  ) echo "invalid option $1"; usage; exit 1 ;;
        esac
    done
}

function check_boot_device_type()
{
    case ${BOOT_DEVICE_TYPE} in
        spirom) ;;
        sd0) ;;
        sd1) ;;
        nand) ;;
        * ) echo "Error: invalid boot device type: ${BOOT_DEVICE_TYPE}"; exit 1 ;;
    esac

    vmsg "BOOT_DEVICE_TYPE: ${BOOT_DEVICE_TYPE}"
}

function get_board_name()
{
    local build_prop=${RESULT_DIR}/system/build.prop
    if [ ! -f ${build_prop} ]; then
        echo "Error: can't find ${build_prop} file... You must build before packaging"
        exit 1
    else
        BOARD_NAME=$(cat ${build_prop} | grep ro.build.product= | sed 's/\(ro.build.product\)=\(.*\)/\2/')
    fi

    vmsg "BOARD_NAME: ${BOARD_NAME}"
}

function is_sd_device()
{
    local f="$1"
    local tmp=$(cat $f | grep dw_mmc | head -n1)
    if (( ${#tmp} > 0 )); then
        echo "true"
    else
        echo "false"
    fi
}

function is_nand_device()
{
    local f="$1"
    local tmp=$(cat $f | grep ubi | head -n1)
    if (( ${#tmp} > 0 )); then
        echo "true"
    else
        echo "false"
    fi
}

function get_sd_device_number()
{
    local f="$1"
    local dev_num=$(cat $f | grep /system | tail -n1 | awk '{print $1}' | awk -F'/' '{print $5}')
    dev_num=$(echo ${dev_num#dw_mmc.})
    echo "sd${dev_num}"
}

function get_root_device()
{
    local fstab=${RESULT_DIR}/root/fstab.${BOARD_NAME}
    if [ ! -f ${fstab} ]; then
        echo "Error: can't find ${fstab} file... You must build before packaging"
        exit 1
    fi

    local is_sd=$(is_sd_device ${fstab})
    if [ ${is_sd} == "true" ]; then
        ROOT_DEVICE_TYPE=$(get_sd_device_number ${fstab})
    else
        local is_nand=$(is_nand_device ${fstab})
        if [ ${is_nand} == "true" ]; then
            ROOT_DEVICE_TYPE=nand
        else
            echo "Error: can't get ROOT_DEVICE_TYPE... Check ${fstab} file"
            exit 1
        fi
    fi

    vmsg "ROOT_DEVICE_TYPE: ${ROOT_DEVICE_TYPE}"
}

function flash()
{
    vmsg "flash $1 $2"
    sudo ${FASTBOOT} flash $1 $2
}

function restart_board()
{
    vmsg "restart..."
    sudo ${FASTBOOT} reboot
}

function update_2ndboot()
{
    if [ ${UPDATE_2NDBOOT} == "true" ] || [ ${UPDATE_ALL} == "true" ]; then
        #local secondboot_file=${TOP}/hardware/nexell/pyrope/boot/pyrope_2ndboot_SPI.bin
        local secondboot_file=${TOP}/linux/pyrope/boot/2ndboot/pyrope_2ndboot_${BOARD_NAME}_spi.bin
        if [ ! -f ${secondboot_file} ]; then
            local input=
            read -p "enter your secondboot file in hardware/nexell/pyrope/boot directory: " input
            if [ -z ${input} ]; then
                echo "You must enter valid file name!!!"
                exit 1
            else
                secondboot_file=${TOP}/hardware/nexell/pyrope/boot/${input}
                if [ ! -f ${secondboot_file} ]; then
                    echo "You must enter valid file name!!!"
                    exit 1
                fi
            fi
        fi

        #local nsih_file=${TOP}/hardware/nexell/pyrope/boot/NSIH_SPI.txt
        local nsih_file=${TOP}/linux/pyrope/boot/nsih/nsih_${BOARD_NAME}_spi.txt
        local secondboot_out_file=$RESULT_DIR/2ndboot.bin


        vmsg "update 2ndboot: ${secondboot_file}"
        #python ${TOP}/device/nexell/tools/make-pyrope-2ndboot-download-image.py ${nsih_file} ${secondboot_file} ${secondboot_out_file} >& /dev/null
        ${TOP}/linux/pyrope/tools/bin/nx_bingen -t 2ndboot -d other -o ${secondboot_out_file} -i ${secondboot_file} -n ${nsih_file} -l 0x40100000 -e 0x40100000
        flash 2ndboot ${secondboot_out_file}
        rm -f ${secondboot_out_file}
    fi
}

function update_bootloader()
{
    if [ ${UPDATE_UBOOT} == "true" ] || [ ${UPDATE_ALL} == "true" ]; then
        if [ ${UPDATE_UBOOT} == "true" ]; then
            cp ${TOP}/u-boot/u-boot.bin ${RESULT_DIR}
        fi

        if [ ! -f ${RESULT_DIR}/u-boot.bin ]; then
            echo "Error: can't find u-boot.bin... check build!!!"
            exit 1
        fi

        vmsg "update bootloader: ${RESULT_DIR}/u-boot.bin"
        flash bootloader ${RESULT_DIR}/u-boot.bin
    fi
}

# arg 1 : flashing force
function update_boot()
{
    if [ ${UPDATE_BOOT} == "true" ] || [ ${UPDATE_ALL} == "true" ]; then
        if [ ${UPDATE_BOOT}  == "true" ]; then
            if [ ${ROOT_DEVICE_TYPE} != "nand" ]; then
                make_ext4 ${BOARD_NAME} boot
            fi
        fi
        flash boot ${RESULT_DIR}/boot.img
    else
        if [ ${1} ]; then
            flash boot ${RESULT_DIR}/boot.img
        fi
    fi

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

function update_kernel()
{
    if [ ${UPDATE_KERNEL} == "true" ] || [ ${UPDATE_ALL} == "true" ]; then
        if [ ${UPDATE_KERNEL} == "true" ]; then
            cp ${TOP}/kernel/arch/arm/boot/uImage ${RESULT_DIR}/boot
            if [ ${ROOT_DEVICE_TYPE} != "nand" ]; then
                make_ext4 ${BOARD_NAME} boot
            fi
        fi

        if [ ! -f ${RESULT_DIR}/boot/uImage ]; then
            echo "Error: can't find uImage check build!!!"
            exit 1
        fi

        if [ ${ROOT_DEVICE_TYPE} == "nand" ]; then
            flash kernel ${RESULT_DIR}/boot/uImage
        else
            update_boot 1
        fi
    fi
}

function update_rootfs()
{
    if [ ${UPDATE_ROOTFS} == "true" ] || [ ${UPDATE_ALL} == "true" ]; then
        if [ ${UPDATE_ROOTFS} == "true" ]; then
            cd ${RESULT_DIR}
            ${TOP}/device/nexell/tools/mkramdisk.sh root 2
            mv root.img.gz ${RESULT_DIR}/boot
            cd ${TOP}

            if [ ${ROOT_DEVICE_TYPE} != "nand" ]; then
                make_ext4 ${BOARD_NAME} boot
            fi
        fi

        if [ ! -f ${RESULT_DIR}/boot/root.img.gz ]; then
            echo "Error: can't find root.img.gz check build!!!"
            exit 1
        fi

        if [ ${ROOT_DEVICE_TYPE} == "nand" ]; then
            flash ramdisk ${RESULT_DIR}/boot/root.img.gz
        else
            update_boot 1
        fi
    fi
}

function update_bmp()
{
    if [ ${UPDATE_BMP} == "true" ] || [ ${UPDATE_ALL} == "true" ]; then
        if [ ${UPDATE_BMP} == "true" ]; then
            copy_bmp_files_to_boot

            if [ ${ROOT_DEVICE_TYPE} != "nand" ]; then
                make_ext4 ${BOARD_NAME} boot
            fi
        fi

        if [ ${ROOT_DEVICE_TYPE} == "nand" ]; then
            cd ${RESULT_DIR}/boot
            local bmp_file=
            local update_file=
            for bmp_file in $(ls *.bmp)
            do
                update_file=${bmp_file%%.bmp}
                flash ${update_file} ${bmp_file}
            done
            cd ${TOP}
        else
            update_boot 1
        fi
    fi
}

function update_system()
{
    if [ ${UPDATE_SYSTEM} == "true" ] || [ ${UPDATE_ALL} == "true" ]; then
        if [ ${UPDATE_SYSTEM} == "true" ]; then
            if [ ${ROOT_DEVICE_TYPE} == "nand" ]; then
                make_ubi_image_for_nand ${BOARD_NAME} system
            else
                make_ext4 ${BOARD_NAME} system
            fi
        fi

        flash system ${RESULT_DIR}/system.img
    fi
}

function update_cache()
{
    if [ ${UPDATE_CACHE} == "true" ] || [ ${UPDATE_ALL} == "true" ]; then
        if [ ${UPDATE_CACHE} == "true" ]; then
            if [ ${ROOT_DEVICE_TYPE} == "nand" ]; then
                make_ubi_image_for_nand ${BOARD_NAME} cache
            else
                make_ext4 ${BOARD_NAME} cache
            fi
        fi

        flash cache ${RESULT_DIR}/cache.img
    fi
}

function update_userdata()
{
    if [ ${UPDATE_USERDATA} == "true" ] || [ ${UPDATE_ALL} == "true" ]; then
        if [ ${UPDATE_USERDATA} == "true" ]; then
            if [ ${ROOT_DEVICE_TYPE} == "nand" ]; then
                make_ubi_image_for_nand ${BOARD_NAME} userdata
            else
                make_ext4 ${BOARD_NAME} userdata
            fi
        fi

        flash userdata ${RESULT_DIR}/userdata.img
    fi
}

check_top
source device/nexell/tools/common.sh

parse_args $@
#export VERBOSE

check_fastboot
check_target_device
check_boot_device_type
get_board_name
get_root_device
update_2ndboot
update_bootloader
if [ ${UPDATE_KERNEL} == "true" ] || [ ${UPDATE_ALL} == "true" ]; then
    apply_kernel_initramfs
fi
if [ ${UPDATE_BOOT} == "false" ] && [ ${UPDATE_ALL} == "false" ]; then
    update_kernel
    update_rootfs
    update_bmp
else
    update_boot
fi
update_system
update_cache
update_userdata

restart_board
