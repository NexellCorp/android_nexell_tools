#!/bin/bash

set -e

TOP=`pwd`
export TOP 

VERBOSE=false
BOARD=
PLAT=
TOUCH_DEVICE=

SUPPORTED_TOUCH_DEVICE_LIST="aw5306_ts ft5x06_ts gslX680 ANOTHER"

function check_top()
{
    if [ ! -d .repo ]; then
        echo "You must execute this script at ANDROID TOP Directory"
        exit 1
    fi
}

function usage()
{
    echo "Usage: $0 [-b <board-name> -v -h]"
    echo -e '\n -b <board-name> : target board name (available boards: "'"$(get_available_board)"'")'
    echo " -v : if you want to view verbose log message, specify this, default no"
}

function parse_args()
{
    TEMP=`getopt -o "p:b:hv" -- "$@"`
    eval set -- "$TEMP"

    while true; do
        case "$1" in
            -b ) BOARD=$2; shift 2 ;;
            -p ) PLAT=$2; shift 2 ;;
            -h ) usage; exit 1 ;;
            -v ) VERBOSE=true; shift 1 ;;
            -- ) break ;;
            *  ) echo "invalid option $1"; usage; exit 1 ;;
        esac
    done
}

function query_touch_device()
{
    if [ -z ${TOUCH_DEVICE} ]; then
        echo "===================================="
        echo "Select Your Touch Device(If you developed your touch device driver, select ANOTHER): "
        local touch_device=
        select touch_device in ${SUPPORTED_TOUCH_DEVICE_LIST}; do
            if [ -n "${touch_device}" ]; then
                vmsg "you select ${touch_device}"
                TOUCH_DEVICE=${touch_device}
                break
            fi
        done
    fi
}

function remove_idc_file()
{
    local board=${BOARD}
    local plat=${PLAT}

    if [ -z ${board} ]; then
        board=${1}
    fi

    local idc_file=$(ls ${TOP}/device/nexell/${plat}_${board}/*.idc)
    if [ ${idc_file} ] && [ -f ${idc_file} ]; then
        rm -f ${idc_file}
    fi

    vmsg "remove ${idc_file}"
}

function remove_touch_in_devicemk()
{
    local board=${BOARD}
    local plat=${PLAT}

    if [ -z ${board} ]; then
        board=${1}
    fi

    local devicemk=${TOP}/device/nexell/${plat}_${board}/device.mk
    tac ${devicemk} | sed -e '/.idc/,+1d' | tac > /tmp/device.mk
    mv /tmp/device.mk ${devicemk}

    vmsg "remove touch idc entry in ${devicemk}"
}

function create_idc_file()
{
    local board=${BOARD}
    local plat=${PLAT}

    if [ -z ${board} ]; then
        board=${1}
    fi

    local touch_device=${TOUCH_DEVICE}
    if [ -z ${touch_device} ]; then
        touch_device=${2}
    fi

    local dest_file=${TOP}/device/nexell/${plat}_${board}/${touch_device}.idc
    echo 'touch.deviceType = touchScreen' > ${dest_file}
    echo 'touch.orientationAware = 1' >> ${dest_file}

    vmsg ${dest_file} created
}

function apply_idc_to_devicemk()
{
    local board=${BOARD}
    local plat=${PLAT}

    if [ -z ${board} ]; then
        board=${1}
    fi

    local touch_device=${TOUCH_DEVICE}
    if [ -z ${touch_device} ]; then
        touch_device=${2}
    fi

    local devicemk=${TOP}/device/nexell/${plat}_${board}/device.mk
    awk '/# touch/{print; getline; print; getline; print "PRODUCT_COPY_FILES += \\\n    device/nexell/'"${board}"'_'"${plat}"'/'"${touch_device}"'.idc:system/usr/idc/'"${touch_device}"'.idc"}1' ${devicemk} > /tmp/device.mk
    mv /tmp/device.mk ${devicemk}

    vmsg "apply ${touch_device}.idc to ${devicemk}"
}

function make_idc()
{
    remove_idc_file
    remove_touch_in_devicemk

    if [ ${TOUCH_DEVICE} == "ANOTHER" ]; then
        echo "============================================================================"
        echo "You must make your touch device's idc file manually"
        echo "idc file's name must same to <\"your touch input device's name\".idc>"
        echo "See your touch device driver's input_register_device(INPUT_DEV) call sector"
        echo "INPUT_DEV's name field is your idc file's name."
        echo "After make idc file, you must modify device.mk"
        echo "ex> your board name: myboard, your idc file name: mytouch.idc"
        echo "add next line to device.mk touch field"
        echo "PRODUCT_COPY_FILES += device/nexell/myboard/mytouch.idc:system/usr/idc/mytouch.idc"
        echo "============================================================================"
    else
        create_idc_file
        apply_idc_to_devicemk
    fi
}

#####################################################################################
check_top

source ${TOP}/device/nexell/tools/common.sh

parse_args "$@"
export VERBOSE

query_board
vmsg "BOARD: ${BOARD}"

query_touch_device
vmsg "TOUCH_DEVICE: ${TOUCH_DEVICE}"

make_idc
