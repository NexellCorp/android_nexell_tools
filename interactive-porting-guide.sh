#!/usr/bin/env bash

set -e 

TOP=$(pwd)

BOARD=
ROOT_DEVICE_TYPE=
ROOT_DEVICE_SIZE_IN_GB=
MAIN_SD_DEVICE_NUMBER=
EXTERNAL_SD_DEVICE_NUMBER=
HAS_CAMERA=
HAS_SENSOR=
HAS_BLUETOOTH=
HAS_SD_STORAGE=
HAS_USB_STORAGE=
HAS_OTG_STORAGE=

VERBOSE=true

function check_top()
{
    if [ ! -d .repo ]; then
        echo "You must execute this script at ANDROID TOP Directory"
        exit 1
    fi
}

function print_startup()
{
    printf "%b\n"  "****************************************************"
    printf "%b\n"  " INTERACTIVE Porting Guide Shell for Nexell Android"
    printf "%b\n"  "****************************************************"
    echo
}

function query_target_board()
{
    local boards=$(get_kernel_board_list)
    printf "===> %-30.30s\n" "select your target board"
    select board in ${boards}; do
        if [ -n ${board} ]; then
            BOARD=${board}
            break
        fi
    done
    vmsg "BOARD: ${BOARD}"
    echo
}

function query_root_device_type()
{
    local root_devices="sd(emmc) nand usb"
    printf "===> %-30.30s\n" "select root device type"
    select root_device in ${root_devices}; do
        if [ -n ${root_device} ]; then
            ROOT_DEVICE_TYPE=$(echo ${root_device} | cut -d'(' -f1)
            break
        fi
    done
    vmsg "ROOT_DEVICE_TYPE: ${ROOT_DEVICE_TYPE}"
    echo
}

function query_root_device_size()
{
    local root_device_sizes="4GB 8GB 16GB 32GB 64GB"
    printf "===> %-30.30s\n" "select root device size"
    select root_device_size in ${root_device_sizes}; do
        if [ -n ${root_device_size} ]; then
            ROOT_DEVICE_SIZE_IN_GB=${root_device_size}
            break
        fi
    done
    vmsg "ROOT_DEVICE_SIZE: ${ROOT_DEVICE_SIZE_IN_GB}"
    echo
}

function query_main_sd_device_number()
{
    local avail_numbers="0 1"
    printf "===> %-30.30s\n" "select main sd card(emmc) port number"
    select number in ${avail_numbers}; do
        if [ -n ${number} ]; then
            MAIN_SD_DEVICE_NUMBER=${number}
            break
        fi
    done
    vmsg "MAIN_SD_DEVICE_NUMBER: ${MAIN_SD_DEVICE_NUMBER}"
    echo
}

function query_has_camera()
{
    choice "===> ${BOARD} has camera?[Y/n] : "
    if [ ${CHOICE} == 'y' ]; then
        HAS_CAMERA=true
    else
        HAS_CAMERA=false
    fi
    vmsg "HAS_CAMERA: ${HAS_CAMERA}"
    echo
}

function query_has_sensor()
{
    choice "===> ${BOARD} has sensor?[Y/n] : "
    if [ ${CHOICE} == 'y' ]; then
        HAS_SENSOR=true
    else
        HAS_SENSOR=false
    fi
    vmsg "HAS_SENSOR: ${HAS_SENSOR}"
    echo
}

function query_has_bluetooth()
{
    choice "===> ${BOARD} has bluetooth? [Y/n] : "
    if [ ${CHOICE} == 'y' ]; then
        HAS_BLUETOOTH=true
    else
        HAS_BLUETOOTH=false
    fi
    vmsg "HAS_BLUETOOTH: ${HAS_BLUETOOTH}"
    echo
}

function query_has_sd_storage()
{
    choice "===> ${BOARD} has external sd card slot? [Y/n] : "
    if [ ${CHOICE} == 'y' ]; then
        HAS_SD_STORAGE=true
    else
        HAS_SD_STORAGE=false
    fi
    vmsg "HAS_SD_STORAGE: ${HAS_SD_STORAGE}"
    echo
}

function query_has_usb_storage()
{
    choice "===> ${BOARD} has usb host slot? [Y/n] : "
    if [ ${CHOICE} == 'y' ]; then
        HAS_USB_STORAGE=true
    else
        HAS_USB_STORAGE=false
    fi
    vmsg "HAS_USB_STORAGE: ${HAS_USB_STORAGE}"
    echo
}

function query_has_otg_storage()
{
    choice "===> ${BOARD} support usb memory through otg interface? [Y/n] : "
    if [ ${CHOICE} == 'y' ]; then
        HAS_OTG_STORAGE=true
    else
        HAS_OTG_STORAGE=false
    fi
    vmsg "HAS_OTG_STORAGE: ${HAS_OTG_STORAGE}"
    echo
}

function query_external_sd_device_number()
{
    local avail_numbers=
    if [ ${ROOT_DEVICE_TYPE} == "sd" ]; then
        if [ ${MAIN_SD_DEVICE_NUMBER} == "0" ]; then
            avail_numbers="1 2"
        else
            avail_numbers="0 2"
        fi
    else
        avail_numbers="0 1 2"
    fi
    printf "===> %-30.30s\n" "select external sd card port number"
    select number in ${avail_numbers}; do
        if [ -n ${number} ]; then
            EXTERNAL_SD_DEVICE_NUMBER=${number}
            break
        fi
    done
    vmsg "EXTERNAL_SD_DEVICE_NUMBER: ${EXTERNAL_SD_DEVICE_NUMBER}"
    echo
}

function base_porting()
{
    printf "%b\n"  "------------------------"
    printf "%b\n"  " Base Porting"
    printf "%b\n"  "------------------------"
    local b_option="-b ${BOARD}"
    local r_option="-r ${ROOT_DEVICE_TYPE}"
    local z_option="-z ${ROOT_DEVICE_SIZE_IN_GB}"
    local m_option=""
    if [ ${ROOT_DEVICE_TYPE} == "sd" ]; then
        m_option="-m ${MAIN_SD_DEVICE_NUMBER}"
    fi
    local n_camera=""
    if [ ${HAS_CAMERA} == "false" ]; then
        n_camera="-n camera"
    fi
    local n_sensor=""
    if [ ${HAS_SENSOR} == "false" ]; then
        n_sensor="-n sensor"
    fi
    local n_bluetooth=""
    if [ ${HAS_BLUETOOTH} == "false" ]; then
        n_bluetooth="-n bluetooth"
    fi
    local n_sd_storage=""
    local e_option=""
    if [ ${HAS_SD_STORAGE} == "false" ]; then
        n_sd_storage="-n sd-storage"
    else
        e_option="-e ${EXTERNAL_SD_DEVICE_NUMBER}"
    fi
    local n_usb_storage=""
    if [ ${HAS_USB_STORAGE} == "false" ]; then
        n_usb_storage="-n usb-storage"
    fi
    local n_otg_storage=""
    if [ ${HAS_OTG_STORAGE} == "false" ]; then
        n_otg_storage="-n otg-storage"
    fi
    ${TOP}/device/nexell/tools/base-porting.sh -v \
        ${b_option} \
        ${r_option} \
        ${z_option} \
        ${m_option} \
        ${e_option} \
        ${n_camera} \
        ${n_sensor} \
        ${n_bluetooth} \
        ${n_sd_storage} \
        ${n_usb_storage} \
        ${n_otg_storage}
    echo
}

function camera_porting()
{
    printf "%b\n"  "------------------------"
    printf "%b\n"  " Camera Porting"
    printf "%b\n"  "------------------------"
    ${TOP}/device/nexell/tools/camera-porting.sh -v -b ${BOARD}
    echo
}

function v4l2_porting()
{
    printf "%b\n"  "------------------------"
    printf "%b\n"  " V4L2 Porting"
    printf "%b\n"  "------------------------"
    ${TOP}/device/nexell/tools/v4l2-porting.sh -v -b ${BOARD}
    echo
}

function touch_porting()
{
    printf "%b\n"  "------------------------"
    printf "%b\n"  " Touch Porting"
    printf "%b\n"  "------------------------"
    ${TOP}/device/nexell/tools/touch-porting.sh -v -b ${BOARD}
    echo
}

function sensor_porting()
{
    printf "%b\n"  "------------------------"
    printf "%b\n"  " Sensor Porting"
    printf "%b\n"  "------------------------"
    ${TOP}/device/nexell/tools/sensor-porting.sh -v -b ${BOARD}
    echo
}
###########################################################################
check_top

source ${TOP}/device/nexell/tools/common.sh

print_startup
query_target_board
query_root_device_type
query_root_device_size
if [ ${ROOT_DEVICE_TYPE} == "sd" ]; then
    query_main_sd_device_number
fi
query_has_camera
query_has_sensor
query_has_bluetooth
query_has_sd_storage
query_has_usb_storage
query_has_otg_storage
if [ ${HAS_SD_STORAGE} == "true" ]; then
    query_external_sd_device_number
fi

base_porting

if [ ${HAS_CAMERA} == "true" ]; then
    camera_porting
fi

v4l2_porting
touch_porting
sensor_porting

printf "%b\n" "--------------------------------------------"
printf "%b\n" "Success Interactive Porting!!!"
printf "%b\n" "--------------------------------------------"
echo ""
