#!/bin/bash

# obejct
# this script changes jack server default setting
# in $HOME/.jack-settings and $HOME/.jack-server/config.properties.
#
# Overriden variable is like below
# $HOME/.jack-settings
#       SERVER_PORT_SERVICE
#       SERVER_PORT_ADMIN
# $HOME/.jack-server/config.properties
#       jack.server.service.port
#       jack.server.admin.port
#
# Default PORT_SERVICE: 8076
# Default PORT_ADMIN: 8077

TOP=$(pwd)

function usage()
{
	echo "at ANDROID TOP Directory"
	echo "./device/nexell/tools/jack-server-overriding.sh port_service port_admin"
	echo "ex> ./device/nexell/tools/jack-server-overriding.sh 9076 9077"
}

function reset_jack_server()
{
	${TOP}/prebuilts/sdk/tools/jack-admin stop-server
	${TOP}/prebuilts/sdk/tools/jack-admin kill-server
	${TOP}/prebuilts/sdk/tools/jack-admin uninstall-server
	rm -f ${HOME}/.jack-settings
	${TOP}/prebuilts/sdk/tools/jack-admin install-server \
		${TOP}/prebuilts/sdk/tools/jack-launcher.jar ${TOP}/prebuilts/sdk/tools/jack-server-4.8.ALPHA.jar
}

function change_jack_settings()
{
	local port_service=${1}
	local port_admin=${2}

	sed -i -e 's/SERVER_PORT_SERVICE=.*/SERVER_PORT_SERVICE='"${port_service}"'/g' ${HOME}/.jack-settings
	sed -i -e 's/SERVER_PORT_ADMIN=.*/SERVER_PORT_ADMIN='"${port_admin}"'/g' ${HOME}/.jack-settings
}

function start_jack_server_background()
{
	JACK_SERVER_VM_ARGUMENTS="-Dfile.encoding=UTF-8 -XX:+TieredCompilation -Xmx4096m" \
		${TOP}/prebuilts/sdk/tools/jack-admin start-server &
}

function kill_jack_server()
{
	local pid_of_jack_server=$(ps -a | grep jack-admin | awk '{print $1}')
	kill -9 ${pid_of_jack_server}
}

function change_jack_properties()
{
	local port_service=${1}
	local port_admin=${2}

	sed -i -e 's/jack\.server\.service\.port=.*/jack\.server\.service\.port='"${port_service}"'/g' ${HOME}/.jack-server/config.properties
	sed -i -e 's/jack\.server\.admin\.port=.*/jack\.server\.admin\.port='"${port_admin}"'/g' ${HOME}/.jack-server/config.properties
}

function start_jack_server()
{
	JACK_SERVER_VM_ARGUMENTS="-Dfile.encoding=UTF-8 -XX:+TieredCompilation -Xmx4096m" \
		${TOP}/prebuilts/sdk/tools/jack-admin start-server
}

test "$#" -ne 2 && usage && exit 0

reset_jack_server
change_jack_settings ${1} ${2}
start_jack_server_background
sleep 5
kill_jack_server
change_jack_properties ${1} ${2}
start_jack_server
