#!/bin/bash

#
# Copyright (C) 2015 The Android Open-Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# This file implements general functions to build component

set -e

TARGET_SOC=
BOARD_NAME=
RESULT_DIR=
BUILD_ALL=true
BUILD_BL1=false
BUILD_UBOOT=false
BUILD_SECURE=false
BUILD_KERNEL=false
BUILD_MODULE=false
BUILD_ANDROID=false
BUILD_DIST=false
VERBOSE=false
OTA_INCREMENTAL=false
OTA_PREVIOUS_FILE=
BUILD_TAG=userdebug
QUICKBOOT=false
AES_KEY=none
RSA_KEY=none
MODULE=none

function usage()
{
    echo "Usage: $0 -s <chip-name> [-k <aes-key-file>] [-p <rsa-key-file>] [-m <cpu-module>] [-t <build-target>] [-d <result-dir>] [-T <android-build-tag>] [-V <build-version>] [-i <previous-target.zip>] [-q]"
    echo "Available build-target: bl1, u-boot, secure, kernel, module, android, dist"
    echo "Available android-build-tag: user userdebug eng"
    echo "If given -d <result-dir> -V <build-version>, result-dir-build-version is created in ANDROID_TOP dir"
    echo "-i option is for generation of incremental ota image, -t dist option is needed and previous built target_files.zip file path must follow"
    echo "-q option is given, quickboot patch is applied"
}

function parse_args()
{
    TEMP=`getopt -o "s:t:hvV:d:T:i:k:p:m:q" -- "$@"`
    eval set -- "$TEMP"

    while true; do
        case "$1" in
            -s ) TARGET_SOC=$2; shift 2 ;;
            -d ) RESULT_DIR=$2; shift 2 ;;
            -t ) case "$2" in
                bl1    ) BUILD_ALL=false; BUILD_BL1=true ;;
                u-boot ) BUILD_ALL=false; BUILD_UBOOT=true ;;
                secure ) BUILD_ALL=false; BUILD_SECURE=true ;;
                kernel ) BUILD_ALL=false; BUILD_KERNEL=true ;;
                module ) BUILD_ALL=false; BUILD_MODULE=true ;;
                android ) BUILD_ALL=false; BUILD_ANDROID=true ;;
                dist   ) BUILD_ALL=true; BUILD_ANDROID=false; BUILD_DIST=true ;;
                none   ) BUILD_ALL=false ;;
                 esac
                 shift 2 ;;
            -h ) usage; exit 1 ;;
            -v ) VERBOSE=true; shift 1 ;;
            -V ) BUILD_VERSION=$2; shift 2;;
            -T ) BUILD_TAG=$2; shift 2;;
            -i ) OTA_INCREMENTAL=true; OTA_PREVIOUS_FILE=$2; shift 2;;
            -q ) QUICKBOOT=true; shift 1 ;;
            -k ) AES_KEY=$2; shift 2;;
            -p ) RSA_KEY=$2; shift 2;;
            -m ) MODULE=$2; shift 2;;
            -- ) break ;;
        esac
    done

    BOARD_NAME=$(get_board_name $0)
    test -z ${BUILD_DATE} && BUILD_DATE=$(date "+%Y%m%d-%H%M%S")
    test -z ${RESULT_DIR} && RESULT_DIR=result-${TARGET_SOC}-${BOARD_NAME}-${BUILD_DATE}
    ! test -z ${BUILD_VERSION} && RESULT_DIR=${RESULT_DIR}-${BUILD_VERSION}
    export TARGET_SOC BOARD_NAME RESULT_DIR BUILD_BL1 BUILD_UBOOT BUILD_SECURE BUILD_KERNEL \
        BUILD_MODULE BUILD_ANDROID BUILD_ALL VERBOSE BUILD_VERSION BUILD_DATE BUILD_TAG QUICKBOOT \
        AES_KEY RSA_KEY MODULE
}

function print_args()
{
    echo "===================================================="
    echo "BUILD ARGS"
    echo "===================================================="
    echo "TARGET_SOC ==> ${TARGET_SOC}"
    echo "BOARD_NAME ==> ${BOARD_NAME}"
    echo "BUILD_ALL ==> ${BUILD_ALL}"
    echo "BUILD_BL1 ==> ${BUILD_BL1}"
    echo "BUILD_UBOOT ==> ${BUILD_UBOOT}"
    echo "BUILD_SECURE ==> ${BUILD_SECURE}"
    echo "BUILD_KERNEL ==> ${BUILD_KERNEL}"
    echo "BUILD_MODULE ==> ${BUILD_MODULE}"
    echo "BUILD_ANDROID ==> ${BUILD_ANDROID}"
    echo "BUILD_DATE ==> ${BUILD_DATE}"
    echo "BUILD_VERSION ==> ${BUILD_VERSION}"
    echo "BUILD_TAG ==> ${BUILD_TAG}"
    echo "RESULT_DIR ==> ${RESULT_DIR}"
    echo "AES_KEY ==> ${AES_KEY}"
    echo "RSA_KEY ==> ${RSA_KEY}"
    echo "CPU_MODULE ==> ${MODULE}"
    echo "QUICKBOOT ==> ${QUICKBOOT}"
}

function get_board_name()
{
    local board=$(echo -n $1 | tr -d . | tr '/' ' ' | awk '{print $3}')
    echo -n ${board}
}

function setup_toolchain()
{
    # android nougat internal
    export PATH=${TOP}/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9/bin:$PATH
    export PATH=${TOP}/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9/bin:$PATH

    # arm-eabi-4.8 that is not included in android pie
    test -d ${TOP}/device/nexell/tools/toolchain/arm-eabi-4.8 ||\
        tar xvjf ${TOP}/device/nexell/tools/toolchain/arm-eabi-4.8.tar.bz2 -C \
        ${TOP}/device/nexell/tools/toolchain/
    export PATH=${TOP}/device/nexell/tools/toolchain/arm-eabi-4.8/bin:$PATH

    # external
    # arm-linux-gnueabihf for optee 32bit build
    test -d ${TOP}/device/nexell/tools/toolchain/gcc-linaro-4.9-2014.11-x86_64_arm-linux-gnueabihf ||\
        cat ${TOP}/device/nexell/tools/toolchain/gcc-linaro-4.9-2014.11-x86_64_arm-linux-gnueabihf-splita* | \
        tar -zxvpf - -C ${TOP}/device/nexell/tools/toolchain
    export PATH=${TOP}/device/nexell/tools/toolchain/gcc-linaro-4.9-2014.11-x86_64_arm-linux-gnueabihf/bin:$PATH

    # aarch64-linux-gnu for optee 64bit build
    test -d ${TOP}/device/nexell/tools/toolchain/gcc-linaro-4.9-2015.05-x86_64_aarch64-linux-gnu ||\
        cat ${TOP}/device/nexell/tools/toolchain/gcc-linaro-4.9-2015.05-x86_64_aarch64-linux-gnu-split* | \
        tar -zxvpf - -C ${TOP}/device/nexell/tools/toolchain
    export PATH=${TOP}/device/nexell/tools/toolchain/gcc-linaro-4.9-2015.05-x86_64_aarch64-linux-gnu/bin:$PATH
}

function print_build_info()
{
    echo ""
    echo "===================================================="
    echo "build $1"
    echo "===================================================="
}

function print_build_done()
{
    echo "done"
    echo ""
}

##
# must be in u-boot top directory
# args
# $1: compiler_prefix
# $2: bootcmd
# $3: bootargs
# $4: (optional) splashsource
# $5: (optional) splashoffset
# $6: (optional) recoveryboot
# $7: (optional) autorecovery_cmd
# $8: (optional) env file name
function build_uboot_env_param_legacy()
{
	local compiler_prefix=${1}
	local bootcmd=${2}
	local bootargs=${3}
	local splashsource=${4:-"nosplash"}
	local splashoffset=${5:-"nosplash"}
	local recoveryboot=${6:-"norecovery"}
	local autorecovery_cmd=${7:-"none"}
	local filename=${8:-"params.bin"}

	cp `find . -name "env_common.o"` copy_env_common.o
	${compiler_prefix}objcopy -O binary --only-section=.rodata.default_environment `find . -name "copy_env_common.o"`
	tr '\0' '\n' < copy_env_common.o > default_envs.txt
	sed -i -e 's/bootcmd=.*/bootcmd='"${bootcmd}"'/g' default_envs.txt
	sed -i -e 's/bootargs=.*/bootargs='"${bootargs}"'/g' default_envs.txt
	if [ "${splashsource}" != "nosplash" ]; then
		sed -i -e 's/splashsource=.*/splashsource='"${splashsource}"'/g' default_envs.txt
	fi
	if [ "${splashoffset}" != "nosplash" ]; then
		sed -i -e 's/splashoffset=.*/splashoffset='"${splashoffset}"'/g' default_envs.txt
	fi
	if [ "${recoveryboot}" != "norecovery" ]; then
		sed -i -e 's/recoveryboot=.*/recoveryboot='"${recoveryboot}"'/g' default_envs.txt
	fi
	if [ "${autorecovery_cmd}" != "none" ]; then
		sed -i -e 's/autorecovery_cmd=.*/autorecovery_cmd='"${autorecovery_cmd}"'/g' default_envs.txt
	fi
	tools/mkenvimage -s 16384 -o ${filename} default_envs.txt
	rm copy_env_common.o default_envs*.txt
}

##
# must be in u-boot top directory
# args
# $1: compiler_prefix
# $2: bootcmd array
# $3: bootargs
# $4: (optional) splashsource
# $5: (optional) splashoffset
# $6: (optional) recoveryboot
function build_uboot_env_param()
{
    local compiler_prefix=${1}
    local bootcmd=("${!2}")
    local bootargs=${3}
    local splashsource=${4:-"nosplash"}
    local splashoffset=${5:-"nosplash"}
    local recoveryboot=${6:-"norecovery"}
    local vendor_blk_select=("${!7}")

    cp `find . -name "env_common.o"` copy_env_common.o
    ${compiler_prefix}objcopy -O binary --only-section=.rodata.default_environment `find . -name "copy_env_common.o"`
    tr '\0' '\n' < copy_env_common.o > default_envs.txt

    # for OTA A/B update
    # sed -i -e 's/bootcmd=.*/bootcmd='"${bootcmd}"'/g' default_envs.txt
    # sed -i -e 's/bootcmd=.*/bootcmd_a='"${bootcmd[0]}"'/g' default_envs.txt
    echo "bootcmd_a=${bootcmd[0]}" >> default_envs.txt
    echo "bootcmd_b=${bootcmd[1]}" >> default_envs.txt
    echo "vendor_blk_select_a=${vendor_blk_select[0]}" >> default_envs.txt
    echo "vendor_blk_select_b=${vendor_blk_select[1]}" >> default_envs.txt

    # bootargs replace
    sed -i -e 's/bootargs=.*/bootargs='"${bootargs}"'/g' default_envs.txt

    if [ "${splashsource}" != "nosplash" ]; then
        sed -i -e 's/splashsource=.*/splashsource='"${splashsource}"'/g' default_envs.txt
    fi
    if [ "${splashoffset}" != "nosplash" ]; then
        sed -i -e 's/splashoffset=.*/splashoffset='"${splashoffset}"'/g' default_envs.txt
    fi
    if [ "${recoveryboot}" != "norecovery" ]; then
        sed -i -e 's/recoveryboot=.*/recoveryboot='"${recoveryboot}"'/g' default_envs.txt
    fi
    tools/mkenvimage -s 16384 -o params.bin default_envs.txt
    rm copy_env_common.o default_envs*.txt
}

##
# args
# $1: source location of bl1
# $2: board name
# $3: debug port number
function build_bl1()
{
    [ $# -lt 3 ] && echo "" &&\
        echo "ERROR in build_bl1: invalid args num($#/3)" &&\
        echo "usage: build_bl1 source_of_bl1 board_name boot_device_port" &&\
        exit 0

    print_build_info bl1

    local src=${1}
    local board=${2}
    local boot_device_port=${3}

    pushd `pwd`
    cd ${src}
    make clean
    if [ "${QUICKBOOT}" == "true" ]; then
        make BOARD="${board}" KERNEL_VER="4" SYSLOG="n" DEVICE_PORT="${boot_device_port}" SECURE_ON=1 QUICKBOOT=1 SUPPORT_OTA_AB_UPDATE=y
    else
        make BOARD="${board}" KERNEL_VER="4" SYSLOG="n" DEVICE_PORT="${boot_device_port}" SECURE_ON=1 SUPPORT_OTA_AB_UPDATE=y
    fi
    popd

    print_build_done
}

##
# args
# $1: source location of bl1
# $2: chipname(nxp4330, s5p4418)
# $3: board name
# $4: debug port number
function build_bl1_s5p4418()
{
    [ $# -lt 4 ] && echo "" &&\
        echo "ERROR in build_bl1_s5p4418: invalid args num($#/4)" &&\
        echo "usage: build_bl1_s5p4418 source_of_bl1 chip_name board_name boot_device_port" &&\
        exit 0

    print_build_info bl1

    local src=${1}
    local chip=${2}
    local board=${3}
    local boot_device_port=${4}

    pushd `pwd`
    cd ${src}
    make clean
    make CHIPNAME="${chip}" BOARD="${board}" KERNEL_VER="4" SYSLOG="n" DEVICE_PORT="${boot_device_port}" SUPPORT_USB_BOOT="y" SUPPORT_SDMMC_BOOT="n"
    cp ./out/bl1-${board}.bin ./bl1-${board}-usb.bin
    make clean
    if [ "${QUICKBOOT}" == "true" ]; then
        make CHIPNAME="${chip}" BOARD="${board}" KERNEL_VER="4" SYSLOG="n" DEVICE_PORT="${boot_device_port}" SUPPORT_USB_BOOT="n" SUPPORT_SDMMC_BOOT="y" QUICKBOOT=1 OTA_AB_UPDATE=y
    else
        make CHIPNAME="${chip}" BOARD="${board}" KERNEL_VER="4" SYSLOG="n" DEVICE_PORT="${boot_device_port}" SUPPORT_USB_BOOT="n" SUPPORT_SDMMC_BOOT="y" OTA_AB_UPDATE=y
    fi

    popd

    print_build_done
}

##
# args
# $1: source location of bl2
function build_bl2_s5p4418()
{
    [ $# -lt 1 ] && echo "" &&\
        echo "ERROR in build_bl2_s5p4418: invalid args num($#/1)" &&\
        echo "usage: build_bl2_s5p4418 source_of_bl2" &&\
        exit 0

    print_build_info bl2

    local src=${1}
    pushd `pwd`
    cd ${src}
    make clean
    if [ "${QUICKBOOT}" == "true" ]; then
        make QUICKBOOT=1 SUPPORT_OTA_AB_UPDATE=y
    else
        make SUPPORT_OTA_AB_UPDATE=y
    fi
    popd

    print_build_done
}

##
# args
# $1: source location of armv7-dispatcher
function build_armv7_dispatcher()
{
    [ $# -lt 1 ] && echo "" &&\
        echo "ERROR in build_armv7_dispatcher: invalid args num($#/1)" &&\
        echo "usage: build_armv7_dispatcher source_of_dispatcher" &&\
        exit 0

    print_build_info armv7_dispatcher

    local src=${1}
    pushd `pwd`
    cd ${src}
    make clean
    make
    popd

    print_build_done
}

##
# args
# $1: source location of u-boot
# $2: soc name(s5p6818, s5p4418, nxp4330)
# $3: board name
# $4: cross_compile_prefix(arm-eabi-, aarch64-linux-android- etc)
# $5: [optional] config name
function build_uboot()
{
    [ $# -lt 4 ] && echo "" &&\
        echo "ERROR in build_uboot: invalid args num($#/4)" &&\
        echo "usage: build_uboot source_of_uboot soc_name board_name cross_compile_prefix" &&\
        exit 0

    print_build_info u-boot

    local src=${1}
    local config=${5:-${2}_${3}}
    local cross_compile=${4}

    pushd `pwd`
    cd ${src}
    make clean
    make ${config}_config
    if [ "${QUICKBOOT}" == "true" ]; then
        make CROSS_COMPILE=${cross_compile} QUICKBOOT=1 -j8
    else
        make CROSS_COMPILE=${cross_compile} -j8
    fi
    popd

    print_build_done
}

##
# args
# $1: source location of optee
# $2: build option
# #3: target
function build_optee()
{
    [ $# -lt 3 ] && echo "" &&\
        echo "ERROR in build_optee: invalid args num($#/3)" &&\
        echo "usage: build_optee source_of_secure build_option target" &&\
        exit 0

    print_build_info optee

    local src=${1}
    local build_option=${2}
    local target=${3}

    pushd `pwd`
    cd ${src}
    if [ "${target}" == "all" ]; then
        make -f optee_build/Makefile ${build_option} clean
        make -f optee_build/Makefile ${build_option} build-bl1 -j8
        make -f optee_build/Makefile ${build_option} build-lloader -j8
        make -f optee_build/Makefile ${build_option} build-bl32 -j8
        make -f optee_build/Makefile ${build_option} build-fip -j8
        make -f optee_build/Makefile ${build_option} build-fip-loader -j8
        make -f optee_build/Makefile ${build_option} build-fip-secure -j8
        make -f optee_build/Makefile ${build_option} build-fip-nonsecure -j8
        # TODO: compile error in build-optee-client
        # make -f optee_build/Makefile ${build_option} build-optee-client -j8
        # make -f optee_build/Makefile ${build_option} OPTEE_CLIENT_EXPORT="optee_client/out/export" build-optee-test -j8
        # for fip-loader usb boot image
        make -f optee_build/Makefile ${build_option} build-singleimage -j8
    else
        make -f optee_build/Makefile ${build_option} ${target} -j8
    fi
    popd

    print_build_done
}

##
# args
# $1: src location of kernel
# $2: target soc(s5p6818, s5p4418, nxp4330)
# $3: target board
# $4: config
# $5: cross_compile prefix
function build_kernel()
{
    [ $# -lt 5 ] && echo "" &&\
        echo "ERROR in build_kernel: invalid args num($#/5)" &&\
        echo "usage: build_kernel source_of_kernel target_soc target_board config_file cross_compile_prefix" &&\
        exit 0

    print_build_info kernel

    local src=${1}
    local soc=${2}
    local board=${3}
    local config=${4}
    local cross_compile=${5}
    local arch=
    local image_type=
    if [ "${soc}" == "s5p6818" ]; then
        arch=arm64
        image_type=Image
    else
        arch=arm
        image_type=zImage
    fi

    if [ "${QUICKBOOT}" == "true" ]; then
        config="${soc}_${board}_pie_quickboot_defconfig"
    fi

    pushd `pwd`
    cd ${src}
    make ARCH=${arch} distclean
    make ARCH=${arch} ${config}
    make ARCH=${arch} CROSS_COMPILE=${cross_compile} ${image_type} -j8
    make ARCH=${arch} CROSS_COMPILE=${cross_compile} dtbs
    make ARCH=${arch} CROSS_COMPILE=${cross_compile} modules -j8
    popd

    print_build_done
}

##
# args
# $1: src location of kernel
# $2: target soc(s5p6818, s5p4418, nxp4330)
# $3: cross_compile prefix
function build_module()
{
    [ $# -lt 3 ] && echo "" &&\
        echo "ERROR in build_module: invalid args num($#/3)" &&\
        echo "usage: build_module source_of_kernel target_soc cross_compile_prefix" &&\
        exit 0

    print_build_info module

    local src=${1}
    local soc=${2}
    local cross_compile=${3}
    local arch=
    if [ "${soc}" == "s5p6818" ]; then
        arch=arm64
    else
        arch=arm
    fi

    pushd `pwd`

    make -C ${src} ARCH=${arch} CROSS_COMPILE=${cross_compile} LOCALVESRION= M=${TOP}/device/nexell/secure/optee_linuxdriver clean
    make -C ${src} ARCH=${arch} CROSS_COMPILE=${cross_compile} LOCALVESRION= M=${TOP}/device/nexell/secure/optee_linuxdriver modules -j8

    cd ${TOP}/hardware/realtek/wlan/driver/rtl8188eus/
    ./build.sh ${arch}

    cd ${TOP}/hardware/realtek/wlan/driver/rtl8189fs/
    ./build.sh ${arch}

    popd

    print_build_done
}

##
# args
# $1: target soc
# $2: board
# $3: build_tag(user, userdebug)
# $4: <optional> module
function build_android()
{
    [ $# -lt 3 ] && echo "" &&\
        echo "ERROR in build_android: invalid args num($#/3)" &&\
        echo "usage: build_android target_soc target_board build_tag" &&\
        exit 0

    print_build_info android

    local product=PRODUCT-${2}-${3}
    if [ "${QUICKBOOT}" == "true" ]; then
        make ${product} TARGET_SOC=${1} MODULE=${4} QUICKBOOT=1 -j8
    else
        make ${product} TARGET_SOC=${1} MODULE=${4} -j8
    fi

    print_build_done
}

##
# args
# $1: target soc
# $2: board
# $3: build_tag(user, userdebug)
function build_dist()
{
    [ $# -lt 3 ] && echo "" &&\
        echo "ERROR in build_android: invalid args num($#/3)" &&\
        echo "usage: build_android target_soc target_board build_tag" &&\
        exit 0

    echo " build dist"
    print_build_info dist

    local product=PRODUCT-${2}-${3}

    rm -rf ${TOP}/out/dist

    if [ "${QUICKBOOT}" == "true" ]; then
        make ${product} TARGET_SOC=${1} QUICKBOOT=1 dist -j8
    else
        make ${product} TARGET_SOC=${1} dist -j8
    fi

    print_build_done
}

##
# args
# $1: target soc(s5p4418, nxp4330, s5p6818)
# $2: input bl1 binary
# $3: nsih
# $4: output binary name
function gen_bl1()
{
    [ $# -lt 4 ] && echo "" &&\
        echo "ERROR in gen_bl1: invalid args num($#/4)" &&\
        echo "usage: gen_bl1 target_soc input_bl1 nsih output" &&\
        exit 0

    print_build_info "$(basename ${4})"

    local soc=${1}
    local in=${2}
    local nsih=${3}
    local out=${4}

    ${TOP}/device/nexell/tools/BOOT_BINGEN -c ${soc} -t 2ndboot -n ${nsih} \
        -i ${in} -o ${out} -l 0xffff0000 -e 0xffff0000

    print_build_done
}

##
# args
# $1: target soc(s5p4418, nxp4330, s5p6818)
# $2: input
# $3: load address
# $4: jump address
# $5: output
# $6: optional needed to fip-loader.bin
function gen_third()
{
    # TODO: handle secure(aes encrypt, rsa encrypt)
    [ $# -lt 5 ] && echo "" &&\
        echo "ERROR in gen_third: invalid args num($#/5)" &&\
        echo "usage: gen_third target_soc input load_addr jump_addr output [extra-option]" &&\
        exit 0

    print_build_info "$(basename ${5})"

    local soc=${1}
    local in=${2}
    local load_addr=${3}
    local jump_addr=${4}
    local out=${5}
    local extra_opts="${6}"

    ${TOP}/device/nexell/tools/SECURE_BINGEN -c ${soc} -t 3rdboot \
        -i ${in} -o ${out} -l ${load_addr} -e ${jump_addr} \
        ${extra_opts}

    print_build_done
}

##
# args
# $1: result_dir
function generate_update_script()
{
    local result_dir=${1}

    cp ${TOP}/device/nexell/tools/update_template.sh ${result_dir}/update.sh
}

##
# args
# $1: result_dir
function generate_usb_boot()
{
    local result_dir=${1}

    cp ${TOP}/device/nexell/tools/boot_by_usb.sh ${result_dir}
    cp ${TOP}/device/nexell/tools/usb-downloader ${result_dir}
}

##
# args
# $1: kernel image
# $2: dtb image
# $3: ramdisk image
# $4: partition size
# $5: result dir
function make_ext4_recovery_image()
{
    local kernel_img=${1}
    local dtb_img=${2}
    local ramdisk_img=${3}
    local partition_size=${4}
    local result_dir=${5}

    mkdir -p ${result_dir}/recovery
    cp ${kernel_img} ${result_dir}/recovery/recovery.kernel
    cp ${dtb_img} ${result_dir}/recovery/recovery.dtb
    cp ${ramdisk_img} ${result_dir}/recovery/ramdisk-recovery.img

    ${TOP}/device/nexell/tools/make_ext4fs -s -T -1 -l ${partition_size} \
        -a recovery ${result_dir}/recovery.img ${result_dir}/recovery
}

##
# args
# $1: target soc
# $2: partmap
# $3: result_dir
# $4: bl1 binary out path
# $5: third boot binary out path
# $6: u-boot params out path
# $7: kernel binary out path
# $8: dtb binary out path
# $9: boot partition size
# $10: android out path
# $11: bl1 target name(ex> avn)
# $12: logo path
function post_process()
{
    [ $# -lt 11 ] && echo "" &&\
        echo "ERROR in post_process: invalid args num($#/10)" &&\
        echo "usage: post_process target_soc partmap result_dir bl1_out third_out param_out kernel_out dtb_out boot_part_size android_out bl1_target_name logo_file_path" &&\
        exit 0

    print_build_info "post process"

    local soc=${1}
    local partmap=${2}
    local result_dir=${3}
    local bl1_out=${4}
    local third_out=${5}
    local params_out=${6}
    local kernel_out=${7}
    local dtb_out=${8}
    local boot_partition_size=${9}
    local android_out=${10}
    local bl1_target_name=${11}
    local logo_path=${12:-"nologo"}
    local arch=

    mkdir -p ${result_dir}

    echo -n "copy ${partmap} ..."
    cp ${partmap} ${result_dir}/partmap.txt
    echo " done"

    if [ "${bl1_out}" != "nop" ]; then
        echo -n "copy ${bl1_out} ..."
        cp ${bl1_out}/bl1-emmcboot.bin ${result_dir}
        if [ "${soc}" == "s5p4418" ]; then
            cp ${bl1_out}/../bl1-${bl1_target_name}-usb.bin ${result_dir}/bl1-usbboot.bin
        else
            cp ${bl1_out}/bl1-${bl1_target_name}.bin ${result_dir}/bl1-usbboot.bin
        fi
        echo " done"
    fi

    if [ "${third_out}" != "nop" ]; then
        echo -n "copy ${third_out} ..."
        cp ${third_out}/*.img ${result_dir}
        echo " done"
    fi

    echo -n "copy ${params_out} ..."
    cp ${params_out}/params*.bin ${result_dir}
    echo " done"


    test -f ${android_out}/bootloader && \
        cp ${android_out}/bootloader ${result_dir}
    if [ -f ${android_out}/boot.img ]; then
        cp ${android_out}/boot.img ${result_dir}
    else
        mkdir -p ${result_dir}/boot
        echo -n "copy ${kernel_out} ..."
        test -f ${kernel_out}/Image && \
            cp ${kernel_out}/Image ${result_dir}/boot
        test -f ${kernel_out}/zImage && \
            cp ${kernel_out}/zImage ${result_dir}/boot
        if [ "${logo_path}" != "nologo" ]; then
            cp ${logo_path} ${result_dir}/boot
        fi
        echo " done"

        echo -n "copy ${dtb_out} ..."
        cp ${dtb_out}/*.dtb ${result_dir}/boot
        echo " done"

        echo -n "copy ${android_out} ..."
        cp ${android_out}/ramdisk.img ${result_dir}/boot

        if [ "${soc}" == "s5p4418" ]; then
            arch=arm
        elif [ "${soc}" == "s5p6818" ]; then
            arch=arm64
        fi
        cp ${android_out}/ramdisk.img ${result_dir}/boot/ramdisk.img.org
        ${TOP}/device/nexell/u-boot/u-boot-2016.01/tools/mkimage \
            -n 'Ramdisk Image' -A ${arch} -O linux -T ramdisk -C none -a 0 -e 0 \
            -d ${result_dir}/boot/ramdisk.img.org ${result_dir}/boot/ramdisk.img
        rm -f ${result_dir}/boot/ramdisk.img.org
        ${TOP}/device/nexell/tools/make_ext4fs -s -T -1 -l ${boot_partition_size} \
            -a boot ${result_dir}/boot.img ${result_dir}/boot
        rm -rf ${result_dir}/boot
    fi
    test -f ${android_out}/recovery.img && \
        cp ${android_out}/recovery.img ${result_dir}
    cp ${android_out}/system.img ${result_dir}
    cp ${android_out}/userdata.img ${result_dir}
    cp ${android_out}/vendor.img ${result_dir}
    echo " done"

    if [ "${BUILD_DIST}" == "true" ]; then
        local board_name=$(basename ${android_out})
        echo "DIST build postprocess"

        # For make ota_update.zip package
        local target_files_suffix_date=`date +%Y-%m-%d-%H_%M_00`
        cp ${TOP}/out/dist/${board_name}_auto-target_files-eng.$(whoami).zip ${result_dir}/target_files.zip
        # For incremental dist build.
        cp ${TOP}/out/dist/${board_name}_auto-target_files-eng.$(whoami).zip ${result_dir}/target_files_${target_files_suffix_date}.zip

        if [ "${OTA_INCREMENTAL}" == "true" ]; then
            test -z ${OTA_PREVIOUS_FILE} && echo "No valid previous target.zip(${OTA_PREVIOUS_FILE})" || \
                python ${TOP}/build/tools/releasetools/ota_from_target_files.py \
                       --full_bootloader \
                       -i ${OTA_PREVIOUS_FILE} ${result_dir}/target_files.zip \
                       ${result_dir}/ota_update.zip
        else
            python ${TOP}/build/tools/releasetools/ota_from_target_files.py \
                   --full_bootloader \
                   ${result_dir}/target_files.zip ${result_dir}/ota_update.zip
        fi
        echo "build dist Done"
    fi

    generate_update_script ${result_dir}
    generate_usb_boot ${result_dir}

    # misc.img copy for OTA A/B update
    # This file use to only fastboot download.
    cp ${TOP}/device/nexell/tools/misc.img ${result_dir}/.

    print_build_done
}

##
# args
# $1: patch files directory
function patch_common()
{
    local patch_dir=${1}
    for f in $(ls ${patch_dir}); do
        echo "patch file --> ${f}"
        patch_path=$(echo -n ${f} | sed -e "s/@/\//g")
        echo "patch_path --> ${patch_path}"
        cd ${TOP}/${patch_path}
        patch -N -s -r - -p0 < ${patch_dir}/${f} || true
        cd ${TOP}
    done
}
function patches()
{
    patch_common ${TOP}/device/nexell/patch
}

function quickboot_patches()
{
    patch_common ${TOP}/device/nexell/quickboot/patch
}

##
# args
# $1: target soc(s5p4418, nxp4330)
# $2: load, jump address
# $3: result folder
function gen_boot_usb_script_4418()
{
    local soc="${1}"
    local address=${2}
    local result=${3}

    echo "#!/bin/bash" > ${result}/boot_by_usb.sh
    echo "" >>  ${result}/boot_by_usb.sh

    echo "sudo ./usb-downloader -t ${soc} -b bl1-usbboot.bin -a 0xffff0000 -j 0xffff0000" >> ${result}/boot_by_usb.sh
    echo "sleep 3" >> ${result}/boot_by_usb.sh
    echo "sudo ./usb-downloader -t ${soc}  -f fip-loader-usb.img -m" >> ${result}/boot_by_usb.sh
}

##
# args
# $1: kernel image path
# $2: dtb image path
# $3: ramdisk image path
# $4: output image path
# $5: page size
# $6: kernel extra cmdline
function make_android_bootimg_legacy()
{
	local mkbootimg=${TOP}/out/host/linux-x86/bin/mkbootimg
	local kernel=${1}
	local dtb=${2}
	local ramdisk=${3}
	local output=${4}
	local pagesize=${5}
	local cmdline=${6}

	local args="--second ${dtb} --kernel ${kernel} --ramdisk ${ramdisk} --pagesize ${pagesize} --cmdline ${cmdline}"
	local version_args="--os_version 7.1.2 --os_patch_level 2017-07-05"

	echo "mkbootimg --> ${mkbootimg} ${args} ${version_args} --output ${output}"
	${mkbootimg} ${args} ${version_args} --output ${output}
}

##
# args
# $1: kernel image path
# $2: dtb image path
# $3: ramdisk image path
# $4: output image path
# $5: page size
# $6: kernel extra cmdline
function make_android_bootimg()
{
    local mkbootimg=${TOP}/out/host/linux-x86/bin/mkbootimg
    local kernel=${1}
    local dtb=${2}
    local ramdisk=${3}
    local output=${4}
    local pagesize=${5}
    local cmdline=${6}

    # ----------------------------------------------------------
    # For OTA A/B update, ramdisk.img not used.
    # ----------------------------------------------------------
    local args="--second ${dtb} --kernel ${kernel} --pagesize ${pagesize} --cmdline ${cmdline}"
    local version_args="--os_version 7.1.2 --os_patch_level 2017-07-05"

    echo "mkbootimg --> ${mkbootimg} ${args} ${version_args} --output ${output}"

    ${mkbootimg} ${args} ${version_args} --output ${output}
}

##
# args
# $1: file path
# $2: align
function get_fsize()
{
    local f=$1
    local align=$2
    local fsize=$(ls -al ${f} | awk '{print $5}')
    fsize=$(((${fsize} + ${align} - 1) / ${align}))
    fsize=$((${fsize} * ${align}))
    echo -n ${fsize}
}

# Android boot.img
# See system/core/mkbootimg/bootimg.h
# /*
# ** +-----------------+
# ** | boot header     | 1 page
# ** +-----------------+
# ** | kernel          | n pages
# ** +-----------------+
# ** | ramdisk         | m pages
# ** +-----------------+
# ** | second stage    | o pages
# ** +-----------------+
# **
# ** n = (kernel_size + page_size - 1) / page_size
# ** m = (ramdisk_size + page_size - 1) / page_size
# ** o = (second_size + page_size - 1) / page_size
# **
# ** 0. all entities are page_size aligned in flash
# ** 1. kernel and ramdisk are required (size != 0)
# ** 2. second is optional (second_size == 0 -> no second)
# ** 3. load each element (kernel, ramdisk, second) at
# **    the specified physical address (kernel_addr, etc)
# ** 4. prepare tags at tag_addr.  kernel_args[] is
# **    appended to the kernel commandline in the tags.
# ** 5. r0 = 0, r1 = MACHINE_TYPE, r2 = tags_addr
# ** 6. if second_size != 0: jump to second_addr
# **    else: jump to kernel_addr
# */

##
# args
# $1: partmap file path
# $2: part name(ex> boot:emmc)
function get_partition_offset()
{
    local partmap=$1
    local name=$2
    local offset=$(grep ${name} ${partmap} | awk -F ':' '{print $4}' | awk -F ',' '{print $1}')
    echo -n ${offset}
}

##
# args
# $1: partmap file path
# $2: image name(ex> bootloader, system.img)
function get_partition_size()
{
    local partmap=$1
    local name=$2
    local size=$(grep ${name} ${partmap} | awk -F ':' '{print $4}' | awk -F ',' '{print $2}')
    local size_decimal=$(printf "%d" ${size})
    echo -n ${size_decimal}
}

##
# args
# $1: value(decimal)
# $2: block size
function get_blocknum_hex()
{
    local value=$1
    local block_size=$2
    local blocknum_hex=$(printf "0x%x" $((${value}/${block_size})))
    echo -n ${blocknum_hex}
}

##
# args
# $1: partmap file path
# $2: load address(hex) of u-boot boot.img
# $3: PAGE_SIZE
# $4: kernel image path
# $5: dtb image path
# $6: ramdisk image path
# $7: part name(ex> boot:emmc, recovery:emmc)
function make_uboot_bootcmd_legacy()
{
	local partmap=$1
	local load_addr=$2
	local page_size=$3
	local kernel=$4
	local dtb=$5
	local ramdisk=$6
	local partname=$7

	local boot_header_size=${page_size}
	local partition_start_offset=$(get_partition_offset ${partmap} ${partname})
	local partition_start_block_num_hex=$(get_blocknum_hex ${partition_start_offset} 512)
	local kernel_size=$(get_fsize ${kernel} ${page_size})
	local dtb_size=$(get_fsize ${dtb} ${page_size})
	local ramdisk_size=$(get_fsize ${ramdisk} ${page_size})
	local total_size=$((${boot_header_size} + ${kernel_size} + ${ramdisk_size} + ${dtb_size}))
	local total_size_block_num_hex=$(get_blocknum_hex ${total_size} 512)
	local ramdisk_start_address_hex=$(printf "%x" $((${load_addr} + ${boot_header_size} + ${kernel_size})))
	local dtb_start_address_hex=$(printf "%x" $((${load_addr} + ${boot_header_size} + ${kernel_size} + ${ramdisk_size})))

	local bootcmd=
	if [ "${TARGET_SOC}" == "s5p4418" ]; then
		local dtb_offset=$((${partition_start_offset} + ${boot_header_size} + ${kernel_size} + ${ramdisk_size}))
		local dtb_offset_block_num_hex=$(get_blocknum_hex ${dtb_offset} 512)
		local dtb_size_block_num_hex=$(get_blocknum_hex ${dtb_size} 512)
		local dtb_size_hex=$(printf "%x" ${dtb_size})
		local dtb_dest_addr=0x49000000

		local ramdisk_offset=$((${partition_start_offset} + ${boot_header_size} + ${kernel_size}))
		local ramdisk_offset_block_num_hex=$(get_blocknum_hex ${ramdisk_offset} 512)
		local ramdisk_size_hex=$(printf "%x" ${ramdisk_size})
		local ramdisk_size_block_num_hex=$(get_blocknum_hex ${ramdisk_size} 512)
		local ramdisk_dest_addr=0x48000000

		local kernel_start_hex=$(printf "%x" $((${load_addr}+${boot_header_size})))
		# echo "dtb_offset_hex --> ${dtb_offset_block_num_hex}"
		# echo "dtb_size_hex --> ${dtb_size_block_num_hex}"
		# echo "ramdisk_offset_block_num_hex --> ${ramdisk_offset_block_num_hex}"
		# echo "ramdisk_size_hex --> ${ramdisk_size_block_num_hex}"
		bootcmd="mmc read ${load_addr} ${partition_start_block_num_hex} ${total_size_block_num_hex};\
			cp ${ramdisk_start_address_hex} ${ramdisk_dest_addr} ${ramdisk_size_hex};\
			cp ${dtb_start_address_hex} ${dtb_dest_addr} ${dtb_size_hex};\
			bootz ${kernel_start_hex} ${ramdisk_dest_addr}:${ramdisk_size_hex} ${dtb_dest_addr}"
	else
		bootcmd="mmc read ${load_addr} ${partition_start_block_num_hex} ${total_size_block_num_hex}; bootm ${load_addr} ${ramdisk_start_address_hex} ${dtb_start_address_hex}"
	fi

	echo -n ${bootcmd}
}

## ---------------------------------------------
# ===   args description   ===
# $1: partmap file path
# $2: load address(hex) of u-boot boot.img
# $3: PAGE_SIZE
# $4: kernel image path
# $5: dtb image path
# $6: ramdisk image path
# $7: part name(ex> boot_a:emmc, recovery:emmc)
# $8: part name(ex> boot_b:emmc, recovery:emmc)
# $9: return array bootcmd
# $10: return vendor select command
## ---------------------------------------------
function make_uboot_bootcmd()
{
    local partmap=$1
    local load_addr=$2
    local page_size=$3
    local kernel=$4
    local dtb=$5
    local ramdisk=$6
    local partname=($7 $8)

    # return array
    local -n bootcmd=$9
    local -n vendor_blk_select=${10}

    for pn in "${partname[@]}";
    do
        local boot_header_size=${page_size}
        local partition_start_offset=$(get_partition_offset ${partmap} ${pn})
        local partition_start_block_num_hex=$(get_blocknum_hex ${partition_start_offset} 512)
        local kernel_size=$(get_fsize ${kernel} ${page_size})
        local dtb_size=$(get_fsize ${dtb} ${page_size})
        local ramdisk_size=$(get_fsize ${ramdisk} ${page_size})
        local total_size=$((${boot_header_size} + ${kernel_size} + ${ramdisk_size} + ${dtb_size}))
        local total_size_block_num_hex=$(get_blocknum_hex ${total_size} 512)
        local ramdisk_start_address_hex=$(printf "%x" $((${load_addr} + ${boot_header_size} + ${kernel_size})))
        local dtb_start_address_hex=$(printf "%x" $((${load_addr} + ${boot_header_size} + ${kernel_size} + ${ramdisk_size})))

        if [ "${TARGET_SOC}" == "s5p4418" ]; then
            local dtb_offset=$((${partition_start_offset} + ${boot_header_size} + ${kernel_size} + ${ramdisk_size}))
            local dtb_offset_block_num_hex=$(get_blocknum_hex ${dtb_offset} 512)
            local dtb_size_block_num_hex=$(get_blocknum_hex ${dtb_size} 512)
            local dtb_size_hex=$(printf "%x" ${dtb_size})
            local dtb_dest_addr=0x49000000

            local ramdisk_offset=$((${partition_start_offset} + ${boot_header_size} + ${kernel_size}))
            local ramdisk_offset_block_num_hex=$(get_blocknum_hex ${ramdisk_offset} 512)
            local ramdisk_size_hex=$(printf "%x" ${ramdisk_size})
            local ramdisk_size_block_num_hex=$(get_blocknum_hex ${ramdisk_size} 512)
            local ramdisk_dest_addr=0x48000000

            local kernel_start_hex=$(printf "%x" $((${load_addr}+${boot_header_size})))
            local var='${change_devicetree}'

            if [ ${pn} == "boot_a:emmc" ];then  # slot A
              bootcmd+=("mmc read ${load_addr} ${partition_start_block_num_hex} ${total_size_block_num_hex};\
                run vendor_blk_select_a;\
                if test !-z $var; then run change_devicetree; fi;\
                cp ${ramdisk_start_address_hex} ${ramdisk_dest_addr} ${ramdisk_size_hex};\
                cp ${dtb_start_address_hex} ${dtb_dest_addr} ${dtb_size_hex};\
                bootz ${kernel_start_hex} - ${dtb_dest_addr}")

              vendor_blk_select+=("fdt addr ${dtb_start_address_hex};\
                fdt set /firmware/android/fstab/vendor dev \"/dev/block/mmcblk0p8\";\
                fdt print /firmware/android/fstab/vendor dev")

              # for DEBUG
              # vendor_blk_select+=("fdt addr ${dtb_start_address_hex};\
              #   echo \"old vendor partition in DTB\";\
              #   fdt print /firmware/android/fstab/vendor dev;\
              #   fdt set /firmware/android/fstab/vendor dev \"/dev/block/mmcblk0p6\";\
              #   echo \"new vendor partition in DTB\";\
              #   fdt print /firmware/android/fstab/vendor dev")
            else # slot B
              bootcmd+=("mmc read ${load_addr} ${partition_start_block_num_hex} ${total_size_block_num_hex};\
                run vendor_blk_select_b;\
                if test !-z $var; then run change_devicetree; fi;\
                cp ${ramdisk_start_address_hex} ${ramdisk_dest_addr} ${ramdisk_size_hex};\
                cp ${dtb_start_address_hex} ${dtb_dest_addr} ${dtb_size_hex};\
                bootz ${kernel_start_hex} - ${dtb_dest_addr}")

              vendor_blk_select+=("fdt addr ${dtb_start_address_hex};\
                fdt set /firmware/android/fstab/vendor dev \"/dev/block/mmcblk0p9\";\
                fdt print /firmware/android/fstab/vendor dev")

              # # for DEBUG
              # vendor_blk_select+=("fdt addr ${dtb_start_address_hex};\
              #   echo \"old vendor partition in DTB\";\
              #   fdt print /firmware/android/fstab/vendor dev;\
              #   fdt set /firmware/android/fstab/vendor dev \"/dev/block/mmcblk0p7\";\
              #   echo \"new vendor partition in DTB\";\
              #   fdt print /firmware/android/fstab/vendor dev")
            fi
        else
            local dtb_dest_addr_hex=$(printf "%x" $((${load_addr} + ${boot_header_size} + ${kernel_size} + ${ramdisk_size} + 1048576)))
            local dtb_size_hex=$(printf "%x" ${dtb_size})
            local var='${change_devicetree}'
            if [ ${pn} == "boot_a:emmc" ];then  # slot A
                bootcmd+=("mmc read ${load_addr} ${partition_start_block_num_hex} ${total_size_block_num_hex}; cp ${dtb_start_address_hex} ${dtb_dest_addr_hex} ${dtb_size_hex}; run vendor_blk_select_a;if test !-z $var; then echo run change_devicetree; run change_devicetree; fi; bootm ${load_addr} - ${dtb_dest_addr_hex}")
                vendor_blk_select+=("fdt addr ${dtb_dest_addr_hex};\
                  fdt set /firmware/android/fstab/vendor dev \"/dev/block/mmcblk0p8\";\
                  fdt print /firmware/android/fstab/vendor dev")
            else # slot B
                bootcmd+=("mmc read ${load_addr} ${partition_start_block_num_hex} ${total_size_block_num_hex}; cp ${dtb_start_address_hex} ${dtb_dest_addr_hex} ${dtb_size_hex}; run vendor_blk_select_b; if test !-z $var; then echo run change_devicetree; run change_devicetree; fi; bootm ${load_addr} - ${dtb_dest_addr_hex}")
                vendor_blk_select+=("fdt addr ${dtb_dest_addr_hex};\
                  fdt set /firmware/android/fstab/vendor dev \"/dev/block/mmcblk0p9\";\
                  fdt print /firmware/android/fstab/vendor dev")
            fi
            # bootcmd+=("mmc read ${load_addr} ${partition_start_block_num_hex} ${total_size_block_num_hex}; bootm ${load_addr} ${ramdisk_start_address_hex} ${dtb_start_address_hex}")
        fi

    done
}

##
# args
# $1: total size(must dividable by 512)
# $2: bl1 file path
# $3: loader offset
# $4: loader file path
# $5: secure offset
# $6: secure file path
# $7: non-secure offset
# $8: non-secure file path
# $9: param offset
# $10: param file path
# $11: logo offset
# $12: logo file path
# $13: outfile path
function make_bootloader_legacy()
{
	local total_size=${1}
	local bl1=${2}
	local loader_offset=${3}
	local loader=${4}
	local secure_offset=${5}
	local secure=${6}
	local nonsecure_offset=${7}
	local nonsecure=${8}
	local param_offset=${9}
	local param=${10}
	local logo_offset=${11}
	local logo=${12}
	local out=${13}

	test -f ${out} && rm -f ${out}

	echo "total_size --> ${total_size}"
	echo "bl1 --> ${bl1}"
	echo "loader_offset --> ${loader_offset}"
	echo "loader --> ${loader}"
	echo "secure_offset --> ${secure_offset}"
	echo "secure --> ${secure}"
	echo "nonsecure_offset --> ${nonsecure_offset}"
	echo "nonsecure --> ${nonsecure}"
	echo "param_offset --> ${param_offset}"
	echo "param --> ${param}"
	echo "logo_offset --> ${logo_offset}"
	echo "logo --> ${logo}"
	echo "out --> ${out}"

	local count_by_512=$((${total_size}/512))
	dd if=/dev/zero of=${out} bs=512 count=${count_by_512}
	dd if=${bl1} of=${out} bs=1
	dd if=${loader} of=${out} seek=${loader_offset} bs=1
	dd if=${secure} of=${out} seek=${secure_offset} bs=1
	dd if=${nonsecure} of=${out} seek=${nonsecure_offset} bs=1
	dd if=${param} of=${out} seek=${param_offset} bs=1
	dd if=${logo} of=${out} seek=${logo_offset} bs=1
	sync
}

##
# args
# $1: total size(must dividable by 512)
# $2: bl1 file path
# $3: loader offset
# $4: loader file path
# $5: secure offset
# $6: secure file path
# $7: non-secure offset
# $8: non-secure file path
# $9: param offset
# $10: param file path
# $11: logo offset
# $12: logo file path
# $13: outfile path
function make_bootloader()
{
    local total_size=${1}
    local loader=${2}
    local secure_offset=${3}
    local secure=${4}
    local nonsecure_offset=${5}
    local nonsecure=${6}
    local param_offset=${7}
    local param=${8}
    local logo_offset=${9}
    local logo=${10}
    local out=${11}

    test -f ${out} && rm -f ${out}

    echo "total_size --> ${total_size}"
    echo "loader --> ${loader}"
    echo "secure_offset --> ${secure_offset}"
    echo "secure --> ${secure}"
    echo "nonsecure_offset --> ${nonsecure_offset}"
    echo "nonsecure --> ${nonsecure}"
    echo "param_offset --> ${param_offset}"
    echo "param --> ${param}"
    echo "logo_offset --> ${logo_offset}"
    echo "logo --> ${logo}"
    echo "out --> ${out}"

    local count_by_512=$((${total_size}/512))
    echo "=========================="
    echo ${count_by_512}
    dd if=/dev/zero of=${out} bs=512 count=${count_by_512}
    dd if=${loader} of=${out} bs=1
    dd if=${secure} of=${out} seek=${secure_offset} bs=1
    dd if=${nonsecure} of=${out} seek=${nonsecure_offset} bs=1
    dd if=${param} of=${out} seek=${param_offset} bs=1
    dd if=${logo} of=${out} seek=${logo_offset} bs=1

    #Zero padding
    out_size=`du -b "${out}" | cut -f1`
    diffsize=$((${total_size}-${out_size}))
    echo "${out} file size = ${out_size}"
    echo "add zero pad ${diffsize} byte"
    dd if=/dev/zero bs=1 count=${diffsize} >> ${out}

    sync
}

##
# args
# $1: board name
function generate_key()
{
    declare -a security=("testkey" "shared" "media" "release" "platform")
    local board=$1
    echo "key generation for ${board}"
    if ! [ -d ${TOP}/device/nexell/${board}/signing_keys ];then
        mkdir -p ${TOP}/device/nexell/${board}/signing_keys
    fi

    for i in ${security[@]}
    do
        if [ ! -e  ${TOP}/device/nexell/${board}/signing_keys/$i.pk8 ];then
            ${TOP}/device/nexell/tools/mkkey.sh $i ${board}
        fi
    done
    echo "End of generate_key"
}
