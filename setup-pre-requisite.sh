#!/bin/bash

#set -e

UBUNTU=`cat /etc/issue.net | cut -d' ' -f2`
HOST_ARCH=`uname -m`
if [ ${HOST_ARCH} == "x86_64" ] ; then
    PKGS='gnupg flex bison gperf build-essential zip curl zlib1g-dev libc6-dev lib32ncurses5-dev x11proto-core-dev libx11-dev lib32z1-dev libgl1-mesa-dev g++-multilib mingw32 tofrodos python-markdown libxml2-utils xsltproc u-boot-tools openjdk-6-jdk openjdk-6-jre vim-common python-parted python-yaml wget realpath'
else
    echo "ERROR: Only 64bit Host(Build) machines are supported at the moment."
    exit 1
fi

if [[ ${UBUNTU} =~ "13." || ${UBUNTU} =~ "12.10" ]]; then
    #Install basic dev package missing in chrooted environments
    sudo apt-get install software-properties-common
    sudo dpkg --add-architecture i386
    PKGS+=' libstdc++6:i386 git-core'
elif [[ ${UBUNTU} =~ "12.04" || ${UBUNTU} =~ "10.04" ]] ; then
    #Install basic dev package missing in chrooted environments
    sudo apt-get install python-software-properties
    if [[ ${UBUNTU} =~ "12.04" ]]; then
       PKGS+=' libstdc++6:i386 git-core'
    else
       PKGS+=' ia32-libs libssl-dev libcurl4-gnutls-dev libexpat1-dev gettext'
    fi
else
    echo "ERROR: Only Ubuntu 10.04, 12.* and 13.* versions are supported."
    exit 1
fi

echo
echo "Setting up Ubuntu software repositories..."
sudo add-apt-repository "deb http://archive.ubuntu.com/ubuntu $(lsb_release -sc) main universe restricted multiverse"
sudo apt-get update
echo

echo "Installing missing dependencies if any..."
sudo apt-get -y install ${PKGS}

# Obsolete git version 1.7.04 in lucid official repositories
# repo need at least git v1.7.2
if [[ ${UBUNTU} =~ "10.04" ]]; then
    echo
    echo "repo tool complains of obsolete git version 1.7.04 in lucid official repositories"
    echo "Building git for lucid from precise sources .."
    wget http://archive.ubuntu.com/ubuntu/pool/main/g/git/git_1.7.9.5.orig.tar.gz
    tar xzf git_1.7.9.5.orig.tar.gz
    cd git-1.7.9.5/
    make prefix=/usr
    sudo make prefix=/usr install
fi

echo -n "Check Android SDK... "
#if ! hash fastboot 2>/dev/null; then
if [ ! -f ~/android-sdk-linux/tools/android ]; then
    echo "Install android SDK"
    [ -f android-sdk_r22.3-linux.tgz ] && echo "Installing Android SDK" && tar xvzf android-sdk_r22.3-linux.tgz \
        && mv android-sdk-linux ~/ \
        && echo "" >> ~/.bashrc \
        && echo "# for android sdk" >> ~/.bashrc \
        && echo "export PATH=$PATH:$HOME/android-sdk-linux/tools" >> ~/.bashrc \
        && echo "export PATH=$PATH:$HOME/android-sdk-linux/platform-tools" >> ~/.bashrc \
        && ~/android-sdk-linux/tools/android
else
    echo "Installed"
fi

JAVA_VERSION=$(java -version 2>&1 | head -n 1 | grep '^java .*[ ""]1\.6[\. "$$"]')
IS_OPEN_JDK=$(java -version 2>&1 | grep -i openjdk)
echo "java version: $JAVA_VERSION, is_open_jdk: $IS_OPEN_JDK"
if [ -z "${JAVA_VERSION}" ] || [ -n "${IS_OPEN_JDK}" ]; then
    echo "Installing java jdk(1.6.0_34)"
    sudo ./jdk-6u34-linux-x64.bin
    sudo mv jdk1.6.0_34 /usr/lib/jvm
    sudo add-apt-repository ppa:nilarimogard/webupd8
    sudo apt-get update
    sudo apt-get install update-java
    sudo update-java

    JAVA_VERSION=`java -version`
    if [ ${JAVA_VERSION} != "1.6.0_34" ]; then
        echo "failed to install java 1.6.0_34"
        exit 1
    fi
    JAVAC_VERSION=`javac -version`
    if [ ${JAVAC_VERSION} != "1.6.0_34" ]; then
        echo "failed to install javac 1.6.0_34"
        exit 1
    fi
fi

echo "Setup Complete!!!"
