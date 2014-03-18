#!/bin/bash

set -e

TOP=$(pwd)
FASTBOOT=${TOP}/device/nexell/tools/fastboot
RESULT_DIR=${TOP}/result
export TOP RESULT_DIR

# user option
BOOT_DEVICE_TYPE=
PARTMAP="nofile"
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
NSIH_FILE=
APPLY_KERNEL_INIT_RAMFS=false

function check_top()
{
    if [ ! -d ${TOP}/.repo ]; then
        echo "You must execute this script at ANDROID TOP Directory"
        exit 1
    fi
}

function usage()
{
    echo "Usage: $0 -d <boot device type> [-p partmap -t 2ndboot -t u-boot -t kernel -t rootfs -t bmp -t boot -t system -t userdata -t cache -v]"
    echo -e '\n -d <boot device type> : your main boot device type(spirom, sd0, sd2, nand)'
    echo " -p partmap   : specify fastboot partmap file (if not specified, use device/nexell/tools/partmap/*)"
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
            -p ) PARTMAP=$2; shift 2 ;;
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
        sd2) ;;
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

function get_root_device()
{
    local fstab=${RESULT_DIR}/root/fstab.${BOARD_NAME}
    if [ ! -f ${fstab} ]; then
        echo "Error: can't find ${fstab} file... You must build before packaging"
        exit 1
    fi

    local is_sd=$(is_sd_device ${fstab})
    if [ ${is_sd} == "true" ]; then
        ROOT_DEVICE_TYPE="sd$(get_sd_device_number ${fstab})"
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

function get_sd_boot_device_number()
{
     echo ${BOOT_DEVICE_TYPE##sd}
}

function change_fstab_for_sd()
{
    if [ ${BOOT_DEVICE_TYPE%%[0-9]} == "sd" ]; then
        local src_file=${RESULT_DIR}/root/fstab.${BOARD_NAME}
        local fstab=${TOP}/device/nexell/${BOARD_NAME}/fstab.${BOARD_NAME}
        local sd_boot_device_num=$(get_sd_boot_device_number)
        local sd_root_device_num=$(get_sd_device_number ${fstab})
        if [ "tmp${sd_boot_device_num}" != "tmp${sd_root_device_num}" ]; then
            echo "change fstab root device : ${sd_root_device_num} --> ${sd_boot_device_num}"
            sed -i 's/dw_mmc.'"${sd_root_device_num}"'/dw_mmc.'"${sd_boot_device_num}"'/g' ${src_file}
            APPLY_KERNEL_INIT_RAMFS=true
        fi
    fi
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

function create_partmap_for_spirom()
{
    local partmap_file=${RESULT_DIR}/partmap.txt
    if [ -f ${partmap_file} ]; then
        rm -f ${partmap_file}
    fi

    echo "flash=eeprom,0:2ndboot:2nd:0x0,0x4000;" > ${partmap_file}
    echo "flash=eeprom,0:bootloader:boot:0x10000,0x70000;" >> ${partmap_file}
    if [ ${ROOT_DEVICE_TYPE} == "nand" ]; then
        echo "flash=nand,0:kernel:raw:0xc00000,0x600000;" >> ${partmap_file}
        echo "flash=nand,0:bootlogo:raw:0x2000000,0x400000;" >> ${partmap_file}
        echo "flash=nand,0:battery:raw:0x2800000,0x400000;" >> ${partmap_file}
        echo "flash=nand,0:update:raw:0x3000000,0x400000;" >> ${partmap_file}
        echo "flash=nand,0:system:ubi:0x4000000,0x20000000;" >> ${partmap_file}
        echo "flash=nand,0:cache:ubi:0x24000000,0x10000000;" >> ${partmap_file}
        echo "flash=nand,0:userdata:ubi:0x34000000,0x0;" >> ${partmap_file}
    else
        local dev_num=${ROOT_DEVICE_TYPE#sd}
        echo "flash=mmc,${dev_num}:boot:ext4:0x000100000,0x004000000;" >> ${partmap_file}
        echo "flash=mmc,${dev_num}:system:ext4:0x004100000,0x028E00000;" >> ${partmap_file}
        echo "flash=mmc,${dev_num}:cache:ext4:0x02CF00000,0x21000000;" >> ${partmap_file}
        echo "flash=mmc,${dev_num}:userdata:ext4:0x4df00000,0x0;" >> ${partmap_file}
    fi
}

function update_partitionmap()
{
    local partmap_file=
    if [ ${PARTMAP} == "nofile" ]; then
        if [ -f ${TOP}/device/nexell/${BOARD_NAME}/partmap.txt ]; then
            partmap_file=${TOP}/device/nexell/${BOARD_NAME}/partmap.txt
        else
            if [ ${BOOT_DEVICE_TYPE} == "spirom" ]; then
                create_partmap_for_spirom
                partmap_file=${RESULT_DIR}/partmap.txt
            else
                partmap_file=${TOP}/device/nexell/tools/partmap/partmap_${BOOT_DEVICE_TYPE}.txt
            fi
        fi
    else
        partmap_file=${PARTMAP}
    fi
    if [ ! -f ${partmap_file} ]; then
        echo "can't find partmap file: ${partmap_file}!!!"
        exit -1
    fi
    flash partmap ${partmap_file}
}

function update_2ndboot()
{
    if [ ${UPDATE_2NDBOOT} == "true" ] || [ ${UPDATE_ALL} == "true" ]; then
        local secondboot_dir=${TOP}/linux/pyrope/boot/2ndboot
        local nsih_dir=${TOP}/linux/pyrope/boot/nsih
        local secondboot_file=
        local nsih_file=
        local option_d=other
        local option_p=
        case ${BOOT_DEVICE_TYPE} in
            spirom) 
                secondboot_file=${secondboot_dir}/pyrope_2ndboot_${BOARD_NAME}_spi.bin
                nsih_file=${nsih_dir}/nsih_${BOARD_NAME}_spi.txt
                ;;
            sd0 | sd2)
                secondboot_file=${secondboot_dir}/pyrope_2ndboot_${BOARD_NAME}_sdmmc.bin
                nsih_file=${nsih_dir}/nsih_${BOARD_NAME}_sdmmc.txt
                ;;
            nand)
                secondboot_file=${secondboot_dir}/pyrope_2ndboot_${BOARD_NAME}_nand.bin
                nsih_file=${nsih_dir}/nsih_${BOARD_NAME}_nand.txt
                option_d=nand
                option_p="-p 8192"
                ;;
        esac

        if [ ! -f ${secondboot_file} ]; then
            echo "can't find secondboot file: ${secondboot_file}!, check ${secondboot_dir}"
            exit -1
        fi

        if [ ! -f ${nsih_file} ]; then
            echo "can't find nsih file: ${nsih_file}!, check ${nsih_dir}"
            exit -1
        fi

        local secondboot_out_file=$RESULT_DIR/2ndboot.bin

        vmsg "update 2ndboot: ${secondboot_file}"
        ${TOP}/linux/pyrope/tools/bin/nx_bingen -t 2ndboot -d ${option_d} -o ${secondboot_out_file} -i ${secondboot_file} -n ${nsih_file} -l 0x40100000 -e 0x40100000 ${option_p}
        flash 2ndboot ${secondboot_out_file}
        #flash 2ndboot ${TOP}/linux/pyrope/boot/2ndboot/2ndboot.ecc
        NSIH_FILE=${nsih_file}
    fi
}

# enable/disable functions for only boot device type
function enable_uboot_eeprom()
{
    local src_file=${TOP}/u-boot/include/configs/nxp4330q_${BOARD_NAME}.h
    sed -i 's/^\/\/#define CONFIG_CMD_EEPROM/#define CONFIG_CMD_EEPROM/g' ${src_file}
    sed -i 's/^\/\/#define CONFIG_SPI/#define CONFIG_SPI/g' ${src_file}
    sed -i 's/^\/\/#define CONFIG_ENV_IS_IN_EEPROM/#define CONFIG_ENV_IS_IN_EEPROM/g' ${src_file}
}

function disable_uboot_eeprom()
{
    local src_file=${TOP}/u-boot/include/configs/nxp4330q_${BOARD_NAME}.h
    sed -i 's/^#define CONFIG_CMD_EEPROM/\/\/#define CONFIG_CMD_EEPROM/g' ${src_file}
    sed -i 's/^#define CONFIG_SPI/\/\/#define CONFIG_SPI/g' ${src_file}
    sed -i 's/^#define CONFIG_ENV_IS_IN_EEPROM/\/\/#define CONFIG_ENV_IS_IN_EEPROM/g' ${src_file}
}

function enable_uboot_nand_env()
{
    local src_file=${TOP}/u-boot/include/configs/nxp4330q_${BOARD_NAME}.h
    sed -i 's/^\/\/#define CONFIG_ENV_IS_IN_NAND/#define CONFIG_ENV_IS_IN_NAND/g' ${src_file}
}

function disable_uboot_nand_env()
{
    local src_file=${TOP}/u-boot/include/configs/nxp4330q_${BOARD_NAME}.h
    sed -i 's/^#define CONFIG_ENV_IS_IN_NAND/\/\/#define CONFIG_ENV_IS_IN_NAND/g' ${src_file}
}

function enable_uboot_mmc_env()
{
    local src_file=${TOP}/u-boot/include/configs/nxp4330q_${BOARD_NAME}.h
    sed -i 's/^\/\/#define CONFIG_ENV_IS_IN_MMC/#define CONFIG_ENV_IS_IN_MMC/g' ${src_file}
}

function disable_uboot_mmc_env()
{
    local src_file=${TOP}/u-boot/include/configs/nxp4330q_${BOARD_NAME}.h
    sed -i 's/^#define CONFIG_ENV_IS_IN_MMC/\/\/#define CONFIG_ENV_IS_IN_MMC/g' ${src_file}
}

function apply_uboot_eeprom_config()
{
    enable_uboot_eeprom
    disable_uboot_nand_env
    disable_uboot_mmc_env
}

function apply_uboot_sd_config()
{
    disable_uboot_eeprom
    disable_uboot_nand_env
    enable_uboot_mmc_env
}

function apply_uboot_nand_config()
{
    disable_uboot_eeprom
    enable_uboot_nand_env
    disable_uboot_mmc_env
}

function update_bootloader()
{
    if [ ${UPDATE_UBOOT} == "true" ] || [ ${UPDATE_ALL} == "true" ]; then

        # check bootdevice env save location
        local src_file=${TOP}/u-boot/include/configs/nxp4330q_${BOARD_NAME}.h
        local backup_file=/tmp/nxp4330q_${BOARD_NAME}.h
        cp ${src_file} ${backup_file}
        case ${BOOT_DEVICE_TYPE} in
            spirom) apply_uboot_eeprom_config ;;
            sd0 | sd2) apply_uboot_sd_config ;;
            nand) apply_uboot_nand_config ;;
        esac
        local diff_result="$(diff -urN ${src_file} ${backup_file})"
        if [[ ${#diff_result} > 0 ]]; then
            echo ${src_file} is modified!!! rebuild
            cd ${TOP}/u-boot
            make -j8
            cd ${TOP}
            cp ${TOP}/u-boot/u-boot.bin ${RESULT_DIR}
        fi

        if [ ${UPDATE_UBOOT} == "true" ]; then
            cp ${TOP}/u-boot/u-boot.bin ${RESULT_DIR}
        fi

        if [ ! -f ${RESULT_DIR}/u-boot.bin ]; then
            echo "Error: can't find u-boot.bin... check build!!!"
            exit 1
        fi

        if [ ${BOOT_DEVICE_TYPE} == "nand" ]; then
            local nand_sizes=$(get_nand_sizes_from_config_file ${BOARD_NAME})
            local page_size=$(echo ${nand_sizes} | awk '{print $1}')

            ${TOP}/linux/pyrope/tools/bin/nx_bingen -t bootloader -d nand -o ${RESULT_DIR}/u-boot.ecc -i ${RESULT_DIR}/u-boot.bin -n ${NSIH_FILE} -p ${page_size}
            vmsg "update bootloader: ${RESULT_DIR}/u-boot.ecc"
            flash bootloader ${RESULT_DIR}/u-boot.ecc
        else
            vmsg "update bootloader: ${RESULT_DIR}/u-boot.bin"
            flash bootloader ${RESULT_DIR}/u-boot.bin
        fi
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
            #${TOP}/device/nexell/tools/mkramdisk.sh root 2
            #mv root.img.gz ${RESULT_DIR}/boot
            #cd ${TOP}

            if [ ${ROOT_DEVICE_TYPE} != "nand" ]; then
                make_ext4 ${BOARD_NAME} boot
            fi
        fi

        #if [ ! -f ${RESULT_DIR}/boot/root.img.gz ]; then
            #echo "Error: can't find root.img.gz check build!!!"
            #exit 1
        #fi

        if [ ${ROOT_DEVICE_TYPE} != "nand" ]; then
            update_boot 1
        #else
            #flash ramdisk ${RESULT_DIR}/boot/root.img.gz
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

#check_fastboot
#check_target_device
check_boot_device_type
get_board_name
get_root_device
update_partitionmap
update_2ndboot
update_bootloader
change_fstab_for_sd
if [ ${UPDATE_KERNEL} == "true" ] || [ ${APPLY_KERNEL_INIT_RAMFS} == "true" ]; then
    apply_kernel_initramfs
fi
if [ ${BOOT_DEVICE_TYPE} == "nand" ]; then
    update_kernel
    update_bmp
else
    if [ ${UPDATE_BOOT} == "false" ] && [ ${UPDATE_ALL} == "false" ]; then
        update_kernel
        update_rootfs
        update_bmp
    else
        update_boot
    fi
fi
update_system
update_cache
update_userdata

restart_board
