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

TOP=$(pwd)

##
# args
# $1: patch directory
function revert_common()
{
	local patch_dir=${1}
	echo "revert in ${patch_dir}"
	for f in $(ls ${patch_dir}); do
		echo "patch file --> ${f}"
		patch_path=$(echo -n ${f} | sed -e "s/@/\//g")
		echo "patch_path --> ${patch_path}"
		cd ${TOP}/${patch_path}
		git checkout ./
		git clean -df
		cd ${TOP}
	done
}
