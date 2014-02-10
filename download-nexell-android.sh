#!/bin/bash

set -e

DEVEL_SERVER_URL="ssh://git@210.219.52.221:9999/nexell/pyrope/android/manifest"
OPEN_SERVER_URL="git://210.219.52.221/nexell/pyrope/android/manifest"
DIR=nexell-android

usage()
{
    echo 'Usage: $0 -s <server(devel/open)> -v <android version name(jb/kitkat)> [ -d directory ]'
    echo -e '\n -s <server> : devel or open'
    echo " -v <android version name> : jb or kitkat"
    echo " -d <directory> : The directory to download code, Default: ${DIR}"
    exit 1
}

function parse_args()
{
    TEMP=`getopt -o "s:v:d:h" -- "$@"`
    eval set -- "$TEMP"

    while true; do
        case $1 in
            -s  ) SERVER=$2; shift 2 ;;
            -v  ) VERSION=$2; shift 2 ;;
            -d  ) DIR=$2; shift 2 ;;
            -h  ) usage; exit 1;;
            --  ) break ;;
        esac
    done
}

function check_server()
{
    if [ ${SERVER} == "devel" ]; then
        SERVER=${DEVEL_SERVER_URL}
    elif [ ${SERVER} == "open" ]; then
        SERVER=${OPEN_SERVER_URL}
    else
        echo "Invalid server name: ${SERVER}"
        usage
        exit 1
    fi
}

function check_android_version()
{
    if [ ${VERSION} == "jb" ]; then
        VERSION="jb-mr1.1"
    elif [ ${VERSION} == "kitkat" ]; then
        VERSION="kitkat-release"
    else
        usage
        exit 1
    fi

    echo "version: ${VERSION}"
}

function check_download_dir()
{
    if [ -d ${DIR} ]; then
        read -p "Directory ${DIR} exists. Are you sure you want to use this? (y/n)" CONTINUE
        [ ${CONTINUE} == y ] || exit 1
    else
        mkdir ${DIR}
    fi
}

function download_repo()
{
    local repo_exist=$(which repo)
    echo "repo_exist: ${repo_exist}"
    if [ -z ${repo_exist} ]; then
        echo "Download repo"
        mkdir -p ~/bin
        curl http://commondatastorage.googleapis.com/git-repo-downloads/repo > ~/bin/repo
        chmod a+x ~/bin/repo
        echo "export PATH=$PATH:~/bin" >> ~/.bashrc
        source ~/.bashrc
    fi
}

function check_git_config()
{
    if [ ! -f ~/.gitconfig ]; then
        echo "false"
    else
        local name=$(cat ~/.gitconfig | grep "name =")
        local email=$(cat ~/.gitconfig | grep "email =")
        if (( ${#name} > 0)) && (( ${#email} > 0 )); then
            echo "true"
        else
            echo "fale"
        fi
    fi
}

function set_git_name_and_email()
{
    git_configured=$(check_git_config)
    if [ ${git_configured} == "false" ]; then
        local git_name=
        local git_email=
        until [ ${git_name} ]; do
            read -p "enter your name for git config: " git_name
            if [ -z ${git_name} ]; then
                echo "Error: You must enter your name in English!!!"
            fi
        done
        git config --global user.name ${git_name}

        until [ ${git_email} ]; do
            read -p "enter your email for git config: " git_email
            if [ -z ${git_email} ]; then
                echo "Error: You must enter your email in English!!!"
            fi
        done
        git config --global user.email ${git_email}
    fi
}

function download_source()
{
    echo "Download ${VERSION} from ${SERVER} to ${DIR}"

    cd ${DIR}

    echo "repo init -u ${SERVER} -b ${VERSION}"
    repo init -u ${SERVER} -b "${VERSION}"
    if [ $? -ne 0 ]; then
        echo "Error repo init"
        rm -rf .repo
        exit 1
    fi

    repo sync
    if [ $? -ne 0 ]; then
        echo "Error repo sync"
        rm -rf .repo
        exit 1
    fi

    echo "Download Complete!!!"
}

parse_args $@
check_server
check_download_dir
check_android_version
download_repo
set_git_name_and_email
download_source
