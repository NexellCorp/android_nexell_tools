#!/bin/bash
#
# build file systems

# command-line settable variables

FS_ROOT_PATH=
FS_COPY_PATH=./
FS_MAKE_DEVNODE=n
MKDEV_EXT_SH_PATH=
MK_DEBUG_MSG=n

# UBIFS Parameters
FS_NAME=ubi.img

FS_EXEC_PATH=

PAGE_SIZE=8192
SUB_PAGE_SIZE=$PAGE_SIZE
PHYS_BL_SIZE=1024				# KiB
FS_SIZE=4096					# MiB
TOTAL_CHIP_SIZE=4096			# MiB

UFS_VOLUME_NAME=
UFS_INI_PATH=./ubi.ini
UFS_BUILD_IMAGE=y
UFS_COMPRESS_TYPE=lzo

#########################
# Get build options
#########################
function usage()
{
	echo "usage: `basename $0`"
	echo "  -r rootfs path to build ubi image		 					 	"
	echo "  -c copy to directory (default .)		 					 	"
	echo "  -n ubi image name  (default fs.ubi.img/ubi.img)				 	"
	echo "  -v ubi volume name  (default root)					 	 	 	"
	echo "  -d build device node (default no)	 						 	"
	echo "  -e set external mknode shell path	 						 	"
	echo "  -t ubifs(mkfs.ubifs, ubinize) tools path 					 	"
	echo "  -i path ubi.ini to build ubi image (ubinize)				 	"
	echo "  -p page size (B)											 	"
	echo "  -s subpage size (special flash, B)							 	"
	echo "  -b physical block size (KiB)									"
	echo "  -l ubifs image size on nand flash (MiB)							"
	echo "  -f nand flash chip size (MiB)									"
	echo "  -z ubifs compress format  (lzo, favor_lzo, zlib, default lzo) 	"
	echo "  -u skip build ubi image (ubinize) 							 	"
	echo "  -g print build message 									 	 	"
	echo "  clean rm *.img											 	 	"
}

while getopts 'hr:c:n:de:t:i:p:s:b:l:f:z:v:ug' opt
do
	case $opt in
	r) FS_ROOT_PATH=$OPTARG ;;
	c) FS_COPY_PATH=$OPTARG ;;
	n) FS_NAME=$OPTARG ;;
	d) FS_MAKE_DEVNODE=y ;;
	e) MKDEV_EXT_SH_PATH=$OPTARG ;;
	t) FS_EXEC_PATH=$OPTARG ;;
	p) PAGE_SIZE=$OPTARG ;;
	s) SUB_PAGE_SIZE=$OPTARG ;;
	b) PHYS_BL_SIZE=$OPTARG ;;
	l) FS_SIZE=$OPTARG ;;
	f) TOTAL_CHIP_SIZE=$OPTARG ;;
	i) UFS_INI_PATH=$OPTARG ;;
	z) UFS_COMPRESS_TYPE=$OPTARG ;;
	v) UFS_VOLUME_NAME=$OPTARG ;;
	u) UFS_BUILD_IMAGE=n ;;
	g) MK_DEBUG_MSG=y ;;
	h | *)
		usage
		exit 1;;
		esac
done

# no input parameter
if [ -z "$1" ]; then usage; exit 1; fi

# clean
if [ "clean" = "$1" ]; then
	echo "make clean, rm *.img"
	rm -f *.img
	exit 1;
fi

#################################################################
# functions
#################################################################

#
# get sudo permission
#
# return "sudo"
#
function sudo_permission()
{
	_user_=$(id | sed 's/^uid=//;s/(.*$//')
    if [ 0 != $_user_ ]; then
    	echo " Require root permission"
        _sudo_=$1
        eval "$_sudo_='sudo'"	# return sudo
        # test
        sudo losetup -a >> /dev/null
	fi
}

#
# check rootfs path's permission
#
# input parameters
# $1	= path
#
# return
# - exit when not write permission
#
function check_permission_w()
{
	path=$1
	if [ -z $path ] || [ ! -d $path ]; then
		echo ""
		echo -e " - check path: $path ...."
		exit 1;
	fi

	if [ ! -w "$path" ]; then
		echo ""
		echo -e " You do not have write permission"
		echo -e " Check permission: '$path'"
		exit 1;
	fi
}

#
# make device node files
#
# input parameters
# $1	= device path
# $2 	= mknode shell path when use external shell
#
function build_mkdev()
{
	root_path=$1
	ext_mk_sh=$2

	if [ -n "$ext_mk_sh" ];
	then
		# use external shell program
		#
		if [ -x "$ext_mk_sh" ]; then
			$ext_mk_sh $root_path
			echo -e "\t[Done]"
		else
			echo ""
			echo -e " - check mknode shell: $MKDEV_EXT_SH_PATH ...."
		fi
	else
		echo ""
		echo -n " [ Make Device Node: '$root_path'..."
		###
		# make device nodes in /dev
		###
		dev_dir=$root_path/dev
		check_permission_w $root_path
		sudo_permission _SUDO_

		# miscellaneous one-of-a-kind stuff
		[ ! -c $dev_dir/console   ] && $_SUDO_ mknod 	$dev_dir/console 	c 5 1;
		[ ! -c "$dev_dir/full"    ] && $_SUDO_ mknod 	$dev_dir/full 		c 1 7;
		[ ! -c "$dev_dir/kmem"    ] && $_SUDO_ mknod 	$dev_dir/kmem 		c 1 2;
		[ ! -c "$dev_dir/mem"     ] && $_SUDO_ mknod 	$dev_dir/mem 		c 1 1;
		[ ! -c "$dev_dir/null"    ] && $_SUDO_ mknod 	$dev_dir/null 		c 1 3;
		[ ! -c "$dev_dir/port"    ] && $_SUDO_ mknod 	$dev_dir/port 		c 1 4;
		[ ! -c "$dev_dir/random"  ] && $_SUDO_ mknod 	$dev_dir/random 	c 1 8;
		[ ! -c "$dev_dir/urandom" ] && $_SUDO_ mknod  	$dev_dir/urandom 	c 1 9;
		[ ! -c "$dev_dir/zero"    ] && $_SUDO_ mknod  	$dev_dir/zero 		c 1 5;
		[ ! -c "$dev_dir/tty"     ] && $_SUDO_ mknod 	$dev_dir/tty 		c 5 0
		[ ! -h "$dev_dir/core"    ] && ln -s /proc/kcore	$dev_dir/core;

		# loop devs
		for i in `seq 0 7`; do
			[ ! -b "$dev_dir/loop$i" ] && $_SUDO_ mknod $dev_dir/loop$i 	b 7 $i;
		done

		# ram devs
		for i in `seq 0 9`; do
			[ ! -b "$dev_dir/ram$i" ] && $_SUDO_ mknod $dev_dir/ram$i 	b 1 $i
		done

		# ttys
		for i in `seq 0 9`; do
			[ ! -c "$dev_dir/tty$i" ] && $_SUDO_ mknod $dev_dir/tty$i 	c 4 $i
		done
		echo -e "\t Done]"
	fi
}

#
# make ubifs
#
# input parameters
# $1	= rootfs path
# $2	= ubifs build name (default fs.ubi.img/ubi.img)
# $3	= page size (Byte)
# $4	= sub page size (Byte)
# $5	= erase block size (KByte)
# $6	= file system size on nand (MByte)
# $7	= ubi.ini path
# $8 	= build ubi raw image (ubinize)
# $9 	= ubifs compress type

function build_ubifs()
{
	root_path=$1
	mkfs_name=$2
 	page_size=$3
 	subs_size=$4
 	bl_length=$5
 	fs_length=$6
 	conf_path=$7
 	mkubinize=$8
 	comp_type=$9
	flash_size=${10}

	# check root path
	if [ ! -d $root_path ] || [ -z $root_path ]; then
		echo -e " - check root path: $path ...."
		exit 1;
	fi

	# check ubi config path
	if [ -d $conf_path ] || [ -z $root_path ] || [ ! -r $conf_path ]; then
		echo -e " check path ubi config at $conf_path"
		exit 1;
	fi

	# check compression type
	if [ $comp_type != "lzo" ] && [ $comp_type != "favor_lzo" ] && [ $comp_type != "zlib" ]; then
		echo -e " not support compression type $comp_type"
		exit 1;
	fi

	# set fs name
	[ -z $mkfs_name ] && mkfs_name=ubi.img;
	ubi_fs_name=fs.$mkfs_name
	ubi_bi_name=$mkfs_name
	ubi_vo_name=$UFS_VOLUME_NAME

	# check mkfs.ubifs capability
	if [ "y" = $mkubinize ]; then
		$EXEC_MKUBIFS --h | grep -q "space-fixup"
		if [ $? -eq 1 ]; then
			echo    ""
			echo -e " $EXEC_MKUBIFS not support option "-F" for space-fixup ..."
			exit 1;
		fi
	fi

	# Calcurate UBI varialbe
	# Refer to http://processors.wiki.ti.com/index.php/UBIFS_Support
	#
	phys_bl_size=$(( $bl_length*1024 ))				# KiB
	fsys_bl_size=$(( $fs_length*1024*1024 ))		# MiB
	flash_bl_cnt=$(( ($flash_size * 1024*1024) / $phys_bl_size ))	# Flash erase block count

	PEB=$(( $phys_bl_size ))						# PEB (Physical Erase Block) Size (SP)
	LEB=$(( $phys_bl_size-(2*$page_size) )) 		# LEB (Logical Erase Block) Size (SL)
	TPB=$(( $fsys_bl_size/$phys_bl_size ))			# Total number of PEBs on the MTD device  (P)
#	RPB=$(( 20 * $TPB/1024 ))						# Number of PEBs reserved for bad PEB handling (20/1024) (B, but if flash has bad more than this...)
	RPB=$(( 20 * ${flash_bl_cnt}/1024 ))			# Number of PEBs reserved for bad PEB handling (20/1024)
	RPC=$(( $PEB-$LEB ))							# The overhead related to storing EC and VID headers in bytes (P)

	# UBI overhead
	OVH=$(( (($RPB+4)*$PEB)+($RPC*($TPB-$RPB-4)) )) # UBI overhead Size
	OVB=$(( $OVH/$PEB ))							# UBI overhead PEBs
	AVL=$(( $fsys_bl_size - $OVH ))					# Available Size ( ubi.cfg : vol_size )

	leb_size=$LEB
	bl_count=$(( $AVL / $leb_size ))				# maximum fs size
	volsize=$(( $AVL/1024/1024 ))					# Available Volume Size (MiB)

	# macro
	_KIB_=KiB
	_MIB_=MiB


	# set ubi.ini
	sed  -i "s|image\=.*|image=$ubi_fs_name|g" $conf_path;
	sed  -i "s|vol_size\=.*|vol_size=$volsize$_MIB_|g" $conf_path;
	[ ! -z $ubi_vo_name ] && sed  -i "s|vol_name\=.*|vol_name=$ubi_vo_name|g" $conf_path;
	ubi_vo_name=`cat $conf_path | grep -w vol_name | cut -d'=' -f2`

	echo ""
	echo -e " Make ubifs "
	echo " root from           = $root_path"
	echo " disk name           = $ubi_fs_name, $ubi_bi_name"
	echo " copy to             = $FS_COPY_PATH"
	echo " ubi config          = $conf_path"
	echo " compression type    = $comp_type"
	echo " page size           = $page_size"
	echo " physical block size = $bl_length KiB"
	echo " logical block size  = $leb_size "
	echo " logical block count = $bl_count "
	echo " ubi overhead PEBs   = $OVB ($TPB)"
	echo " ubi config          = $conf_path"
	echo " ubi reserved  size  = $(( $OVH/1024/1024 )) MiB"
	echo " ubi volume    size  = $volsize MiB"
	echo " ubi volume    name  = $ubi_vo_name"

	# build ubifs image
	[ "y" = $MK_DEBUG_MSG ] && UBIFS_VERBOSE=-v;

	$EXEC_MKUBIFS -r $root_path -o $ubi_fs_name	\
			-m $page_size 						\
			-e $leb_size 						\
			-c $bl_count						\
			-F									\
			$UBIFS_VERBOSE

	echo "$EXEC_MKUBIFS -r $root_path -o $ubi_fs_name -m $page_size -e $leb_size -c $bl_count -F $UBIFS_VERBOSE"
	echo "$EXEC_UBINIZE -o $ubi_bi_name -m $page_size -p $bl_length$_KIB_ -s $subs_size $conf_path $UBIFS_VERBOSE"


	if [ "y" = $mkubinize ]; then
		$EXEC_UBINIZE -o $ubi_bi_name 			\
				-m $page_size					\
				-p $bl_length$_KIB_				\
				-s $subs_size					\
				$conf_path						\
				$UBIFS_VERBOSE
	fi

	[ $ubi_fs_name ] &&  chmod 666 $ubi_fs_name;
	[ $ubi_bi_name ] &&  chmod 666 $ubi_bi_name;

	# copy image
	if [ ! -z $FS_COPY_PATH ] && [ -d $FS_COPY_PATH ]; then
		[ $ubi_fs_name ]&& cp -f $ubi_fs_name $FS_COPY_PATH;
		[ $ubi_bi_name ]&& cp -f $ubi_bi_name $FS_COPY_PATH;
	fi
}


#################################################################
# RUN COMMAND
#################################################################

# check ubifs tools
EXEC_MKUBIFS=mkfs.ubifs
EXEC_UBINIZE=ubinize
if [ ! -z $FS_EXEC_PATH   ]; then
	EXEC_MKUBIFS=$FS_EXEC_PATH/$EXEC_MKUBIFS
	if [ ! -x "$EXEC_MKUBIFS" ]; then
		echo -e " check path mkfs.ubifs at $EXEC_MKUBIFS"
		exit 1;
	fi
fi

if [ ! -z $FS_EXEC_PATH   ]; then
	EXEC_UBINIZE=$FS_EXEC_PATH/$EXEC_UBINIZE
	if [ ! -x "$EXEC_UBINIZE" ]; then
		echo -e " check path ubinize at $EXEC_UBINIZE"
		exit 1;
	fi
fi

# build device nodes
ROOT_PATH=$FS_ROOT_PATH
if [ $FS_MAKE_DEVNODE = "y" ] || [ -n "$MKDEV_EXT_SH_PATH" ]; then
	check_permission_w $ROOT_PATH
	build_mkdev $ROOT_PATH $MKDEV_EXT_SH_PATH
fi

# build ubifs
param1=$ROOT_PATH
param2=$FS_NAME
param3=$PAGE_SIZE
param4=$SUB_PAGE_SIZE
param5=$PHYS_BL_SIZE
param6=$FS_SIZE
param7=$UFS_INI_PATH
param8=$UFS_BUILD_IMAGE
param9=$UFS_COMPRESS_TYPE
param10=$TOTAL_CHIP_SIZE

build_ubifs $param1 $param2 $param3 $param4 $param5 $param6 $param7 $param8 $param9 $param10


