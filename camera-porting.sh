#!/bin/bash

set -e

TOP=$(pwd)
export TOP

VERBOSE=false
BOARD=
PLAT=
CAMERA_NUMBER=
BACK_CAMERA_NAME=
FRONT_CAMERA_NAME=
BACK_CAMERA_V4L2_ID=
FRONT_CAMERA_V4L2_ID=
IS_BACK_CAMERA_MIPI=
IS_FRONT_CAMERA_MIPI=
BACK_CAMERA_SKIP_FRAME=
FRONT_CAMERA_SKIP_FRAME=
BACK_CAMERA_ORIENTATION=
FRONT_CAMERA_ORIENTATION=

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

function check_camera()
{
    local src_file=${TOP}/device/nexell/${BOARD}_${PLAT}/BoardConfig.mk
    local board_has_camera=$(grep 'BOARD_HAS_CAMERA' ${src_file} | cut -d' ' -f3)
    if [ ${board_has_camera} == "false" ]; then
        echo "You don't have to port camera, your board ${BOARD}_${PLAT} don't have camera!!!"
        exit 1
    fi
}

function query_camera_number()
{
    echo "===================================="
    until [ ${CAMERA_NUMBER} ]; do
        local input=$(get_userinput_number "Enter ${BOARD}_${PLAT}'s camera number(1 or 2): ")
        if [ ${input} == "invalid" ]; then
            echo "You must enter only Number!!!(1~2)"
        else
            if (( ${input} > 0 && ${input} < 3 )); then
                CAMERA_NUMBER=${input}
            else
                echo "Invalid Number: ${input}!!!"
                echo "Valid Num: 1 ~ 2"
                CAMERA_NUMBER=
            fi
        fi
    done
    echo "Number of camera is ${CAMERA_NUMBER}"
    echo ""
}

function check_camera_number()
{
    if [ ${CAMERA_NUMBER} -eq 0 ]; then
        echo "Your board doesn't have camera sensor!!!"
        exit 1
    fi
}

function query_camera_name()
{
    if [ ${1} != "back" ] && [ ${1} != "front" ]; then
        echo "invalid name: ${1}"
        exit 1
    fi

    local src_dir=${TOP}/hardware/samsung_slsi/slsiap/libcamerasensor
    cd ${src_dir}
    local sensors=$(ls *.cpp | cut -d'.' -f1)
    cd ${TOP}
    echo "===================================="
    echo "Select Your ${1} camera: "
    select sensor in ${sensors}; do
        if [ -n ${sensor} ]; then
            vmsg "you select ${sensor}"
            if [ ${1}  == "back" ]; then
                BACK_CAMERA_NAME=sensor
            else
                FRONT_CAMERA_NAME=sensor
            fi
            break
        else
            echo "You must select!!!"
        fi
    done
    echo ""
}

function check_camera_name()
{
    local src_dir=${TOP}/hardware/samsung_slsi/slsiap/libcamerasensor
    if [ ${1} == "back" ]; then
        if [ -z ${BACK_CAMERA_NAME} ]; then
            echo "Error: Back Camera Name is not set!!!"
            exit 1
        else
            if [ ! -f ${src_dir}/${BACK_CAMERA_NAME}.cpp ]; then
                echo "Error: your camera support HAL is not exist in ${src_dir}!!!"
                echo "You must create ${src_dir}/${BACK_CAMERA_NAME}.h ${src_dir}/${BACK_CAMERA_NAME}.cpp"
            fi
        fi
    elif [ ${1} == "front" ]; then
        if [ -z ${FRONT_CAMERA_NAME} ]; then
            echo "Error: Front Camera Name is not set!!!"
            exit 1
        else
            if [ ! -f ${src_dir}/${FRONT_CAMERA_NAME}.cpp ]; then
                echo "Error: your camera support HAL is not exist in ${src_dir}!!!"
                echo "You must create ${src_dir}/${FRONT_CAMERA_NAME}.h ${src_dir}/${FRONT_CAMERA_NAME}.cpp"
            fi
        fi
    fi
}

function check_camera_v4l2_id()
{
    if [ ${1} == "back" ]; then
        if [ -z "${BACK_CAMERA_V4L2_ID}" ]; then
            echo "Error: Back Camera V4L2 ID is not set!!!"
            exit 1
        fi
    elif [ ${1} == "front" ]; then
        if [ -z "${FRONT_CAMERA_V4L2_ID}" ]; then
            echo "Error: Front Camera V4L2 ID is not set!!!"
            exit 1
        fi
    fi
}

function base_kernel_check()
{
    local src_file=${TOP}/kernel/arch/arm/plat-${PLAT}/${BOARD}/device.c
    if [ ! -f ${src_file} ]; then
        echo "You must port ${BOARD} in kernel!!!"
        exit 1
    fi
}

function camera_name_arg_check()
{
    if [ ${1} != "back" ] && [ ${1} != "front" ]; then
        echo "invalid name: ${1}"
        exit 1
    fi
}

# arg1 : 'back' or 'front'
function get_camera_name()
{
    camera_name_arg_check ${1}

    local src_file=${TOP}/kernel/arch/arm/plat-${PLAT}/${BOARD}/device.c
    local search="${1}_camera_i2c_boardinfo"
    local name=$(awk '/'"${search}"'/{getline; getline; print $0}' ${src_file} | awk '/I2C_BOARD_INFO/{print $0}' |\
        cut -d'(' -f2 | cut -d',' -f1 | sed 's/[[:punct:]]//g')
    echo ${name}
}

function get_camera_v4l2_id()
{
    camera_name_arg_check ${1}

    local src_file=${TOP}/kernel/arch/arm/plat-${PLAT}/${BOARD}/device.c
    # first search
    local tmp=$(awk '/nxp_v4l2_i2c_board_info sensor/{getline; getline; print $3}' ${TOP}/kernel/arch/arm/plat-${PLAT}/${BOARD}/device.c |\
         grep ${1}_camera)
    if [ ${tmp} ]; then
        echo "nxp_v4l2_sensor0"
    else
        if (( ${CAMERA_NUMBER} == 1 )); then
            echo -n
        else
            # second search
            tmp=$(awk '/nxp_v4l2_i2c_board_info sensor/{getline; getline; getline; getline; getline; getline; print $3}'\
                 ${TOP}/kernel/arch/arm/plat-${PLAT}/${BOARD}/device.c | grep ${1}_camera)
            if [ ${tmp} ]; then
                echo "nxp_v4l2_sensor1"
            else
                echo -n
            fi
        fi
    fi
}

function is_camera_mipi()
{
    camera_name_arg_check ${1}
    local src_file=${TOP}/kernel/arch/arm/plat-${PLAT}/${BOARD}/device.c
    local search=
    if [ -${1} == "back" ];then
        search="sensor\[${BACK_CAMERA_V4L2_ID#nxp_v4l2_sensor}"
    else
        search="sensor\[${FRONT_CAMERA_V4L2_ID#nxp_v4l2_sensor}"
    fi

    local tmp=$(awk '/'"${search}"'/{getline; getline; getline; print $0}' ${TOP}/kernel/arch/arm/plat-${PLAT}/${BOARD}/device.c |\
         grep is_mipi | awk '{print $3}' | tr -d ',')
    if [ "${tmp}" ]; then
        echo "${tmp}"
    else
        echo -n
    fi
}

function check_is_camera_mipi()
{
    if [ ${1} == "back" ]; then
        if [ -z "${IS_BACK_CAMERA_MIPI}" ]; then
            echo "Error: Is Back Camera MIPI is not set!!!"
            exit 1
        fi
    elif [ ${1} == "front" ]; then
        if [ -z "${IS_FRONT_CAMERA_MIPI}" ]; then
            echo "Error: Is Front Camera MIPI is not set!!!"
            exit 1
        fi
    fi
}

function query_camera_skip_frame()
{
    camera_name_arg_check ${1}

    local skip_frame=
    until [ ${skip_frame} ]; do
        local input=$(get_userinput_number "===> Enter ${1} camera skip frame number(after initialization, we don't display skip frame): ")
        if [ ${input} != "invalid" ]; then
            skip_frame=${input}
        fi
    done

    if [ ${skip_frame} ]; then
        echo ${skip_frame}
    else
        echo -n
    fi
}

function check_camera_skip_frame()
{
    if [ ${1} == "back" ]; then
        if [ -z ${BACK_CAMERA_SKIP_FRAME} ]; then
            echo "Error: Back Camera SKIP Frame is not set!!!"
            exit 1
        fi
    else
        if [ -z ${FRONT_CAMERA_SKIP_FRAME} ]; then
            echo "Error: Front Camera SKIP Frame is not set!!!"
            exit 1
        fi
    fi
}

function query_camera_orientation()
{
    camera_name_arg_check ${1}

    local orientation=
    select orientation in 0 90 180 270; do
        if [ -n "${orientation}" ]; then
            break
        fi
    done
    echo ${orientation}
}

function check_camera_orientation()
{
    if [ ${1} == "back" ]; then
        if [ -z ${BACK_CAMERA_ORIENTATION} ]; then
            echo "Error: Back Camera Orientation is not set!!!"
            exit 1
        fi
    else
        if [ -z ${FRONT_CAMERA_ORIENTATION} ]; then
            echo "Error: Front Camera Orientation is not set!!!"
            exit 1
        fi
    fi
}

function make_board_camera_cpp()
{
    local src_file=${TOP}/device/nexell/${BOARD}_${PLAT}/camera/board-camera.cpp

    if [ -f ${src_file} ]; then
        rm -f ${src_file}
    fi

    local sensor0_var=
    local sensor1_var=
    if [ ${BACK_CAMERA_V4L2_ID} == "nxp_v4l2_sensor0" ]; then
        sensor0_var=backSensor
        sensor1_var=frontSensor
    else
        sensor0_var=frontSensor
        sensor1_var=backSensor
    fi

    local is_sensor0_mipi=
    local is_sensor1_mipi=
    if [ ${BACK_CAMERA_V4L2_ID} == "nxp_v4l2_sensor0" ]; then
        is_sensor0_mipi=${IS_BACK_CAMERA_MIPI}
        is_sensor1_mipi=${IS_FRONT_CAMERA_MIPI}
    else
        is_sensor0_mipi=${IS_FRONT_CAMERA_MIPI}
        is_sensor1_mipi=${IS_BACK_CAMERA_MIPI}
    fi

    local sensor0_skip_frame=
    local sensor1_skip_frame=
    if [ ${BACK_CAMERA_V4L2_ID} == "nxp_v4l2_sensor0" ]; then
        sensor0_skip_frame=${BACK_CAMERA_SKIP_FRAME}
        sensor1_skip_frame=${FRONT_CAMERA_SKIP_FRAME}
    else
        sensor0_skip_frame=${FRONT_CAMERA_SKIP_FRAME}
        sensor1_skip_frame=${BACK_CAMERA_SKIP_FRAME}
    fi

echo "
#define LOG_TAG \"NXCameraBoardSensor\"
#include <linux/videodev2.h>
#include <linux/v4l2-mediabus.h>

#include <utils/Log.h>
#include <nxp-v4l2.h>
#include <nx_camera_board.h>

#include <${BACK_CAMERA_NAME}.h>
" >> ${src_file}

if [ ${FRONT_CAMERA_NAME} ]; then
    echo "#include <${FRONT_CAMERA_NAME}.h>" >> ${src_file}
fi

echo "
namespace android {

extern \"C\" {
int get_board_number_of_cameras() {
    return ${CAMERA_NUMBER};
}
}

class NXCameraBoardSensor *frontSensor = NULL;
class NXCameraBoardSensor *backSensor = NULL;

NXCameraBoardSensor *get_board_camera_sensor(int id) {
    NXCameraBoardSensor *sensor = NULL;

    if (id == 0) {
        if (!backSensor) {
            backSensor = new ${BACK_CAMERA_NAME}(${BACK_CAMERA_V4L2_ID});
            if (!backSensor)
                ALOGE(\"%s: cannot create BACK Sensor\", __func__);
        }
        sensor = backSensor;
    }
" >> ${src_file}

if (( ${CAMERA_NUMBER} > 1 )); then
echo "    else if (id == 1) {
        if (!frontSensor) {
            frontSensor = new ${FRONT_CAMERA_NAME}(${FRONT_CAMERA_V4L2_ID});
            if (!frontSensor)
                ALOGE(\"%s: cannot create FRONT Sensor\", __func__);
        }
        sensor = frontSensor;
    }
" >> ${src_file}
fi

echo "    else {
        ALOGE(\"INVALID ID: %d\", id);
    };
    return sensor;
}
" >> ${src_file}

echo "
NXCameraBoardSensor *get_board_camera_sensor_by_v4l2_id(int v4l2_id) {
    switch (v4l2_id) {
    case nxp_v4l2_sensor0:
        return ${sensor0_var};
    case nxp_v4l2_sensor1:
        return ${sensor1_var};
    default: 
        ALOGE(\"%s: invalid v4l2 id(%d)\", __func__, v4l2_id);
        return NULL;
    }
}

uint32_t get_board_preview_v4l2_id(int cameraId)
{
    switch (cameraId) {
    case 0:
        return nxp_v4l2_decimator0;
    case 1:
        return nxp_v4l2_decimator1;
    default:
        ALOGE(\"%s: invalid cameraId %d\", __func__, cameraId);
        return 0;
    }
}

uint32_t get_board_capture_v4l2_id(int cameraId)
{
    switch (cameraId) {
    case 0:
        return nxp_v4l2_clipper0;
    case 1:
        return nxp_v4l2_clipper1;
    default:
        ALOGE(\"%s: invalid cameraId %d\", __func__, cameraId);
        return 0;
    }
}

uint32_t get_board_record_v4l2_id(int cameraId)
{
    switch (cameraId) {
    case 0:
        return nxp_v4l2_clipper0;
    case 1:
        return nxp_v4l2_clipper1;
    default:
        ALOGE(\"%s: invalid cameraId %d\", __func__, cameraId);
        return 0;
    }
}

bool get_board_camera_is_mipi(uint32_t v4l2_sensorId)
{
    switch (v4l2_sensorId) {
    case nxp_v4l2_sensor0:
        return ${is_sensor0_mipi};
    case nxp_v4l2_sensor1:
        return ${is_sensor1_mipi};
    default:
        return false;
    }
}

uint32_t get_board_preview_skip_frame(int v4l2_sensorId, int width, int height)
{
    switch (v4l2_sensorId) {
    case nxp_v4l2_sensor0:
        return ${sensor0_skip_frame};
    case nxp_v4l2_sensor1:
        return ${sensor1_skip_frame};
    default:
        return 0;
    }
}

uint32_t get_board_capture_skip_frame(int v4l2_sensorId, int width, int height)
{
    switch (v4l2_sensorId) {
    case nxp_v4l2_sensor0:
        return ${sensor0_skip_frame};
    case nxp_v4l2_sensor1:
        return ${sensor1_skip_frame};
    default:
        return 0;
    }
}

void set_board_preview_mode(int v4l2_sensorId, int width, int height)
{
    switch (v4l2_sensorId) {
    case nxp_v4l2_sensor0:
        return;
    case nxp_v4l2_sensor1:
        return;
    }
}

void set_board_capture_mode(int v4l2_sensorId, int width, int height)
{
    switch (v4l2_sensorId) {
    case nxp_v4l2_sensor0:
        return;
    case nxp_v4l2_sensor1:
        return;
    }
}

uint32_t get_board_camera_orientation(int cameraId)
{
    switch (cameraId) {
    case 0:
        return ${BACK_CAMERA_ORIENTATION};
    case 1:
        return ${FRONT_CAMERA_ORIENTATION};
    default:
        return 0;
    }
}

}" >> ${src_file}

    vmsg "create ${src_file}"
}

#####################################################################################
check_top

source ${TOP}/device/nexell/tools/common.sh

parse_args "$@"
export VERBOSE

query_board
echo "BOARD: ${BOARD}"

base_kernel_check
check_camera

CAMERA_NUMBER=$(get_camera_number ${BOARD})
vmsg "CAMERA_NUMBER: ${CAMERA_NUMBER}"
check_camera_number

BACK_CAMERA_NAME=$(get_camera_name back)
vmsg "BACK_CAMERA_NAME: ${BACK_CAMERA_NAME}"
check_camera_name back
if (( ${CAMERA_NUMBER} > 1 )); then
    FRONT_CAMERA_NAME=$(get_camera_name front)
    vmsg "FRONT_CAMERA_NAME: ${FRONT_CAMERA_NAME}"
fi

BACK_CAMERA_V4L2_ID=$(get_camera_v4l2_id back)
vmsg "BACK_CAMERA_V4L2_ID: ${BACK_CAMERA_V4L2_ID}"
check_camera_v4l2_id back
if (( ${CAMERA_NUMBER} > 1 )); then
    FRONT_CAMERA_V4L2_ID=$(get_camera_v4l2_id front)
    vmsg "FRONT_CAMERA_V4L2_ID: ${FRONT_CAMERA_V4L2_ID}"
    check_camera_v4l2_id front
fi

IS_BACK_CAMERA_MIPI=$(is_camera_mipi back)
vmsg "IS_BACK_CAMERA_MIPI: ${IS_BACK_CAMERA_MIPI}"
check_is_camera_mipi back
if (( ${CAMERA_NUMBER} > 1 )); then
    IS_FRONT_CAMERA_MIPI=$(is_camera_mipi front)
    vmsg "IS_FRONT_CAMERA_MIPI: ${IS_FRONT_CAMERA_MIPI}"
    check_is_camera_mipi front
fi

BACK_CAMERA_SKIP_FRAME=$(query_camera_skip_frame back)
vmsg "BACK_CAMERA_SKIP_FRAME: ${BACK_CAMERA_SKIP_FRAME}"
check_camera_skip_frame back
if (( ${CAMERA_NUMBER} > 1 )); then
    FRONT_CAMERA_SKIP_FRAME=$(query_camera_skip_frame front)
    vmsg "FRONT_CAMERA_SKIP_FRAME: ${FRONT_CAMERA_SKIP_FRAME}"
    check_camera_skip_frame front
fi

echo "===> select back camera orientation: "
BACK_CAMERA_ORIENTATION=$(query_camera_orientation back)
vmsg "BACK_CAMERA_ORIENTATION: ${BACK_CAMERA_ORIENTATION}"
check_camera_orientation back
if (( ${CAMERA_NUMBER} > 1 )); then
    echo "===> select front camera orientation: "
    FRONT_CAMERA_ORIENTATION=$(query_camera_orientation front)
    vmsg "FRONT_CAMERA_ORIENTATION: ${FRONT_CAMERA_ORIENTATION}"
    check_camera_orientation front
fi

make_board_camera_cpp
