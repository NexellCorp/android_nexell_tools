#!/bin/bash

function jenkin_apply_all_patches()
{
	top=$(pwd)
	list=$(cat ${top}/.repo/manifests/default.xml | grep revision | tr '<' ' ' | tr '>' ' ' | awk '{print $2}' | tr '=' ' ' | awk '{print $2}' | tr "\"" " " )

	for path in $(echo $list)
	do
		first=$(echo -n $path | tr '/' ' ' | awk '{print $1}')
		if [ "${first}" != "refs" ]; then
			cd ${top}/${path}
			repo=$(git remote -v | grep fetch | awk '{print $2}' | sed -e "s/http:\/\/.*gerrit\///g")
			branch=$(git branch -a | grep "m/master" | head -1 | awk '{print $3}' | tr '/' ' ' | awk '{print $2}')
			echo "path ===> ${path}"
			echo "patch repo =====> ${repo}"
			echo "branch =====> ${branch}"
			${JENKINS_HOME}/scripts/getPatchSetLatest.sh -p ${repo} -b ${branch}
		fi
	done

	cd ${top}
}
