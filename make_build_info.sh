#!/bin/bash

function make_build_info()
{
	local result_dir=${1}
	result_dir=$(echo -n ${result_dir} | sed -e 's/\///g')
	cp -a ${TOP}/device/nexell/tools/HOWTO_releasenotes.txt ${result_dir}
	cp -a ${TOP}/device/nexell/tools/HOWTO_install.txt ${result_dir}
	cp -a ${TOP}/device/nexell/tools/HOWTO_getsourceandbuild.txt ${result_dir}
	local dest_file=${TOP}/${result_dir}/HOWTO_releasenotes.txt
	local current_dir=$(pwd)

	list=$(cat ${TOP}/.repo/manifests/default.xml | grep revision | tr '<' ' ' | tr '>' ' ' | awk '{print $2}' | tr '=' ' ' | awk '{print $2}' | tr "\"" " " )
	for path in $(echo $list)
	do
		first=$(echo -n $path | tr '/' ' ' | awk '{print $1}')
		if [ "${first}" != "refs" ]; then
			cd ${TOP}/$path
			echo '---------------------------------------' >> ${dest_file}
			echo $path >> ${dest_file}
			echo $(git log -1 --pretty=oneline) >> ${dest_file}
			echo $(git log -1 --pretty=format:"%cd") >> ${dest_file}
			echo '---------------------------------------' >> ${dest_file}
		fi
	done

	cd ${current_dir}
}
