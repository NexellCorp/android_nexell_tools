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

function parse_partmap()
{
	local parts=$(cat partmap.txt | sed '/^# /d' | tr ':|;' ' ' | awk '{print $2 "," $5}')
	echo -n "${parts}"
}

function get_part_name()
{
	echo -n "${1}" | awk -F',' '{print $1}'
}

function get_part_image()
{
	echo -n "${1}" | awk -F',' '{print $2}'
}

function get_image()
{
	local found=""
	for part in ${PARTS}; do
		name=$(get_part_name ${part})
		image=$(get_part_image ${part})
		if [ $name == ${1} ]; then
			found=${image}
			break
		fi
	done
	echo -n "${found}"
}

function get_partname_by_image()
{
	local found=""
	for part in ${PARTS}; do
		name=$(get_part_name ${part})
		image=$(get_part_image ${part})
		if [ $image == ${1} ]; then
			found=${name}
			break
		fi
	done
	echo -n "${found}"
}

PARTS=$(parse_partmap)

sudo fastboot flash partmap partmap.txt

if [ $# -lt 1 ]; then
	# fuse all
	for part in ${PARTS}; do
		name=$(get_part_name ${part})
		image=$(get_part_image ${part})
		# echo "${name} ==> ${image}"
		test -f ${image} && sudo fastboot flash ${name} ${image}
	done
else
	while [ "${1}" != "" ]; do
		case "${1}" in
			-t ) image=$(get_image ${2}); sudo fastboot flash ${2} ${image}; shift 2 ;;
			*  ) part_name=$(get_partname_by_image ${1});
				echo "part_name --> ${part_name}";
				if [ "${part_name}" == "" ]; then
					echo "No part for ${1}";
				else
					sudo fastboot flash ${part_name} ${1};
				fi
				shift 1 ;;
		esac
	done
fi
