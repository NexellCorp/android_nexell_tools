#!/usr/bin/env bash

set -e

TOP=$(pwd)
export TOP

VERBOSE=false
BOARD=
SENSOR_TYPE=

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
    TEMP=`getopt -o "b:hv" -- "$@"`
    eval set -- "$TEMP"

    while true; do
        case "$1" in
            -b ) BOARD=$2; shift 2 ;;
            -h ) usage; exit 1 ;;
            -v ) VERBOSE=true; shift 1 ;;
            -- ) break ;;
            *  ) echo "invalid option $1"; usage; exit 1 ;;
        esac
    done
}

function is_sensor_exist()
{
    local src_file=${TOP}/device/nexell/${BOARD}/BoardConfig.mk
    local board_has_sensor=$(awk '/BOARD_HAS_SENSOR/ {print $3}' ${src_file})
    if [ ${board_has_sensor} == "false" ]; then
        #echo "${BOARD} don't have sensor!!!"
        echo "no"
    else
        echo "yes"
    fi
}

function query_sensor_type()
{
    local src_dir=${TOP}/hardware/nexell/pyrope/libsensors
    cd ${src_dir}
    local sensors=$(find . -maxdepth 1 -type d | tr -d './' | awk 'NF > 0 {print $1}')
    echo "========================================================================"
    echo "Select Your sensor type(If you want to port manually, select ANOTHER): "
    select sensor in ${sensors} ANOTHER ; do
        if [ -n ${sensor} ]; then
            SENSOR_TYPE=${sensor}
            break
        fi
    done
}

function check_sensor_type()
{
    if [ -z ${SENSOR_TYPE} ]; then
        echo "Error: you must select sensor type"
        exit 1
    fi
}

function apply_sensor_type()
{
    local src_file=${TOP}/device/nexell/${BOARD}/BoardConfig.mk

    if [ ${SENSOR_TYPE} == "ANOTHER" ]; then
        echo "======================================================="
        echo "You must apply your sensor library name to ${src_file}"
        echo "======================================================="
    else
        echo "apply sensor: ${SENSOR_TYPE}"
        grep BOARD_SENSOR_TYPE ${src_file} > /dev/null
        if [ $? -ne 0 ]; then
            vmsg "insert BOARD_SENSOR_TYPE"
            sed -i -e 's/BOARD_HAS_SENSOR.*/&\nBOARD_SENSOR_TYPE := '"${SENSOR_TYPE}"'/' ${src_file}
        else
            vmsg "change BOARD_SENSOR_TYPE"
            sed -i -e 's/\(BOARD_SENSOR_TYPE :=\)\(.*\)/\1 '"${SENSOR_TYPE}"'/' ${src_file}
        fi
        vmsg "apply sensor ${SENSOR_TYPE} to ${src_file}"
    fi
}

#####################################################################################
check_top

source ${TOP}/device/nexell/tools/common.sh

parse_args "$@"
export VERBOSE

query_board
vmsg "BOARD: ${BOARD}"

sensor_exist=is_sensor_exist
if [[ ${sensor_exist} == "yes" ]]; then
    query_sensor_type
    vmsg "SENSOR_TYPE: ${SENSOR_TYPE}"
    check_sensor_type
    apply_sensor_type
else
    echo "Board doesn't have sensor!!!"
fi
