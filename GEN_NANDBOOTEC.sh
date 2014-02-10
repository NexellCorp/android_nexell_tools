#!/bin/bash

TOP=`pwd`

BOARD=

BINGEN="${TOP}/hardware/nexell/pyrope/tools/nand/GEN_NANDBOOTEC"
BOOT_DIR="${TOP}/hardware/nexell/pyrope/boot"
RESULT_DIR="${TOP}/result"
BOOTLOADER="u-boot.bin"
NSIH_FILE="${TOP}/hardware/nexell/pyrope/boot/NSIH.txt"
# Page Size  (MiB)
PAGE_SIZE=

# Address
LOAD_ADDR=0x40100000
JUMP_ADDR=0x40100000







function usage()
{
	echo "usage: `basename $0`"
	echo "  -b board name 			 	"
	echo "  -p page size (KiB)          "
}

function check_result()
{
    if [ $? -ne 0 ]
    then
        echo "  [Error] $1"
#		rm -f ${NAND_SECONDBOOT} ${NAND_BOOTLOADER}
    fi
}

function remove_tmps()
{
	rm -f PHASE1_FILE PHASE2_FILE
	rm -f ${TMP_BL}
}


while getopts 'h:b:p:' opt
do
	case $opt in
	b) BOARD=$OPTARG ;;
	p) PAGE_SIZE=$OPTARG ;;
	h | *)
		usage
		exit 1;;
		esac
done

# no input parameter
if [ -z "$BOARD" ]; then usage; exit 1; fi
if [ -z "$PAGE_SIZE" ]; then usage; exit 1; fi

NAND_SECONDBOOT=nand_2ndboot_${BOARD}.bin
NAND_BOOTLOADER=nand_bootloader_${BOARD}.bin

SECONDBOOT="${BOOT_DIR}/pyrope_2ndboot_NAND_${BOARD}.bin"

ORG_BL="${TOP}/u-boot/${BOOTLOADER}"
TMP_BL="${RESULT_DIR}/_${BOOTLOADER}"
OUT_NAND_2ND="${RESULT_DIR}/${NAND_SECONDBOOT}"
OUT_NAND_BL="${RESULT_DIR}/${NAND_BOOTLOADER}"

if [ ! -f ${SECONDBOOT} ]; then
	echo "Error: can't find 2ndboot file."
	exit 1
fi

if [ ! -f "${ORG_BL}" ]; then
	echo "Error: can't find ${BOOTLOADER} file."
	exit 1
fi



cp -f ${ORG_BL} ${TMP_BL}


echo "bulid ${SECONDBOOT} ..."
${BINGEN} -t 2ndboot -o ${OUT_NAND_2ND} -i ${SECONDBOOT} -n ${NSIH_FILE} -p ${PAGE_SIZE} -l ${LOAD_ADDR} -e ${JUMP_ADDR}
check_result "build 2ndboot for nand"

echo "bulid ${BOOTLOADER} ..."
${BINGEN} -t bootloader -o ${OUT_NAND_BL} -i ${TMP_BL} -n ${NSIH_FILE} -p ${PAGE_SIZE} -l ${LOAD_ADDR} -e ${JUMP_ADDR}
check_result "build bootloader for nand"

remove_tmps
