#!/bin/bash

set -e

# export all working directory
# this can be changed
# pre-requisites: TOP must be defined in other place
function export_work_dir()
{
	BL1_DIR=${TOP}/device/nexell/bl1
	UBOOT_DIR=${TOP}/device/nexell/u-boot/u-boot-2016.01
	OPTEE_DIR=${TOP}/device/nexell/secure
	KERNEL_DIR=${TOP}/device/nexell/kernel/kernel-4.4.x

	export BL1_DIR UBOOT_DIR OPTEE_DIR KERNEL_DIR
}
