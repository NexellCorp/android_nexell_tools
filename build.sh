#!/bin/bash

set -e

TOP=`pwd`
RESULT_DIR=${TOP}/result
export TOP RESULT_DIR

BUILD_ALL=true
BUILD_UBOOT=false
BUILD_KERNEL=false
BUILD_MODULE=false
BUILD_ANDROID=false
BUILD_DIST=false
CLEAN_BUILD=false
ROOT_DEVICE_TYPE=sd
WIFI_DEVICE_NAME=rtl8188
#BUILD_TAG=user
BUILD_TAG=userdebug
WIFI_DRIVER_PATH="hardware/realtek/wlan/driver/rtl8188EUS_linux_v4.3.0.3_10997.20140327"
VERBOSE=false
## OTA variables
OTA_INCREMENTAL=false
OTA_PREVIOUS_FILE=
OTA_UPDATE_2NDBOOT=true
OTA_UPDATE_UBOOT=true

BOARD_NAME=

function check_top()
{
    if [ ! -d .repo ]; then
        echo "You must execute this script at ANDROID TOP Directory"
        exit 1
    fi
}

function usage()
{
    echo "Usage: $0 -b <board-name> [-r <root-device-type> -c -w <wifi-device-name> -t u-boot -t kernel -t module -t android -t dist [-i previous_target.zip -d 2ndboot -d u-boot ]]"
    echo -e '\n -b <board-name> : target board name (available boards: "'"$(get_available_board)"'")'
    echo " -r <root-device-type> : your root device type(sd, nand, usb), default sd"
    echo " -c : clean build, default no"
    echo " -w : wifi device name (rtl8188, rtl8712, bcm), default rtl8188"
    echo " -v : if you want to view verbose log message, specify this, default no"
    echo " -t u-boot  : if you want to build u-boot, specify this, default yes"
    echo " -t kernel  : if you want to build kernel, specify this, default yes"
    echo " -t module  : if you want to build driver modules, specify this, default yes"
    echo " -t android : if you want to build android, specify this, default yes"
    echo " -t none    : if you want to only post process, specify this, default no"
    echo " -t dist    : if you want to build distribute image, specify this, default no"
    echo "    -i previous_target.zip : if you want incremental OTA update, specify this, default no"
    echo "    -d 2ndboot             : if you don't want to update OTA 2ndboot, specify this, default no"
    echo "    -d u-boot              : if you don't want to update OTA u-boot, specify this, default no"
}

function parse_args()
{
    TEMP=`getopt -o "b:r:t:i:d:chv" -- "$@"`
    eval set -- "$TEMP"

    while true; do
        case "$1" in
            -b ) BOARD_NAME=$2; shift 2 ;;
            -r ) ROOT_DEVICE_TYPE=$2; shift 2 ;;
            -c ) CLEAN_BUILD=true; shift 1 ;;
            -w ) WIFI_DEVICE_NAME=$2; shift 2 ;;
            -t ) case "$2" in
                    u-boot  ) BUILD_ALL=false; BUILD_UBOOT=true ;;
                    kernel  ) BUILD_ALL=false; BUILD_KERNEL=true ;;
                    module  ) BUILD_ALL=false; BUILD_MODULE=true ;;
                    android ) BUILD_ALL=false; BUILD_ANDROID=true ;;
                    dist    ) BUILD_ALL=false; BUILD_DIST=true ;;
                    none    ) BUILD_ALL=false ;;
                 esac
                 shift 2 ;;
            -i ) OTA_INCREMENTAL=true; OTA_PREVIOUS_FILE=$2; shift 2 ;;
            -d ) case "$2" in
                    2ndboot ) OTA_UPDATE_2NDBOOT=false ;;
                    u-boot  ) OTA_UPDATE_UBOOT=false ;;
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
        echo "=============================================="
        echo " print args"
        echo "=============================================="
        echo -e "BOARD_NAME:\t\t${BOARD_NAME}"
        echo -e "WIFI_DEVICE_NAME:\t${WIFI_DEVICE_NAME}"
        if [ ${BUILD_ALL} == "true" ]; then
            echo -e "Build:\t\t\tAll"
        else
            if [ ${BUILD_UBOOT} == "true" ]; then
                echo -e "Build:\t\t\tu-boot"
            fi
            if [ ${BUILD_KERNEL} == "true" ]; then
                echo -e "Build:\t\t\tkernel"
            fi
            if [ ${BUILD_MODULE} == "true" ]; then
                echo -e "Build:\t\t\tmodule"
            fi
            if [ ${BUILD_ANDROID} == "true" ]; then
                echo -e "Build:\t\t\tandroid"
            fi
            if [ ${BUILD_DIST} == "true" ]; then
                echo -e "Build:\t\t\tdistribution"
            fi
        fi
        echo -e "ROOT_DEVICE_TYPE:\t${ROOT_DEVICE_TYPE}"
        echo -e "CLEAN_BUILD:\t\t${CLEAN_BUILD}"
    fi
}

function clean_up()
{
    if [ ${CLEAN_BUILD} == "true" ]; then
        echo ""
        echo -e -n "clean up...\t"

        if [ ${BUILD_ALL} == "true" ] || [ ${BUILD_ANDROID} == "true" ]; then
            rm -rf ${RESULT_DIR}
            make clean
        fi

        echo "End"
    fi
}

function apply_uboot_nand_config()
{
    if [ ${VERBOSE} == "true" ]; then
        echo ""
        echo -e -n "apply nand booting config to u-boot...\t"
    fi

    local dest_file=${TOP}/u-boot/include/configs/nxp4330q_${BOARD_NAME}.h
    # backup: include/configs/nxp4330q_${BOARD_NAME}.h.org
    cp ${dest_file} ${dest_file}.org

    local config_logo_load="    #define CONFIG_CMD_LOGO_LOAD    \"nand read 0x62000000 0x2000000 0x400000;bootlogo 0x62000000\""
    sed -i "s/.*#define.*CONFIG_CMD_LOGO_LOAD.*/${config_logo_load}/g" ${dest_file}

    local config_bootcommand="#define CONFIG_BOOTCOMMAND \"nand read 0x44000000 0xc00000 0x600000;nand read 43000000 0x1800000 400000;bootm 0x44000000\""
    sed -i "s/#define.*CONFIG_BOOTCOMMAND.*/${config_bootcommand}/g" ${dest_file}

    local config_cmd_nand="#define CONFIG_CMD_NAND"
    sed -i "s/\/\/#define.*CONFIG_CMD_NAND/${config_cmd_nand}/g" ${dest_file}

    local config_fastboot_nandbsp="#define CFG_FASTBOOT_NANDBSP"
    sed -i "s/#define.*CFG_FASTBOOT_SDMMCBSP/${config_fastboot_nandbsp}/g" ${dest_file}

    if [ ${VERBOSE} == "true" ]; then
        echo "End"
    fi
}

function apply_uboot_partition_config()
{
    if [ ${VERBOSE} == "true" ]; then
        echo ""
        echo -e -n "apply sd/usb partition info at android BoardConfig.mk to u-boot...\t"
    fi

    local dest_file=${TOP}/u-boot/include/configs/nxp4330q_${BOARD_NAME}.h
    local src_file=${TOP}/device/nexell/${BOARD_NAME}/BoardConfig.mk
    # backup: include/configs/nxp4330q_${BOARD_NAME}.h.org
    cp ${dest_file} ${dest_file}.org

    local system_partition_size=`awk '/BOARD_SYSTEMIMAGE_PARTITION_SIZE/{print $3}' ${src_file}`
    local cache_partition_size=`awk '/BOARD_CACHEIMAGE_PARTITION_SIZE/{print $3}' ${src_file}`

    echo "system_partition_size: ${system_partition_size}, cache_partition_size: ${cache_partition_size}"

    sed -i "s/#define CFG_SYSTEM_PART_SIZE.*/#define CFG_SYSTEM_PART_SIZE    (${system_partition_size})/g" ${dest_file}
    sed -i "s/#define CFG_CACHE_PART_SIZE.*/#define CFG_CACHE_PART_SIZE     (${cache_partition_size})/g" ${dest_file}

    if [ ${VERBOSE} == "true" ]; then
        echo "End"
    fi
}

function enable_uboot_sd_root()
{
    local src_file=${TOP}/u-boot/include/configs/nxp4330q_${BOARD_NAME}.h
    sed -i 's/^\/\/#define[[:space:]]CONFIG_CMD_MMC/#define CONFIG_CMD_MMC/g' ${src_file}
    sed -i 's/^\/\/#define[[:space:]]CONFIG_LOGO_DEVICE_MMC/#define CONFIG_LOGO_DEVICE_MMC/g' ${src_file}
    local root_device_num=$(get_sd_device_number ${TOP}/device/nexell/${BOARD_NAME}/fstab.${BOARD_NAME})
    sed -i 's/^#define[[:space:]]CONFIG_BOOTCOMMAND.*/#define CONFIG_BOOTCOMMAND \"ext4load mmc '"${root_device_num}"':1 0x48000000 uImage;ext4load mmc '"${root_device_num}"':1 0x49000000 root.img.gz;bootm 0x48000000\"/g' ${src_file}
    sed -i 's/.*#define[[:space:]]CONFIG_CMD_LOGO_WALLPAPERS.*/    #define CONFIG_CMD_LOGO_WALLPAPERS \"ext4load mmc '"${root_device_num}"':1 0x47000000 logo.bmp; drawbmp 0x47000000\"/g' ${src_file}
    sed -i 's/.*#define[[:space:]]CONFIG_CMD_LOGO_BATTERY.*/    #define CONFIG_CMD_LOGO_BATTERY \"ext4load mmc '"${root_device_num}"':1 0x47000000 battery.bmp; drawbmp 0x47000000\"/g' ${src_file}
    sed -i 's/.*#define[[:space:]]CONFIG_CMD_LOGO_UPDATE.*/    #define CONFIG_CMD_LOGO_UPDATE \"ext4load mmc '"${root_device_num}"':1 0x47000000 update.bmp; drawbmp 0x47000000\"/g' ${src_file}
}

function disable_uboot_sd_root()
{
    local src_file=${TOP}/u-boot/include/configs/nxp4330q_${BOARD_NAME}.h
    echo "src_file: ${src_file}"
    sed -i 's/^#define[[:space:]]CONFIG_CMD_MMC/\/\/#define CONFIG_CMD_MMC/g' ${src_file}
    sed -i 's/^#define[[:space:]]CONFIG_LOGO_DEVICE_MMC/\/\/#define CONFIG_LOGO_DEVICE_MMC/g' ${src_file}
}

function enable_uboot_nand_root()
{
    local src_file=${TOP}/u-boot/include/configs/nxp4330q_${BOARD_NAME}.h
    sed -i 's/^\/\/#define[[:space:]]CONFIG_CMD_NAND/#define CONFIG_CMD_NAND/g' ${src_file}
    sed -i 's/^\/\/#define[[:space:]]CONFIG_LOGO_DEVICE_NAND/#define CONFIG_LOGO_DEVICE_NAND/g' ${src_file}
    sed -i 's/^\/\/#define[[:space:]]CONFIG_CMD_UBIFS/#define CONFIG_CMD_UBIFS/g' ${src_file}
    sed -i 's/^#define[[:space:]]CONFIG_BOOTCOMMAND.*/#define CONFIG_BOOTCOMMAND \"nand read 0x48000000 0xc00000 0x600000;nand read 0x49000000 0x1800000 0x100000;bootm 0x48000000\"/g' ${src_file}
    sed -i 's/.*#define[[:space:]]CONFIG_CMD_LOGO_WALLPAPERS.*/    #define CONFIG_CMD_LOGO_WALLPAPERS \"nand read 0x47000000 0x2000000 0x400000; drawbmp 0x47000000\"/g' ${src_file}
    sed -i 's/.*#define[[:space:]]CONFIG_CMD_LOGO_BATTERY.*/    #define CONFIG_CMD_LOGO_BATTERY \"nand read 0x47000000 0x2800000 0x400000; drawbmp 0x47000000\"/g' ${src_file}
    sed -i 's/.*#define[[:space:]]CONFIG_CMD_LOGO_UPDATE.*/    #define CONFIG_CMD_LOGO_UPDATE \"nand read 0x47000000 0x3000000 0x400000; drawbmp 0x47000000\"/g' ${src_file}
}

function disable_uboot_nand_root()
{
    local src_file=${TOP}/u-boot/include/configs/nxp4330q_${BOARD_NAME}.h
    sed -i 's/^#define[[:space:]]CONFIG_CMD_NAND/\/\/#define CONFIG_CMD_NAND/g' ${src_file}
    sed -i 's/^#define[[:space:]]CONFIG_LOGO_DEVICE_NAND/\/\/#define CONFIG_LOGO_DEVICE_NAND/g' ${src_file}
    sed -i 's/^#define[[:space:]]CONFIG_CMD_UBIFS/\/\/#define CONFIG_CMD_UBIFS/g' ${src_file}
}

function apply_uboot_sd_root()
{
    echo "====> apply sd root"
    disable_uboot_nand_root
    enable_uboot_sd_root
}

function apply_uboot_nand_root()
{
    echo "====> apply nand root"
    disable_uboot_sd_root
    enable_uboot_nand_root
}

function build_uboot()
{
    if [ ${BUILD_ALL} == "true" ] || [ ${BUILD_UBOOT} == "true" ]; then
        echo ""
        echo "=============================================="
        echo "build u-boot"
        echo "=============================================="

        if [ ! -e ${TOP}/u-boot ]; then
            cd ${TOP}
            ln -s linux/bootloader/u-boot-2014.07 u-boot
        fi

        cd ${TOP}/u-boot
        make distclean

        #echo "ROOT_DEVICE_TYPE is ${ROOT_DEVICE_TYPE}"
        #case ${ROOT_DEVICE_TYPE} in
            #sd) apply_uboot_sd_root ;;
            #nand) apply_uboot_nand_root ;;
        #esac

        #make nxp4330q_${BOARD_NAME}_config
        make nxp5430_${BOARD_NAME}_config
        make -j8
        check_result "build-uboot"
        if [ -f include/configs/nxp4330q_${BOARD_NAME}.h.org ]; then
            mv include/configs/nxp4330q_${BOARD_NAME}.h.org include/configs/nxp4330q_${BOARD_NAME}.h
        fi
        cd ${TOP}

        echo "---------- End of build u-boot"
    fi
}

function apply_kernel_nand_config()
{
    local src_file=${TOP}/kernel/arch/arm/configs/nxp4330_${BOARD_NAME}_android_defconfig
    local dst_config=nxp4330_${BOARD_NAME}_android_defconfig.nandboot
    local dst_file=${src_file}.nandboot
    cp ${src_file} ${dst_file}

    # cmdline
    sed -i 's/CONFIG_CMDLINE=.*/CONFIG_CMDLINE=\"console=ttyAMA0,115200n8 ubi.mtd=0 ubi.mtd=1 ubi.mtd=2 androidboot.console=ttyAMA0 init=\/init androidboot.hardware='${BOARD_NAME}' androidboot.serialno=0123456789abcdef\"/g' ${dst_file}
    # mtd
    sed -i 's/.*CONFIG_MTD.*/CONFIG_MTD=y/g' ${dst_file}
    sed -i '/CONFIG_MTD=y/ a\
# CONFIG_MTD_TESTS is not set' ${dst_file}
    sed -i '/# CONFIG_MTD_TESTS.*/ a\
# CONFIG_MTD_REDBOOT_PARTS is not set' ${dst_file}
    sed -i '/CONFIG_MTD_REDBOOT_PARTS.*/ a\
CONFIG_MTD_CMDLINE_PARTS=y' ${dst_file}
    sed -i '/CONFIG_MTD_CMDLINE_PARTS=y/ a\
# CONFIG_MTD_AFS_PARTS is not set' ${dst_file}
    sed -i '/CONFIG_MTD_AFS_PARTS.*/ a\
# CONFIG_MTD_AR7_PARTS is not set' ${dst_file}
    sed -i '/CONFIG_MTD_AR7_PARTS.*/ a\
CONFIG_MTD_CHAR=y' ${dst_file}
    sed -i '/CONFIG_MTD_CHAR=y/ a\
CONFIG_MTD_BLKDEVS=y' ${dst_file}
    sed -i '/CONFIG_MTD_BLKDEVS=y/ a\
CONFIG_MTD_BLOCK=y' ${dst_file}
    sed -i '/CONFIG_MTD_BLOCK=y/ a\
# CONFIG_FTL is not set' ${dst_file}
    sed -i '/CONFIG_FTL.*/ a\
# CONFIG_NFTL is not set' ${dst_file}
    sed -i '/CONFIG_NFTL.*/ a\
# CONFIG_INFTL is not set' ${dst_file}
    sed -i '/CONFIG_INFTL.*/ a\
# CONFIG_RFD_FTL is not set' ${dst_file}
    sed -i '/CONFIG_RFD_FTL.*/ a\
# CONFIG_SSFDC is not set' ${dst_file}
    sed -i '/CONFIG_SSFDC.*/ a\
# CONFIG_SM_FTL is not set' ${dst_file}
    sed -i '/CONFIG_SM_FTL.*/ a\
# CONFIG_MTD_OOPS is not set' ${dst_file}
    sed -i '/CONFIG_MTD_OOPS.*/ a\
# CONFIG_MTD_CFI is not set' ${dst_file}
    sed -i '/CONFIG_MTD_CFI.*/ a\
# CONFIG_MTD_JEDECPROBE is not set' ${dst_file}
    sed -i '/CONFIG_MTD_JEDECPROBE.*/ a\
CONFIG_MTD_MAP_BANK_WIDTH_1=y' ${dst_file}
    sed -i '/CONFIG_MTD_MAP_BANK_WIDTH_1=y/ a\
CONFIG_MTD_MAP_BANK_WIDTH_2=y' ${dst_file}
    sed -i '/CONFIG_MTD_MAP_BANK_WIDTH_2=y/ a\
CONFIG_MTD_MAP_BANK_WIDTH_4=y' ${dst_file}
    sed -i '/CONFIG_MTD_MAP_BANK_WIDTH_4=y/ a\
CONFIG_MTD_CFI_I1=y' ${dst_file}
    sed -i '/CONFIG_MTD_CFI_I1=y/ a\
CONFIG_MTD_CFI_I2=y' ${dst_file}
    sed -i '/CONFIG_MTD_CFI_I2=y/ a\
# CONFIG_MTD_RAM is not set' ${dst_file}
    sed -i '/CONFIG_MTD_RAM.*/ a\
# CONFIG_MTD_ROM is not set' ${dst_file}
    sed -i '/CONFIG_MTD_ROM.*/ a\
# CONFIG_MTD_ABSENT is not set' ${dst_file}
    sed -i '/CONFIG_MTD_ABSENT.*/ a\
CONFIG_MTD_NAND_ECC=y' ${dst_file}
    sed -i '/CONFIG_MTD_NAND_ECC=y/ a\
CONFIG_MTD_NAND=y' ${dst_file}
    sed -i '/CONFIG_MTD_NAND=y/ a\
CONFIG_MTD_NAND_IDS=y' ${dst_file}
    sed -i '/CONFIG_MTD_NAND_IDS=y/ a\
CONFIG_MTD_NAND_NEXELL=y' ${dst_file}
    sed -i '/CONFIG_MTD_NAND_NEXELL=y/ a\
CONFIG_MTD_NAND_ECC_HW=y a\
CONFIG_NAND_RANDOMIZER=y' ${dst_file}
    sed -i '/CONFIG_MTD_NAND_ECC_HW=y/ a\
CONFIG_MTD_UBI=y' ${dst_file}
    sed -i '/CONFIG_MTD_UBI=y/ a\
CONFIG_MTD_UBI_WL_THRESHOLD=4096' ${dst_file}
    sed -i '/CONFIG_MTD_UBI_WL_THRESHOLD=.*/ a\
CONFIG_MTD_UBI_BEB_LIMIT=20' ${dst_file}
    sed -i '/CONFIG_EFS_FS.*/ a\
CONFIG_UBIFS_FS=y' ${dst_file}
    sed -i '/CONFIG_UBIFS_FS=y/ a\
CONFIG_UBIFS_FS_LZO=y' ${dst_file}
    sed -i '/CONFIG_UBIFS_FS_LZO=y/ a\
CONFIG_UBIFS_FS_ZLIB=y' ${dst_file}

    echo ${dst_config}
}

function build_kernel()
{
    if [ ${BUILD_ALL} == "true" ] || [ ${BUILD_KERNEL} == "true" ]; then
        echo ""
        echo "=============================================="
        echo "build kernel"
        echo "=============================================="

        if [ ! -e ${TOP}/kernel ]; then
            cd ${TOP}
            ln -s linux/kernel/kernel-3.4.39 kernel
        fi

        cd ${TOP}/kernel

        #local kernel_config=nxp4330_${BOARD_NAME}_android_defconfig
        local kernel_config=nxp5430_${BOARD_NAME}_android_defconfig
        if [ ${ROOT_DEVICE_TYPE} == "nand" ]; then
            kernel_config=$(apply_kernel_nand_config)
            echo "nand kernel config: ${kernel_config}"
        fi

        make distclean
        cp arch/arm/configs/${kernel_config} .config
        yes "" | make ARCH=arm oldconfig
        make ARCH=arm uImage -j8

        if [ ${ROOT_DEVICE_TYPE} == "nand" ]; then
            rm -f ${TOP}/arch/arm/configs/${kernel_config}
        fi

        check_result "build-kernel"

        echo "---------- End of build kernel"
    fi
}

function build_module()
{
    if [ ${BUILD_ALL} == "true" ] || [ ${BUILD_MODULE} == "true" ]; then
        echo ""
        echo "=============================================="
        echo "build modules"
        echo "=============================================="

        local out_dir=${TOP}/out/target/product/${BOARD}
        mkdir -p ${out_dir}/system/lib/modules

        if [ ${VERBOSE} == "true" ]; then
            echo -n -e "build vr driver..."
        fi
        cd ${TOP}/hardware/nexell/pyrope/prebuilt/modules/vr
        ./build.sh
        if [ ${VERBOSE} == "true" ]; then
            echo "End"
        fi

        if [ ${VERBOSE} == "true" ]; then
            echo -n -e "build coda driver..."
        fi
        cd ${TOP}/linux/nxp5430/modules/coda960
        ./build.sh
        if [ ${VERBOSE} == "true" ]; then
            echo "End"
        fi

        if [ ${VERBOSE} == "true" ]; then
            echo -n -e "build wifi driver..."
        fi
        cd ${TOP}/${WIFI_DRIVER_PATH}
        ./build.sh
        if [ ${VERBOSE} == "true" ]; then
            echo "End"
        fi
        cd ${TOP}

        if [ ${VERBOSE} == "true" ]; then
            echo "End"
        fi

        echo "---------- End of build modules"
    fi
}

function make_android_root()
{
    local out_dir=${TOP}/out/target/product/${BOARD_NAME}
    cd ${out_dir}/root
    sed -i -e '/mount\ yaffs2/ d' -e '/on\ fs/ d' -e '/mount\ mtd/ d' -e '/Mount\ \// d' init.rc

    awk '/console\ \/system/{print; getline; print; getline; print; getline; print; getline; print "    user root"; getline}1' init.rc > /tmp/init.rc
    mv /tmp/init.rc init.rc

    # handle nand boot
    if [ ${ROOT_DEVICE_TYPE} == "nand" ]; then
        rm -f fstab.${BOARD_NAME}
        echo "ubi0:system       /system      ubifs    defaults,noatime,rw    wait" > fstab.${BOARD_NAME}
        echo "ubi1:cache        /cache       ubifs    noatime                wait" >> fstab.${BOARD_NAME}
        echo "ubi2:userdata     /data        ubifs    noatime                wait" >> fstab.${BOARD_NAME}
        local cur_user=`whoami`
        chown ${cur_user}:${cur_user} fstab.${BOARD_NAME}
    fi

    # arrange permission
    chmod 644 *.prop
    chmod 644 *.${BOARD_NAME}
    chmod 644 *.rc

    cd ..
    rm -f root.img.gz
    cd ${TOP}
}

function apply_android_overlay()
{
    cd ${TOP}
    local overlay_dir=${TOP}/hardware/nexell/pyrope/overlay-apps
    local overlay_list_file=${overlay_dir}/files.txt
    local token1=""
    while read line; do
        token1=$(echo ${line} | awk '{print $1}')
        if [ ${token1} == "replace" ]; then
            local src_file=$(echo ${line} | awk '{print $2}')
            local replace_file=$(echo ${line} | awk '{print $3}')
            cp ${overlay_dir}/${src_file} ${RESULT_DIR}/${replace_file}
        elif [ ${token1} == "remove" ]; then
            local remove_file=$(echo ${line} | awk '{print $2}')
            rm -f ${RESULT_DIR}/${remove_file}
        fi
    done < ${overlay_list_file}
}

function remove_android_banned_files()
{
    rm -f ${RESULT_DIR}/system/xbin/su
}

function refine_android_system()
{
    local out_dir=${TOP}/out/target/product/${BOARD_NAME}
    cd ${out_dir}/system
    chmod 644 *.prop
    chmod 644 lib/modules/*
    cd ${TOP}
}

function patch_android()
{
    cd ${TOP}
    local patch_dir=${TOP}/hardware/nexell/pyrope/patch
    local patch_list_file=${patch_dir}/files.txt
    local src_file=""
    local dst_dir=""
    while read line; do
        src_file=$(echo ${line} | awk '{print $1}')
        dst_dir=$(echo ${line} | awk '{print $2}')
        echo "copy ${patch_dir}/${src_file}  =====> ${TOP}/${dst_dir}"
        cp ${patch_dir}/${src_file} ${TOP}/${dst_dir}
    done < ${patch_list_file}
    cd ${TOP}
}

function restore_patch()
{
    cd ${TOP}
    if [ -d ${TOP}/.repo ]; then
        local patch_dir=${TOP}/hardware/nexell/pyrope/patch
        local patch_list_file=${patch_dir}/files.txt
        local src_file=""
        local dst_dir=""
        while read line; do
            src_file=$(echo ${line} | awk '{print $1}')
            dst_dir=$(echo ${line} | awk '{print $2}')
            echo "restore ${TOP}/${dst_dir}/${src_file}"
            cd ${TOP}/${dst_dir}
            git status | grep -q Untracked || git checkout ${src_file}
        done < ${patch_list_file}
        cd ${TOP}
    fi
}

function apply_kernel_headers()
{
    # make install kernel header
    #local tmp_install_header=/tmp/install_headers
    #mkdir -p ${tmp_install_header}
    #cd ${TOP}/kernel
    #make headers_install ARCH=arm INSTALL_HDR_PATH=${tmp_install_header}
    #cd ${TOP}
    #local header_dir=${tmp_install_header}/include

    #local asm_arm_header_dir=${tmp_install_header}/include/asm
    local android_kernel_header=${TOP}/external/kernel-headers/original
    #cp -a ${asm_arm_header_dir}/* ${android_kernel_header}/asm-arm
    #cp -a ${header_dir}/asm-generic/* ${android_kernel_header}/asm-generic
    #cp -a ${header_dir}/linux/* ${android_kernel_header}/linux
    ##cp -a ${header_dir}/media/* ${android_kernel_header}/media
    #cp -a ${header_dir}/mtd/* ${android_kernel_header}/mtd
    #cp -a ${header_dir}/sound/* ${android_kernel_header}/sound
    ##cp -a ${header_dir}/uapi/* ${android_kernel_header}/uapi
    #cp -a ${header_dir}/video/* ${android_kernel_header}/video
    cp kernel/include/linux/ion.h ${android_kernel_header}/linux
    ${TOP}/bionic/libc/kernel/tools/update_all.py
}

function apply_kernel_ion_header()
{
    local kernel_ion_header=kernel/include/linux/ion.h
    local bionic_ion_header=bionic/libc/kernel/common/linux/ion.h
    local libion=system/core/libion/ion.c
    cp ${kernel_ion_header} ${bionic_ion_header}
    sed -i 's/heap_mask/heap_id_mask/g' ${libion}
}

function build_cts()
{
    make -j8 PRODUCT-aosp_${BOARD_NAME}-${BUILD_TAG} cts
}

function sign_system_private_app()
{
    java -jar out/host/linux-x86/framework/signapk.jar vendor/nexell/security/${BOARD_NAME}/platform.x509.pem vendor/nexell/security/${BOARD_NAME}/platform.pk8 out/target/product/${BOARD_NAME}/system/app/OTAUpdateCenter.apk /tmp/OTAUpdateCenter.apk
    mv /tmp/OTAUpdateCenter.apk out/target/product/${BOARD_NAME}/system/app/
    sync
}

function build_android()
{
    if [ ${BUILD_ALL} == "true" ] || [ ${BUILD_ANDROID} == "true" ]; then
        echo ""
        echo "=============================================="
        echo "build android"
        echo "=============================================="

        echo "key generation for ${BOARD_NAME}"
        [ ! -e  ${TOP}/vendor/nexell/security/${BOARD_NAME}/media.pk8 ] && ${TOP}/device/nexell/tools/mkkey.sh media ${BOARD_NAME}
        [ ! -e  ${TOP}/vendor/nexell/security/${BOARD_NAME}/platform.pk8 ] && $(${TOP}/device/nexell/tools/mkkey.sh platform ${BOARD_NAME})
        [ ! -e  ${TOP}/vendor/nexell/security/${BOARD_NAME}/release.pk8 ] && ${TOP}/device/nexell/tools/mkkey.sh release ${BOARD_NAME}
        [ ! -e  ${TOP}/vendor/nexell/security/${BOARD_NAME}/shared.pk8 ] && ${TOP}/device/nexell/tools/mkkey.sh shared ${BOARD_NAME}
        [ ! -e  ${TOP}/vendor/nexell/security/${BOARD_NAME}/testkey.pk8 ] && ${TOP}/device/nexell/tools/mkkey.sh testkey ${BOARD_NAME}

        patch_android

        apply_kernel_ion_header

        make -j8 PRODUCT-aosp_${BOARD_NAME}-${BUILD_TAG}
        check_result "build-android"

        make_android_root
        refine_android_system

        #sign_system_private_app

        #build_cts

        restore_patch

        echo "---------- End of build android"
    fi
}

function build_dist()
{
    if [ ${BUILD_DIST} == "true" ]; then
        echo ""
        echo "=============================================="
        echo "build dist"
        echo "=============================================="

        patch_android

        make -j8 PRODUCT-aosp_${BOARD_NAME}-${BUILD_TAG} dist

        cp ${TOP}/out/dist/aosp_${BOARD_NAME}-target_files-eng.$(whoami).zip ${RESULT_DIR}/${BOARD_NAME}-target_files.zip

        local tmpdir=${RESULT_DIR}/tmp
        rm -rf ${tmpdir}
        rm -f ${RESULT_DIR}/target.zip
        mkdir -p ${tmpdir}
        unzip -o -q ${RESULT_DIR}/${BOARD_NAME}-target_files.zip -d ${tmpdir}
        mkdir -p ${tmpdir}/BOOTABLE_IMAGES/
        local otaver=$(cat device/nexell/${BOARD_NAME}/otaver)
        otaver=$((otaver+1))
        sed -i "s/setprop otaupdater.otaver.*/setprop otaupdater.otaver ${otaver}/g" ${RESULT_DIR}/root/init.${BOARD_NAME}.rc
        local release_date=$(date +%Y%m%d-%H%M)
        sed -i "s/setprop otaupdater.otatime.*/setprop otaupdater.otatime ${release_date}/g" ${RESULT_DIR}/root/init.${BOARD_NAME}.rc
        ${TOP}/device/nexell/tools/mkinitramfs.sh ${RESULT_DIR}/root ${RESULT_DIR}
        cp ${RESULT_DIR}/root.img.gz ${RESULT_DIR}/boot
        cp ${RESULT_DIR}/root.img.gz ${TOP}/out/target/product/${BOARD_NAME}/ramdisk.img
        if [ ${ROOT_DEVICE_TYPE} != "nand" ]; then
            make_ext4 ${BOARD_NAME} boot
        fi
        cp ${RESULT_DIR}/boot.img ${tmpdir}/BOOTABLE_IMAGES
        cp out/target/product/${BOARD_NAME}/recovery.img ${tmpdir}/BOOTABLE_IMAGES
        if [ ${OTA_UPDATE_UBOOT} == "true" ] || [ ${OTA_UPDATE_2NDBOOT} == "true" ]; then
            mkdir -p ${tmpdir}/RADIO
            if [ ${OTA_UPDATE_2NDBOOT} == "true" ]; then
                cp device/nexell/${BOARD_NAME}/boot/2ndboot.bin ${tmpdir}/RADIO/2ndbootloader
            fi
            if [ ${OTA_UPDATE_UBOOT} == "true" ]; then
                cp ${RESULT_DIR}/u-boot.bin ${tmpdir}/RADIO/bootloader
            fi
        fi
        cd ${tmpdir}
        zip -r -q ../target *
        cd ${TOP}
        cp build/tools/releasetools/common.py /tmp/
        cp device/nexell/tools/common.py build/tools/releasetools/
        local ota_name="ota-${BOARD_NAME}-${release_date}.zip"
        local i_option=
        if [ ${OTA_INCREMENTAL} == "true" ]; then
            if [ -f ${OTA_PREVIOUS_FILE} ]; then
                local src_tmpdir=${RESULT_DIR}/src_tmp
                rm -rf ${src_tmpdir}
                rm -f ${RESULT_DIR}/src_target.zip
                mkdir -p ${src_tmpdir}
                unzip -o -q ${OTA_PREVIOUS_FILE} -d ${src_tmpdir}
                cp ${RESULT_DIR}/boot.img ${src_tmpdir}/BOOTABLE_IMAGES
                cd ${src_tmpdir}
                zip -r -q ../src_target *
                cd ${TOP}
                i_option="-i ${RESULT_DIR}/src_target.zip"
            fi
        fi
        echo "i_option ====> ${i_option}"
        build/tools/releasetools/ota_from_target_files -v -p out/host/linux-x86 -k vendor/nexell/security/${BOARD_NAME}/release ${i_option} ${RESULT_DIR}/target.zip ${RESULT_DIR}/${ota_name}
        mv /tmp/common.py build/tools/releasetools/

        #restore_patch

        local ota_desc=${RESULT_DIR}/OTA_DESC
        echo "Rom Name: aosp_${BOARD_NAME}-${BUILD_TAG} 4.4.2 KOT49H ${release_date}" > ${ota_desc}
        echo "Rom ID: nexell_pyrope_${BOARD_NAME}_kk" >> ${ota_desc}
        echo -e ${otaver} | awk '{print "Rom Version: " $1}' >> ${ota_desc}
        echo "Rom Date: ${release_date}" >> ${ota_desc}
        echo "Download URL: http://git.nexell.co.kr/_builds/${ota_name}" >> ${ota_desc}
        md5sum ${RESULT_DIR}/${ota_name} | awk '{print "MD5 Checksum: " $1}' >> ${ota_desc}
        echo "Device(code)name: ${BOARD_NAME}" >> ${ota_desc}

        echo -e ${otaver} > device/nexell/${BOARD_NAME}/otaver

        echo "---------- End of build dist"
    fi
}

function make_boot()
{
    vmsg "start make_boot"
    local out_dir="${TOP}/out/target/product/${BOARD_NAME}"

    mkdir -p ${RESULT_DIR}/boot

    cp ${TOP}/kernel/arch/arm/boot/uImage ${RESULT_DIR}/boot

    copy_bmp_files_to_boot ${BOARD_NAME}

    cp -a ${out_dir}/root ${RESULT_DIR}
    ${TOP}/device/nexell/tools/mkinitramfs.sh ${RESULT_DIR}/root ${RESULT_DIR}
    cp ${RESULT_DIR}/root.img.gz ${RESULT_DIR}/boot
    cp ${RESULT_DIR}/root.img.gz ${TOP}/out/target/product/${BOARD_NAME}/ramdisk.img

    if [ -f ${out_dir}/ramdisk-recovery.img ]; then
        cp ${out_dir}/ramdisk-recovery.img ${RESULT_DIR}/boot
    fi

    if [ ${ROOT_DEVICE_TYPE} != "nand" ]; then
        make_ext4 ${BOARD_NAME} boot
    fi
    vmsg "end make_boot"
}

function make_system()
{
    vmsg "start make_system"
    local out_dir="${TOP}/out/target/product/${BOARD_NAME}"
    cp -a ${out_dir}/system ${RESULT_DIR}

    apply_android_overlay
    #remove_android_banned_files

    if [ ${ROOT_DEVICE_TYPE} != "nand" ]; then
        #cp ${out_dir}/system.img ${RESULT_DIR}
        make_ext4 ${BOARD_NAME} system
    else
        make_ubi_image_for_nand ${BOARD_NAME} system
    fi
    vmsg "end make_system"
}

function make_cache()
{
    vmsg "start make_cache"
    local out_dir="${TOP}/out/target/product/${BOARD_NAME}"
    cp -a ${out_dir}/cache ${RESULT_DIR}
    if [ ${ROOT_DEVICE_TYPE} != "nand" ]; then
        cp ${out_dir}/cache.img ${RESULT_DIR}
    else
        make_ubi_image_for_nand ${BOARD_NAME} cache
    fi
    vmsg "end make_cache"
}

function make_userdata()
{
    vmsg "start make_userdata"
    local out_dir="${TOP}/out/target/product/${BOARD_NAME}"
    cp -a ${out_dir}/data ${RESULT_DIR}/userdata
    if [ ${ROOT_DEVICE_TYPE} != "nand" ]; then
        cp ${out_dir}/userdata.img ${RESULT_DIR}
    else
        make_ubi_image_for_nand ${BOARD_NAME} userdata
    fi
    vmsg "end make_userdata"
}

function post_process()
{
    if [ ${BUILD_DIST} == "false" ]; then
        echo ""
        echo "=============================================="
        echo "post processing"
        echo "=============================================="

        local out_dir="${TOP}/out/target/product/${BOARD_NAME}"
        echo ${out_dir}

        rm -rf ${RESULT_DIR}
        mkdir -p ${RESULT_DIR}

        cp ${TOP}/u-boot/u-boot.bin ${RESULT_DIR}

        if [ ${ROOT_DEVICE_TYPE} == "nand" ]; then
            query_nand_sizes ${BOARD_NAME}
        fi

        make_boot
        make_system
        make_cache
        make_userdata

        echo "---------- End of post processing"
    fi
}

check_top
source device/nexell/tools/common.sh

parse_args $@
print_args
export VERBOSE
set_android_toolchain_and_check
check_board_name ${BOARD_NAME}
check_wifi_device ${WIFI_DEVICE_NAME}
clean_up
build_uboot
build_kernel
build_module
build_android
post_process
build_dist
