#!/bin/bash

set -e

TOP=`pwd`
export TOP 

VERBOSE=false
BOARD=
PLAT=
OS=
CAMERA_NUM=

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
    TEMP=`getopt -o "o:p:b:hv" -- "$@"`
    eval set -- "$TEMP"

    while true; do
        case "$1" in
            -b ) BOARD=$2; shift 2 ;;
            -p ) PLAT=$2; shift 2 ;;
            -o ) OS=$2; shift 2 ;;
            -h ) usage; exit 1 ;;
            -v ) VERBOSE=true; shift 1 ;;
            -- ) break ;;
            *  ) echo "invalid option $1"; usage; exit 1 ;;
        esac
    done
}

function check_kernel_porting()
{
		local str_os=""
		if [ -n ${OS} ]; then
   		str_os=${OS}_  
    fi

    local board=${BOARD}
    local src_file=${TOP}/kernel/arch/arm/configs/${PLAT}_${board}_android_${str_os}defconfig

    if [ ! -f ${src_file} ]; then
        echo "can't find kernel config for ${board}"
        echo "try after create ${src_file}!!!"
        exit 1
    fi
}

function get_use_decimator()
{
    check_kernel_porting

		local str_os=""
		if [ -n ${OS} ]; then
   		str_os=${OS}_  
    fi

    local board=${BOARD}
    local src_file=${TOP}/kernel/arch/arm/configs/${PLAT}_${board}_android_${str_os}defconfig
    grep -q CONFIG_NXP_CAPTURE_DECIMATOR=y ${src_file}
    if [ $? -eq 0 ]; then
        echo "true"
    else
        echo "false"
    fi
}

function get_use_hdmi()
{
    check_kernel_porting
		
		local str_os=""
		if [ -n ${OS} ]; then
   		str_os=${OS}_  
    fi

    local board=${BOARD}
    local src_file=${TOP}/kernel/arch/arm/configs/${PLAT}_${board}_android_${str_os}defconfig
    grep -q CONFIG_NXP_OUT_HDMI=y ${src_file}
    if [ $? -eq 0 ]; then
        echo "true"
    else
        echo "false"
    fi
}

function get_use_resol()
{
    check_kernel_porting

		local str_os=""
		if [ -n ${OS} ]; then
   		str_os=${OS}_  
    fi

    local board=${BOARD}
    local src_file=${TOP}/kernel/arch/arm/configs/${PLAT}_${board}_android_${str_os}defconfig
    grep -q CONFIG_NXP_OUT_RESOLUTION_CONVERTER=y ${src_file}
    if [ $? -eq 0 ]; then
        echo "true"
    else
        echo "false"
    fi
}

function make_android_nxp_v4l2_cpp()
{
    local board=${BOARD}
    local plat=${PLAT}

    if [ -z "${board}" ]; then
        echo "you must set board name"
        exit 1
    fi

    local use_clipper0=false
    local use_decimator0=false
    local use_clipper1=false
    local use_decimator1=false
    local use_mlc0_video=true
    local use_mlc1_video=false
    local use_mlc1_rgb=false
    local use_resol=false
    local use_hdmi=false

    local dst_file=${TOP}/device/nexell/${board}_${plat}/v4l2/android-nxp-v4l2.cpp
    rm -f ${dst_file}

    if (( ${CAMERA_NUM} > 0 )); then
        use_clipper0=true
        use_decimator0=$(get_use_decimator)
        if (( ${CAMERA_NUM} > 1 )); then
            use_clipper1=true
            use_decimator1=$use_decimator0;
        fi
    fi

    use_hdmi=$(get_use_hdmi)
    if [ ${use_hdmi} == true ]; then
        use_mlc1_video=true
        use_mlc1_rgb=true
    fi

    use_resol=$(get_use_resol)


    echo "#include <android-nxp-v4l2.h>
#include \"nxp-v4l2.h\"

#ifdef __cplusplus
extern \"C\" {
#endif

static bool inited = false;
bool android_nxp_v4l2_init()
{
    if (!inited) {
        struct V4l2UsageScheme s;
        memset(&s, 0, sizeof(s));

        s.useClipper0   = ${use_clipper0};
        s.useDecimator0 = ${use_decimator0};
        s.useClipper1   = ${use_clipper1};
        s.useDecimator1 = ${use_decimator1};
        s.useMlc0Video  = ${use_mlc0_video};
        s.useMlc1Video  = ${use_mlc1_video};
        s.useMlc1Rgb    = ${use_mlc1_rgb};
        s.useResol      = ${use_resol};
        s.useHdmi       = ${use_hdmi};

        int ret = v4l2_init(&s);
        if (ret != 0)
            return false;

        inited = true;
    }
    return true;
}

#ifdef __cplusplus
}
#endif" > ${dst_file}

    vmsg "create ${dst_file}"
}

#####################################################################################
check_top

source ${TOP}/device/nexell/tools/common.sh

parse_args "$@"
export VERBOSE

query_board
vmsg "BOARD: ${BOARD}_${PLAT}"

CAMERA_NUM=$(get_camera_number ${BOARD})
vmsg "CAMERA_NUM: ${CAMERA_NUM}"

make_android_nxp_v4l2_cpp
