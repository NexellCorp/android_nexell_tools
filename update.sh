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
BOARD_PURE_NAME=
CHIP_NAME=
ROOT_DEVICE_TYPE=
NSIH_FILE=
APPLY_KERNEL_INIT_RAMFS=false

ROOT_DEVICE_SIZE=

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
        BOARD_PURE_NAME=${BOARD_NAME%_*}
    fi

    vmsg "BOARD_NAME: ${BOARD_NAME}"
}

function is_sd_device()
{
    local f="$1"
    local tmp=$(cat $f | grep by-num | head -n1)
    if (( ${#tmp} > 0 )); then
        echo "true"
    else
        echo "false"
    fi
}

function is_nand_device()
{
    local f="$1"
    local tmp=$(cat $f | grep mio | head -n1)
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

function get_root_device_size()
{
    local command=
    if [ ${ROOT_DEVICE_TYPE%[0-9]} == "sd" ]; then
        command="capacity.mmc.${ROOT_DEVICE_TYPE##sd}"
    else
        command="capacity.nand"
    fi
    local result_file=/tmp/size.txt 
    echo "command : ${command}"
    sudo ${FASTBOOT} getvar ${command} 2> ${result_file}
    cat ${result_file}
    local failed=$(cat ${result_file} | grep FAILED | awk '{print $2}')
    if [ -z ${failed} ]; then
        local size=$(cat ${result_file} | grep capacity | awk '{print $2}')
        ROOT_DEVICE_SIZE=${size}
    else
        ROOT_DEVICE_SIZE=0
    fi
    rm -f ${result_file}
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
            #APPLY_KERNEL_INIT_RAMFS=true
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
    if [ ${ROOT_DEVICE_TYPE} == "nand" ]; then
        echo "flash=nand,0:bootrecovery:factory:0x2000000,0x2000000;" >> ${partmap_file}
        echo "flash=nand,0:bootloader:boot:0x4000000,0x2000000;" >> ${partmap_file}
        echo "flash=nand,0:boot:ext4:0x00100000,0x4000000;" >> ${partmap_file}
        echo "flash=nand,0:system:ext4:0x04100000,0x2F200000;" >> ${partmap_file}
        echo "flash=nand,0:cache:ext4:0x33300000,0x1AC00000;" >> ${partmap_file}
        echo "flash=nand,0:misc:emmc:0x4E000000,0x00800000;" >> ${partmap_file}
        echo "flash=nand,0:recovery:emmc:0x4E900000,0x01600000;" >> ${partmap_file}
        echo "flash=nand,0:userdata:ext4:0x50000000,0x0;" >> ${partmap_file}
    else
        local dev_num=${ROOT_DEVICE_TYPE#sd}
		echo "flash=eeprom,0:bootloader:boot:0x10000,0x70000;" >> ${partmap_file}
        echo "flash=mmc,${dev_num}:boot:ext4:0x00100000,0x04000000;" >> ${partmap_file}
        echo "flash=mmc,${dev_num}:system:ext4:0x04100000,0x28E00000;" >> ${partmap_file}
        echo "flash=mmc,${dev_num}:cache:ext4:0x2CF00000,0x21000000;" >> ${partmap_file}
        echo "flash=mmc,${dev_num}:misc:emmc:0x4E000000,0x00800000;" >> ${partmap_file}
        echo "flash=mmc,${dev_num}:recovery:emmc:0x4E900000,0x01600000;" >> ${partmap_file}
        echo "flash=mmc,${dev_num}:userdata:ext4:0x50000000,0x0;" >> ${partmap_file}
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
        local secondboot_dir=${TOP}/linux/platform/${CHIP_NAME}/boot/release/2ndboot
        local nsih_dir=${TOP}/linux/platform/${CHIP_NAME}/boot/release/nsih
        local secondboot_file=
        local nsih_file=
        local option_d="-d other"
        local option_p=
        local option_b=
        case ${BOOT_DEVICE_TYPE} in
            spirom)
                secondboot_file=${secondboot_dir}/2ndboot_${BOARD_PURE_NAME}_spi.bin
                nsih_file=${nsih_dir}/nsih_${BOARD_PURE_NAME}_spi.txt
                option_b="SPI"
                ;;
            sd0 | sd2)
                secondboot_file=${secondboot_dir}/2ndboot_${BOARD_PURE_NAME}_sdmmc.bin
                nsih_file=${nsih_dir}/nsih_${BOARD_PURE_NAME}_sdmmc.txt
                option_b="SD"
                ;;
            nand)
				local nand_sizes=$(get_nand_sizes_from_config_file ${BOARD_PURE_NAME})
				local page_size=$(echo ${nand_sizes} | awk '{print $1}')

                secondboot_file=${secondboot_dir}/2ndboot_${BOARD_PURE_NAME}_nand.bin
                nsih_file=${nsih_dir}/nsih_${BOARD_PURE_NAME}_nand.txt
                option_d="-d nand"
                option_p="-p ${page_size}"
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
        #${TOP}/linux/platform/${CHIP_NAME}/tools/bin/nx_bingen -t 2ndboot ${option_d} -o ${secondboot_out_file} -i ${secondboot_file} -n ${nsih_file} ${option_p}
        #${TOP}/linux/platform/${CHIP_NAME}/tools/bin/BOOT_BINGEN -c S5P4418 -t 2ndboot -b ${option_b} -n ${nsih_file} -i ${secondboot_file} -o ${secondboot_out_file} -d ffff0000 -l ffff0000
		if [ ${BOOT_DEVICE_TYPE} == "nand" ]; then
			${TOP}/linux/platform/${CHIP_NAME}/tools/bin/BOOT_BINGEN_NAND -c ${CHIP_NAME} -t 2ndboot -o ${secondboot_out_file} -i ${secondboot_file} -n ${nsih_file} ${option_p}
		else
			${TOP}/linux/platform/${CHIP_NAME}/tools/bin/BOOT_BINGEN -c ${CHIP_NAME} -t 2ndboot -o ${secondboot_out_file} -i ${secondboot_file} -n ${nsih_file} ${option_p}
		fi
        sync
        sleep 1
        echo "call fastboot"
        flash 2ndboot ${secondboot_out_file}
        NSIH_FILE=${nsih_file}

        mkdir -p ${TOP}/device/nexell/${BOARD_NAME}/boot
        cp ${secondboot_out_file} ${TOP}/device/nexell/${BOARD_NAME}/boot
    fi
}

# enable/disable functions for only boot device type
function enable_uboot_eeprom()
{
    local src_file=${TOP}/u-boot/include/configs/${CHIP_NAME}_${BOARD_PURE_NAME}.h
    sed -i 's/^\/\/#define CONFIG_CMD_EEPROM/#define CONFIG_CMD_EEPROM/g' ${src_file}
    sed -i 's/^\/\/#define CONFIG_SPI/#define CONFIG_SPI/g' ${src_file}
    sed -i 's/^\/\/#define CONFIG_ENV_IS_IN_EEPROM/#define CONFIG_ENV_IS_IN_EEPROM/g' ${src_file}
}

function disable_uboot_eeprom()
{
    local src_file=${TOP}/u-boot/include/configs/${CHIP_NAME}_${BOARD_PURE_NAME}.h
    sed -i 's/^#define CONFIG_CMD_EEPROM/\/\/#define CONFIG_CMD_EEPROM/g' ${src_file}
    sed -i 's/^#define CONFIG_SPI/\/\/#define CONFIG_SPI/g' ${src_file}
    sed -i 's/^#define CONFIG_ENV_IS_IN_EEPROM/\/\/#define CONFIG_ENV_IS_IN_EEPROM/g' ${src_file}
}

function enable_uboot_nand_env()
{
    local src_file=${TOP}/u-boot/include/configs/${CHIP_NAME}_${BOARD_PURE_NAME}.h
    sed -i 's/^\/\/#define CONFIG_ENV_IS_IN_NAND/#define CONFIG_ENV_IS_IN_NAND/g' ${src_file}
}

function disable_uboot_nand_env()
{
    local src_file=${TOP}/u-boot/include/configs/${CHIP_NAME}_${BOARD_PURE_NAME}.h
    sed -i 's/^#define CONFIG_ENV_IS_IN_NAND/\/\/#define CONFIG_ENV_IS_IN_NAND/g' ${src_file}
}

function enable_uboot_mmc_env()
{
    local src_file=${TOP}/u-boot/include/configs/${CHIP_NAME}_${BOARD_PURE_NAME}.h
    sed -i 's/^\/\/#define CONFIG_ENV_IS_IN_MMC/#define CONFIG_ENV_IS_IN_MMC/g' ${src_file}
}

function disable_uboot_mmc_env()
{
    local src_file=${TOP}/u-boot/include/configs/${CHIP_NAME}_${BOARD_PURE_NAME}.h
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
	# nand:devel)    SDFAT on SVT
    disable_uboot_eeprom
    #disable_uboot_nand_env
    #disable_uboot_mmc_env

	# nand:release)  EEPROM
	#enable_uboot_eeprom
    #disable_uboot_nand_env
    #disable_uboot_mmc_env
}

function update_bootloader()
{
    if [ ${UPDATE_UBOOT} == "true" ] || [ ${UPDATE_ALL} == "true" ]; then

        # check bootdevice env save location
        local src_file=${TOP}/u-boot/include/configs/${CHIP_NAME}_${BOARD_PURE_NAME}.h
        local backup_file=/tmp/${CHIP_NAME}_${BOARD_PURE_NAME}.h
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
            local nand_sizes=$(get_nand_sizes_from_config_file ${BOARD_PURE_NAME})
            local page_size=$(echo ${nand_sizes} | awk '{print $1}')

            ${TOP}/linux/platform/${CHIP_NAME}/tools/bin/nx_bingen -t bootloader -d nand -o ${RESULT_DIR}/u-boot.ecc -i ${RESULT_DIR}/u-boot.bin -n ${NSIH_FILE} -p ${page_size}
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
			make_ext4 ${BOARD_NAME} boot
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
            make_ext4 ${BOARD_NAME} boot
        fi

        if [ ! -f ${RESULT_DIR}/boot/uImage ]; then
            echo "Error: can't find uImage check build!!!"
            exit 1
        fi

            update_boot 1
    fi
}

function update_rootfs()
{
    if [ ${UPDATE_ROOTFS} == "true" ] || [ ${UPDATE_ALL} == "true" ]; then
        if [ ${UPDATE_ROOTFS} == "true" ]; then
            ${TOP}/device/nexell/tools/mkinitramfs.sh ${RESULT_DIR}/root ${RESULT_DIR}

            cp ${RESULT_DIR}/root.img.gz ${RESULT_DIR}/boot

            if [ ! -f ${RESULT_DIR}/boot/root.img.gz ]; then
                echo "Error: can't find root.img.gz check build!!!"
                exit 1
            fi

			make_ext4 ${BOARD_NAME} boot
        fi


            update_boot 1
    fi
}

function update_bmp()
{
    if [ ${UPDATE_BMP} == "true" ] || [ ${UPDATE_ALL} == "true" ]; then
        if [ ${UPDATE_BMP} == "true" ]; then
            copy_bmp_files_to_boot

			make_ext4 ${BOARD_NAME} boot
        fi

		update_boot 1
    fi
}

function update_system()
{
    if [ ${UPDATE_SYSTEM} == "true" ] || [ ${UPDATE_ALL} == "true" ]; then
        if [ ${UPDATE_SYSTEM} == "true" ]; then
			make_ext4 ${BOARD_NAME} system
        fi

        flash system ${RESULT_DIR}/system.img
    fi
}

function update_cache()
{
    if [ ${UPDATE_CACHE} == "true" ] || [ ${UPDATE_ALL} == "true" ]; then
        if [ ${UPDATE_CACHE} == "true" ]; then
			make_ext4 ${BOARD_NAME} cache
        fi

        flash cache ${RESULT_DIR}/cache.img
    fi
}

function recalc_userdata_size()
{
    local boot_size=$(get_partition_size ${BOARD_NAME} boot)
    local system_size=$(get_partition_size ${BOARD_NAME} system)
    local cache_size=$(get_partition_size ${BOARD_NAME} cache)
    local misc_size=0x800000
    local recovery_size=0x1600000
    local extpartinfo_size=0x300000
    local user_data_size=$((ROOT_DEVICE_SIZE - boot_size - system_size - cache_size - misc_size - recovery_size - extpartinfo_size - (1024*1024)))
    echo -n "${user_data_size}"
}

function update_userdata()
{
    if [ ${UPDATE_USERDATA} == "true" ] || [ ${UPDATE_ALL} == "true" ]; then
        local user_data_size=$(recalc_userdata_size)
		make_ext4 ${BOARD_NAME} userdata ${user_data_size}

        flash userdata ${RESULT_DIR}/userdata.img
    fi
}

#check_top
source device/nexell/tools/common.sh

parse_args $@
#export VERBOSE

#check_fastboot
#check_target_device
check_boot_device_type
get_board_name
CHIP_NAME=$(get_cpu_variant2 ${BOARD_NAME})
get_root_device
get_root_device_size

update_partitionmap
#nand: release)
#update_2ndboot
#update_bootloader
change_fstab_for_sd

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
