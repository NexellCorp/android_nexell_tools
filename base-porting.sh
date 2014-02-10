#!/bin/bash

# must be called at ANDROID_TOP directory 
# ./device/nexell/tools/base-porting.sh NEW_BOARD

set -e

TOP=$(pwd)

SOURCE_BOARD_NAME=pyxis
TARGET_BOARD_NAME=
ROOT_DEVICE_TYPE=
ROOT_DEVICE_SIZE="16GB"
MAIN_SDCARD_DEVICE_NUM="0"
EXTERNAL_SDCARD_DEVICE_NUM="1"
NO_CAMERA=false
NO_SENSOR=false
NO_BLUETOOTH=false
NO_SD_STORAGE=false
NO_USB_STORAGE=false
NO_OTG_STORAGE=false
VERBOSE=false

RESERVED_SIZE=1048576       # 1MB
BOOT_IMAGE_SIZE=67108864    # 64MB
SYSTEM_IMAGE_SIZE=685768704 # 654MB
CACHE_IMAGE_SIZE=553648128  # 528MB
META_DATA_SIZE=67108864
let USERDATA_IMAGE_SIZE="16*1024*1024*1024 - RESERVED_SIZE - BOOT_IMAGE_SIZE - SYSTEM_IMAGE_SIZE - CACHE_IMAGE_SIZE - META_DATA_SIZE"

SOURCE_BOARD_DIR=
TARGET_BOARD_DIR=

function usage()
{
    echo "Usage: $0 -b <your-board-name> -r <root-device-type> [-s <source-board-name> -z <root-device-size-in-GB> -m <main-sd-device-number> -e <external-sd-device-number> -n camera -n sensor -n bluetooth -n sd-storage -n usb-storage -n otg-storage]"
    echo -e '\n -b <board-name> : new board name that must be compatible with kernel plat(arch/arm/plat-nxp4330/xxx)'
    echo " -r <root-device-type> : your root device type(sd, nand, usb)"
    echo " -s <source-board-name> : board directory that you want to copy from(available boards: $(get_available_board))"
    echo " -z <root-device-size-in-GB> : root device size in GigaBytes default 16GB, range from 2GB to 64GB"
    echo " -m <main-sd-device-number> : if your root device type is sd, specify card slot number(0, 1, 2), default 0"
    echo " -e <external-sd-device-number> : if your board has external sdcard slot, specify card slot number(0, 1, 2), default 1"
    echo " -n camera : if your board don't have camera, specify this"
    echo " -n sensor : if your board don't have sensor(gyro, accelerometer ...) device, specify this"
    echo " -n bluetooth : if your board don't have bluetooth device, specify this"
    echo " -n sd-storage : if your board don't have removable sd card slot, specify this"
    echo " -n usb-storage : if your board don't have usb host port, specify this"
    echo " -n otg-storage : if you don't want to support otg host storage device, specify this"
}

function check_top()
{
    if [ ! -d .repo ]; then
        echo "You must execute this script at ANDROID TOP Directory"
        exit 1
    fi
}

function parse_args()
{
    TEMP=`getopt -o "s:b:r:z:m:e:n:hv" -- "$@"`
    eval set -- "$TEMP"

    while true; do
        case "$1" in
            -s ) SOURCE_BOARD_NAME=$2; shift 2 ;;
            -b ) TARGET_BOARD_NAME=$2; shift 2 ;;
            -r ) ROOT_DEVICE_TYPE=$2; shift 2 ;;
            -z ) ROOT_DEVICE_SIZE=$2; shift 2 ;;
            -m ) MAIN_SDCARD_DEVICE_NUM=$2; shift 2 ;;
            -e ) EXTERNAL_SDCARD_DEVICE_NUM=$2; shift 2 ;;
            -n ) case "$2" in
                    camera      ) NO_CAMERA=true ;;
                    sensor      ) NO_SENSOR=true ;;
                    bluetooth   ) NO_BLUETOOTH=true ;;
                    sd-storage  ) NO_SD_STORAGE=true ;;
                    usb-storage ) NO_USB_STORAGE=true ;;
                    otg-storage ) NO_OTG_STORAGE=true ;;
                 esac
                 shift 2 ;;
            -h ) usage; exit 1 ;;
            -v ) VERBOSE=true; shift 1 ;;
            -- ) break ;;
            *  ) echo "invalid option $1"; usage; exit 1 ;;
        esac
    done
}

function print_args()
{
    if [ ${VERBOSE} == "true" ]; then
        echo "============================================"
        echo " print args"
        echo "============================================"
        echo -e "SOURCE_BOARD_NAME:\t${SOURCE_BOARD_NAME}"
        echo -e "TARGET_BOARD_NAME:\t${TARGET_BOARD_NAME}"
        echo -e "ROOT_DEVICE_TYPE:\t${ROOT_DEVICE_TYPE}"
        echo -e "ROOT_DEVICE_SIZE:\t${ROOT_DEVICE_SIZE}"
        echo -e "MAIN_SDCARD_DEVICE_NUM:\t${MAIN_SDCARD_DEVICE_NUM}"
        echo -e "EXTERNAL_SDCARD_DEVICE_NUM:\t${EXTERNAL_SDCARD_DEVICE_NUM}"
        echo -e "NO_CAMERA:\t\t${NO_CAMERA}"
        echo -e "NO_SENSOR:\t\t${NO_SENSOR}"
        echo -e "NO_BLUETOOTH:\t\t${NO_BLUETOOTH}"
        echo -e "NO_SD_STORAGE:\t\t${NO_SD_STORAGE}"
        echo -e "NO_USB_STORAGE:\t\t${NO_USB_STORAGE}"
        echo -e "NO_OTG_STORAGE:\t\t${NO_OTG_STORAGE}"
        echo "============================================"
    fi
}

function check_source_board()
{
    SOURCE_BOARD_DIR="device/nexell/${SOURCE_BOARD_NAME}"
    if [ ${VERBOSE} == "true" ]; then
        echo -e -n "check source board directory: ${SOURCE_BOARD_DIR}...\t"
    fi
    if [ ! -d ${SOURCE_BOARD_DIR} ]; then
        echo "Fail: ${SOURCE_BOARD_DIR} is not exist!!!"
        exit 1
    fi
    if [ ${VERBOSE} == "true" ]; then
        echo "Success"
    fi
}

function check_target_board()
{
    TARGET_BOARD_DIR="device/nexell/${TARGET_BOARD_NAME}"
    if [ ${VERBOSE} == "true" ]; then
        echo -e -n "check target board directory: ${TARGET_BOARD_DIR}...\t"
    fi
    if [ -d ${TARGET_BOARD_DIR} ]; then
        echo "Fail: ${TARGET_BOARD_DIR} is exist!!!"
        exit 1
    fi
    if [ ${VERBOSE} == "true" ]; then
        echo "Success"
    fi
}

function check_root_device_type()
{
    if [ ${VERBOSE} == "true" ]; then
        echo -e -n "check root device type: ${ROOT_DEVICE_TYPE}...\t"
    fi
    case ${ROOT_DEVICE_TYPE} in
        sd   ) ;;
        nand ) ;;
        usb  ) ;;
        *    ) echo -n -e "Fail: invalid root device type ${ROOT_DEVICE_TYPE}"; echo -e ", you must select in <sd,nand,usb>"; exit 1 ;;
    esac
    if [ ${VERBOSE} == "true" ]; then
        echo "Success"
    fi
}

function check_root_device_size()
{
    if [ ${VERBOSE} == "true" ]; then
        echo -e -n "check root device size: ${ROOT_DEVICE_SIZE}...\t"
    fi

    p=`expr match "$ROOT_DEVICE_SIZE" '\([0-9]*GB\)'`
    if [ -z ${p} ]; then
        echo -e "Fail: you must set like this(-z 10GB), range(2GB ~ 64GB)"
        exit 1
    fi

    size_in_gb=${p%GB}
    echo "size_in_gb: ${size_in_gb}"
    let USERDATA_IMAGE_SIZE="${size_in_gb}*1024*1024*1024 - RESERVED_SIZE - BOOT_IMAGE_SIZE - SYSTEM_IMAGE_SIZE - CACHE_IMAGE_SIZE - META_DATA_SIZE"
    if [ ${VERBOSE} == "true" ]; then
        echo "USERDATA Size: ${USERDATA_IMAGE_SIZE}"
    fi

    if [ ${VERBOSE} == "true" ]; then
        echo "Success"
    fi
}

function check_main_sd_device_number()
{
    if [ ${ROOT_DEVICE_TYPE} == "sd" ]; then
        if [ ${VERBOSE} == "true" ]; then
            echo -e -n "check main sd device number: ${MAIN_SDCARD_DEVICE_NUM}...\t"
        fi

        # check number
        p=`echo ${MAIN_SDCARD_DEVICE_NUM} | sed -n '/[0-9]/p'`
        if [ -z ${p} ]; then
            echo -e "Fail: you must set number<0-2>"
            exit 1
        fi

        # check range
        let n="MAIN_SDCARD_DEVICE_NUM + 1"
        if [ $n -gt 3 ]; then
            echo -n -e "Fail: invalid number ${MAIN_SDCARD_DEVICE_NUM}"
            echo -e ", you must set <0~2>"
            exit 1
        fi
        if [ ${VERBOSE} == "true" ]; then
            echo "Success"
        fi
    fi
}

function check_external_sd_device_number()
{
    if [ ${NO_SD_STORAGE} == "false" ]; then
        if [ ${VERBOSE} == "true" ]; then
            echo -e -n "check external sd device number: ${EXTERNAL_SDCARD_DEVICE_NUM}...\t"
        fi

        if [ ${ROOT_DEVICE_TYPE} == "sd" ]; then
            if [ ${EXTERNAL_SDCARD_DEVICE_NUM} == ${MAIN_SDCARD_DEVICE_NUM} ]; then
                echo -e "Fail: you specify external sdcard device number same to main sdcard device number"
                exit 1
            fi
        fi

        # check number
        p=`echo ${EXTERNAL_SDCARD_DEVICE_NUM} | sed -n '/[0-9]/p'`
        if [ -z ${p} ]; then
            echo -e "Fail: you must specify number<0-2>"
            exit 1
        fi

        # check range
        let n="EXTERNAL_SDCARD_DEVICE_NUM + 1"
        if [ $n -gt 3 ]; then
            echo -n -e "Fail: invalid number ${EXTERNAL_SDCARD_DEVICE_NUM}"
            echo -e ", you must set <0~2>"
            exit 1
        fi
        if [ ${VERBOSE} == "true" ]; then
            echo "Success"
        fi
    fi
}

# copy_dir src_dir target_dir exchange_pattern
function copy_dir()
{
    # echo "$0 $1 $2 $3"
    mkdir -p ${2}

    for f in `ls ${1}`
    do
        s=`echo ${f} | sed -n "/${SOURCE_BOARD_NAME}/p"`
        if [ -z $s ]; then
            s=$f
        else
            s=${s/${SOURCE_BOARD_NAME}/${TARGET_BOARD_NAME}}
        fi
        full_src_file="${1}/${f}"
        full_dst_file="${2}/${s}"
        if [ ${VERBOSE} == "true" ]; then
            echo "${full_src_file} ====> ${full_dst_file}"
        fi
        if [ -d ${full_src_file} ]; then
            copy_dir ${full_src_file} ${full_dst_file} ${3}
        else
            sed -e ${3} ${full_src_file} > ${full_dst_file}
        fi
    done
}

function copy_source_to_target()
{
    if [ ${VERBOSE} == "true" ]; then
        echo "===================================================="
        echo "copy from ${SOURCE_BOARD_DIR} to ${TARGET_BOARD_DIR}"
        echo "===================================================="
    fi

    PATTERN="s/${SOURCE_BOARD_NAME}/${TARGET_BOARD_NAME}/g"
    copy_dir ${SOURCE_BOARD_DIR} ${TARGET_BOARD_DIR} ${PATTERN}

    if [ ${VERBOSE} == "true" ]; then
        echo "Complete"
    fi
}

function handle_root_device_size()
{
    if [ ${ROOT_DEVICE_TYPE} == "sd" ]; then
        if [ ${VERBOSE} == "true" ]; then
            echo "===================================================="
            echo "handle root device size"
            echo "===================================================="
        fi

        sed -e '/packaging/,+7d' ${TARGET_BOARD_DIR}/BoardConfig.mk > /tmp/BoardConfig.mk
        echo "" >> /tmp/BoardConfig.mk
        echo "# packaging for emmc, sd" >> /tmp/BoardConfig.mk
        echo "TARGET_USERIMAGES_USE_EXT4       := true" >> /tmp/BoardConfig.mk
        echo "BOARD_CACHEIMAGE_FILE_SYSTEM_TYPE := ext4" >> /tmp/BoardConfig.mk
        echo "BOARD_SYSTEMIMAGE_PARTITION_SIZE := ${SYSTEM_IMAGE_SIZE}" >> /tmp/BoardConfig.mk
        echo "BOARD_CACHEIMAGE_PARTITION_SIZE  := ${CACHE_IMAGE_SIZE}" >> /tmp/BoardConfig.mk
        echo "BOARD_USERDATAIMAGE_PARTITION_SIZE := ${USERDATA_IMAGE_SIZE}" >> /tmp/BoardConfig.mk
        echo "BOARD_FLASH_BLOCK_SIZE           := 4096" >> /tmp/BoardConfig.mk
        mv /tmp/BoardConfig.mk ${TARGET_BOARD_DIR}/BoardConfig.mk

        if [ ${VERBOSE} == "true" ]; then
            echo "Complete"
        fi
    fi
}

function handle_main_sd_device_number()
{
    if [ ${ROOT_DEVICE_TYPE} == "sd" ]; then
        if [ ${VERBOSE} == "true" ]; then
            echo "===================================================="
            echo "handle main sd device number"
            echo "===================================================="
        fi

        replace=`awk '{print $1}' ${TARGET_BOARD_DIR}/fstab.${TARGET_BOARD_NAME} | grep dw_mmc | awk -F'/' '{print $5}' | head -n1`
        if [ ${VERBOSE} == "true" ]; then
            echo "handle_main_sd_device_number: replace ${replace} --> dw_mmc.${MAIN_SDCARD_DEVICE_NUM}"
        fi
        sed -e "s/${replace}/dw_mmc.${MAIN_SDCARD_DEVICE_NUM}/" ${TARGET_BOARD_DIR}/fstab.${TARGET_BOARD_NAME} > /tmp/fstab.${TARGET_BOARD_NAME}
        mv /tmp/fstab.${TARGET_BOARD_NAME} ${TARGET_BOARD_DIR}/fstab.${TARGET_BOARD_NAME}

        if [ ${VERBOSE} == "true" ]; then
            echo "Complete"
        fi
    fi
}

function handle_external_sd_device_number()
{
    if [ ${NO_SD_STORAGE} == "false" ]; then
        if [ ${VERBOSE} == "true" ]; then
            echo "===================================================="
            echo "handle external sd device number"
            echo "===================================================="
        fi

        replace=`awk '{print $5}' ${TARGET_BOARD_DIR}/vold.fstab | grep dw_mmc | awk -F'/' '{print $4}'`
        if [ ${VERBOSE} == "true" ]; then
            echo "handle_external_sd_device_number: replace ${replace} --> dw_mmc.${EXTERNAL_SDCARD_DEVICE_NUM}"
        fi
        sed -e "s/${replace}/dw_mmc.${EXTERNAL_SDCARD_DEVICE_NUM}/" ${TARGET_BOARD_DIR}/vold.fstab > /tmp/vold.fstab
        mv /tmp/vold.fstab ${TARGET_BOARD_DIR}/vold.fstab

        if [ ${VERBOSE} == "true" ]; then
            echo "Complete"
        fi
    fi
}

function handle_no_camera()
{
    if [ ${NO_CAMERA} == "true" ]; then
        if [ ${VERBOSE} == "true" ]; then
            echo "===================================================="
            echo "handle no camera"
            echo "===================================================="
        fi

        rm -rf ${TARGET_BOARD_DIR}/camera

        sed -i -e 's/BOARD_HAS_CAMERA\ :=\ true/BOARD_HAS_CAMERA\ :=\ false/g' ${TARGET_BOARD_DIR}/BoardConfig.mk

        tac ${TARGET_BOARD_DIR}/device.mk  | sed -e '/camera.pyrope/,+5d' -e '/camera/d'| tac  > /tmp/device.mk
        mv /tmp/device.mk ${TARGET_BOARD_DIR}/device.mk

        if [ ${VERBOSE} == "true" ]; then
            echo "Complete"
        fi
    else
        sed -i -e 's/BOARD_HAS_CAMERA\ :=\ false/BOARD_HAS_CAMERA\ :=\ true/g' ${TARGET_BOARD_DIR}/BoardConfig.mk
    fi
}

function handle_no_sensor()
{
    if [ ${NO_SENSOR} == "true" ]; then
        if [ ${VERBOSE} == "true" ]; then
            echo "===================================================="
            echo "handle no sensor"
            echo "===================================================="
        fi

        for f in `find ${TARGET_BOARD_DIR} -name "*sensor*"`
        do
            rm -rf ${f}
        done

        sed -i -e 's/BOARD_HAS_SENSOR\ :=\ true/BOARD_HAS_SENSOR\ :=\ false/g' ${TARGET_BOARD_DIR}/BoardConfig.mk

        tac ${TARGET_BOARD_DIR}/device.mk  | sed -e "/sensors.${TARGET_BOARD_NAME}/,+5d" -e '/sensor/d'| tac  > /tmp/device.mk
        mv /tmp/device.mk ${TARGET_BOARD_DIR}/device.mk

        sed -i -e '/sensor/d' -e '/barometer/d' -e '/gyroscope/d' ${TARGET_BOARD_DIR}/tablet_core_hardware.xml

        if [ ${VERBOSE} == "true" ]; then
            echo "Complete"
        fi
    else
        sed -i -e 's/BOARD_HAS_SENSOR\ :=\ false/BOARD_HAS_SENSOR\ :=\ true/g' ${TARGET_BOARD_DIR}/BoardConfig.mk
    fi
}

function handle_no_bluetooth()
{
    if [ ${NO_BLUETOOTH} == "true" ]; then
        if [ ${VERBOSE} == "true" ]; then
            echo "===================================================="
            echo "handle no bluetooth"
            echo "===================================================="
        fi

        for f in `find ${TARGET_BOARD_DIR} -name "*bluetooth*"`
        do
            rm -rf ${f}
        done

        sed -e '/bluetooth/d' ${TARGET_BOARD_DIR}/BoardConfig.mk > ${TARGET_BOARD_DIR}/BoardConfig.mk.tmp
        mv ${TARGET_BOARD_DIR}/BoardConfig.mk.tmp ${TARGET_BOARD_DIR}/BoardConfig.mk

        sed -e '/bluetooth/d' ${TARGET_BOARD_DIR}/tablet_core_hardware.xml > /tmp/tablet_core_hardware.xml
        mv /tmp/tablet_core_hardware.xml ${TARGET_BOARD_DIR}/tablet_core_hardware.xml

        if [ ${VERBOSE} == "true" ]; then
            echo "Complete"
        fi
    fi
}

function handle_no_sd_storage()
{
    if [ ${NO_SD_STORAGE} == "true" ]; then
        if [ ${VERBOSE} == "true" ]; then
            echo "===================================================="
            echo "handle no sd storage"
            echo "===================================================="
        fi

        # vold.fstab
        sed -e '/sdcard1/d' ${TARGET_BOARD_DIR}/vold.fstab > /tmp/vold.fstab
        mv /tmp/vold.fstab ${TARGET_BOARD_DIR}/vold.fstab

        # overlay/frameworks/base/core/res/res/xml/storage_list.xml
        cat ${TARGET_BOARD_DIR}/overlay/frameworks/base/core/res/res/xml/storage_list.xml | sed -e '/external\ sdcard/,+4d' > /tmp/storage_list.xml
        mv /tmp/storage_list.xml ${TARGET_BOARD_DIR}/overlay/frameworks/base/core/res/res/xml/storage_list.xml

        if [ ${VERBOSE} == "true" ]; then
            echo "Complete"
        fi
    fi
}

function handle_no_usb_storage()
{
    if [ ${NO_USB_STORAGE} == "true" ]; then
        if [ ${VERBOSE} == "true" ]; then
            echo "===================================================="
            echo "handle no usb storage"
            echo "===================================================="
        fi

        # vold.fstab
        sed -e '/nxp4330-ehci/d' ${TARGET_BOARD_DIR}/vold.fstab > /tmp/vold.fstab
        mv /tmp/vold.fstab ${TARGET_BOARD_DIR}/vold.fstab

        # overlay/frameworks/base/core/res/res/xml/storage_list.xml
        cat ${TARGET_BOARD_DIR}/overlay/frameworks/base/core/res/res/xml/storage_list.xml | sed -e '/usb\ disk/,+4d' > /tmp/storage_list.xml
        mv /tmp/storage_list.xml ${TARGET_BOARD_DIR}/overlay/frameworks/base/core/res/res/xml/storage_list.xml

        if [ ${VERBOSE} == "true" ]; then
            echo "Complete"
        fi
    fi
}

function handle_no_otg_storage()
{
    if [ ${NO_OTG_STORAGE} == "true" ]; then
        if [ ${VERBOSE} == "true" ]; then
            echo "===================================================="
            echo "handle no otg storage"
            echo "===================================================="
        fi

        # vold.fstab
        sed -e '/dwc3-gadget/d' ${TARGET_BOARD_DIR}/vold.fstab > /tmp/vold.fstab
        mv /tmp/vold.fstab ${TARGET_BOARD_DIR}/vold.fstab

        # overlay/frameworks/base/core/res/res/xml/storage_list.xml
        cat ${TARGET_BOARD_DIR}/overlay/frameworks/base/core/res/res/xml/storage_list.xml | sed -e '/usb\ otg/,+4d' > /tmp/storage_list.xml
        mv /tmp/storage_list.xml ${TARGET_BOARD_DIR}/overlay/frameworks/base/core/res/res/xml/storage_list.xml

        if [ ${VERBOSE} == "true" ]; then
            echo "Complete"
        fi
    fi
}

check_top
source device/nexell/tools/common.sh

parse_args $@
print_args
check_source_board
check_target_board
check_root_device_type
check_root_device_size
check_main_sd_device_number
check_external_sd_device_number
copy_source_to_target
handle_root_device_size
handle_main_sd_device_number
handle_external_sd_device_number
handle_no_camera
handle_no_sensor
handle_no_bluetooth
handle_no_sd_storage
handle_no_usb_storage
handle_no_otg_storage
