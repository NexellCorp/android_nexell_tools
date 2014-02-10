
#!/bin/bash
# Copyright (C) 2013 <www.nexell.co.kr>
# Created. KOO Bon-Gyu <freestyle@nexell.co.kr>

TOP=$(pwd)
MTD_TOOL_PATH=$TOP/device/nexell/tools/mtd-utils
SCRIPT_PATH=$TOP/device/nexell/tools

RESULT_PATH=$TOP/result



# BOARD
BOARD=

# NAND
PAGE_SIZE=    			# Page Size  (Byte)
SUB_PAGE_SIZE=    		# SubPage Size  (Byte)
BLOCK_SIZE=    			# Block Size (KB)
TOTAL_BLOCK_SIZE=    	# Total flash size (MB)
RAW_DATA_SIZE=64  		# raw data (MB)

# ANDROID FS SIZE
FS_SYSTEM_SIZE=   		# system file system partition size (MB)
FS_CACHE_SIZE=   		# cache  file system partition size (MB)
FS_DATA_SIZE=			# data   file system partition size (MB)

SYSTEM_SRC_PATH=$TOP/result/system
USERDATA_SRC_PATH=$TOP/result/data
CACHE_SRC_PATH=$TOP/result/cache

SYSTEM_UBI_CFG=$SCRIPT_PATH/ubi_system.cfg
USERDATA_UBI_CFG=$SCRIPT_PATH/ubi_userdata.cfg
CACHE_UBI_CFG=$SCRIPT_PATH/ubi_cache.cfg


MK_DEBUG_MSG=n
 

#########################
# Get build options
#########################
function usage()
{
	echo "usage: `basename $0`"
	echo "  -b target board name					 					 	"
	echo "  -p page size (B)											 	"
	echo "  -s subpage size (default: equal to page size, B)				"
	echo "  -e block size (KiB)												"
	echo "  -l total block size (MiB)										"
	echo "  -w raw data size (default: 64, MiB)								"
	echo "  -y SYSTEM partition size (MiB)									"
	echo "  -i CACHE partition size (MiB)									"
	echo "  -o DATA partition size (MiB)									"
	echo "  -g print build message 									 	 	"
	#echo "  clean rm *.img											 	 	"
}

function Diaplay()
{
	echo "==============================================================="
	echo "   Board  [ $BOARD ]" 
	echo "==============================================================="
	echo ""
}

function success_cmd()
{
	echo "Done!"
	echo "Success"
	exit
}

function exit_cmd()
{
	echo "Failed"
	exit
}

function check_result()
{
    if [ $? -ne 0 ]
    then
        echo "  [Error] $1"
		exit_cmd
    fi
}


function tracing()
{
	if [ "y" = $MK_DEBUG_MSG ]; then
		echo "$@"
	fi
	eval "$@"
}

function make_image()
{
	
	echo "==============================================================="
	echo " Generate system image"
	echo "==============================================================="
	echo ""

	tracing "sudo $SCRIPT_PATH/mk_ubifs.sh -p $PAGE_SIZE -s $SUB_PAGE_SIZE -b $BLOCK_SIZE -l $FS_SYSTEM_SIZE \
		-r $SYSTEM_SRC_PATH     \
		-i $SYSTEM_UBI_CFG      \
		-c $RESULT_PATH         \
		-t $MTD_TOOL_PATH       \
		-f $TOTAL_BLOCK_SIZE    \
		-v system -n system.img"

	check_result "make system image"


	echo "==============================================================="
	echo " Generate userdata image"
	echo "==============================================================="
	echo ""

	tracing "sudo $SCRIPT_PATH/mk_ubifs.sh -p $PAGE_SIZE -s $SUB_PAGE_SIZE -b $BLOCK_SIZE -l $FS_DATA_SIZE \
		-r $USERDATA_SRC_PATH   \
		-i $USERDATA_UBI_CFG    \
		-c $RESULT_PATH         \
		-t $MTD_TOOL_PATH       \
		-f $TOTAL_BLOCK_SIZE    \
		-v data -n data.img"

	check_result "make data image"


	echo "==============================================================="
	echo " Generate cache image"
	echo "==============================================================="
	echo ""

	tracing "sudo $SCRIPT_PATH/mk_ubifs.sh -p $PAGE_SIZE -s $SUB_PAGE_SIZE -b $BLOCK_SIZE -l $FS_CACHE_SIZE \
		-r $CACHE_SRC_PATH      \
		-i $CACHE_UBI_CFG       \
		-c $RESULT_PATH         \
		-t $MTD_TOOL_PATH       \
		-f $TOTAL_BLOCK_SIZE    \
		-v cache -n cache.img"

	check_result "make cache image"

}



while getopts 'hb:p:s:e:l:w:y:i:og' opt
do
	case $opt in
	b) BOARD=$OPTARG ;;
	p) PAGE_SIZE=$OPTARG ;;
	s) SUB_PAGE_SIZE=$OPTARG ;;
	e) BLOCK_SIZE=$OPTARG ;;
	l) TOTAL_BLOCK_SIZE=$OPTARG ;;
	w) RAW_DATA_SIZE=$OPTARG ;;
	y) FS_SYSTEM_SIZE=$OPTARG ;;
	i) FS_CACHE_SIZE=$OPTARG ;;
	o) FS_DATA_SIZE=$OPTARG ;;
	g) MK_DEBUG_MSG=y ;;
	h | *)
		usage
		exit 1;;
		esac
done



# Argument Checking
if [ -z "$BOARD"            ];  then usage; exit 1; fi
if [ -z "$PAGE_SIZE"        ];  then usage; exit 1; fi
if [ -z "$SUB_PAGE_SIZE"    ];  then
	SUB_PAGE_SIZE=$PAGE_SIZE
fi
if [ -z "$BLOCK_SIZE"       ];  then usage; exit 1; fi
if [ -z "$TOTAL_BLOCK_SIZE" ];  then usage; exit 1; fi
if [ -z "$RAW_DATA_SIZE"    ];  then usage; exit 1; fi

if [ -z "$FS_SYSTEM_SIZE"   ];  then usage; exit 1; fi
if [ -z "$FS_CACHE_SIZE"    ];  then usage; exit 1; fi
if [ -z "$FS_DATA_SIZE"     ];  then
	FS_DATA_SIZE=`expr $TOTAL_BLOCK_SIZE "-" $RAW_DATA_SIZE "-" $FS_SYSTEM_SIZE "-" $FS_CACHE_SIZE`
fi




# BUILD
Diaplay;
echo "Gnerate android ubifs file, Please wait for some minutes..."

mkdir -p result/cache
check_result "make cache directory"

mkdir -p $TOP/out/target/product/$BOARD
check_result "make product directory"

cd $TOP/out/target/product/$BOARD
check_result "goto to product directory"


make_image;
check_result "make image failed"


success_cmd;
