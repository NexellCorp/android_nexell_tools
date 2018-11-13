#!/bin/bash

# must be called at ANDROID_TOP directory
# ./device/nexell/tools/copy_dir.sh {SOURCE_BOARD} {TARGET_BOARD}
# ex>
# ./device/nexell/tools/copy_dir.sh avn_ref kick_st

set -e

SOURCE_BOARD_NAME=${1}
TARGET_BOARD_NAME=${2}

SOURCE_BOARD_DIR=
TARGET_BOARD_DIR=

function usage()
{
	echo "Usage: $0 <source-board-name> <target-board-name>"
}

function check_source_board()
{
	SOURCE_BOARD_DIR="device/nexell/${SOURCE_BOARD_NAME}"

	if [ ! -d ${SOURCE_BOARD_DIR} ]; then
		echo "Fail: ${SOURCE_BOARD_DIR} is not exist!!!"
		exit 1
	fi
}

function check_target_board()
{
	TARGET_BOARD_DIR="device/nexell/${TARGET_BOARD_NAME}"
}

# arguments
# $1: source dir
# $2: target dir
# $3: pattern
function copy_dir()
{
	local src_dir=${1}
	local dst_dir=${2}
	local pattern=${3}

	mkdir -p ${dst_dir}

	# echo "src_dir: ${src_dir}"
	# echo "dst_dir: ${dst_dir}"
	# echo "pattern: ${pattern}"

	for f in `ls ${src_dir}`
	do
		local s=`echo ${f} | sed -n "/${SOURCE_BOARD_NAME}/p"`
		if [ -z ${s} ]; then
			s=${f}
		else
			s=${s/${SOURCE_BOARD_NAME}/${TARGET_BOARD_NAME}}
		fi
		full_src_file="${src_dir}/${f}"
		full_dst_file="${dst_dir}/${s}"
		echo "${full_src_file} ====> ${full_dst_file}"
		if [ -d ${full_src_file} ]; then
			copy_dir ${full_src_file} ${full_dst_file} ${pattern}
		else
			# echo "sed -e '"${pattern}"' ${full_src_file} > ${full_dst_file}"
			sed -e "${pattern}" ${full_src_file} > ${full_dst_file}
		fi
	done
}

function copy_source_to_target()
{
	echo "==========================================================="
	echo "copy from ${SOURCE_BOARD_DIR} to ${TARGET_BOARD_DIR}"
	echo "==========================================================="

	local pattern="s/${SOURCE_BOARD_NAME}/${TARGET_BOARD_NAME}/g"
	copy_dir ${SOURCE_BOARD_DIR} ${TARGET_BOARD_DIR} ${pattern}
	chmod u+x ${TARGET_BOARD_DIR}/*.sh
}

check_source_board
check_target_board
copy_source_to_target
