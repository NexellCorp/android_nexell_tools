#!/usr/bin/env python

"""
Nexell android auto packaging tool.

Usage: nexell-pack.py -c config_file

config file example
===================
BOOT_MODE=usb
FASTBOOT_PATH=/home/swpark/android-sdk-linux/platform-tools
SECOND_BOOT=/home/swpark/nxp4330/packaging/pyrope_secondboot_20130731_800_800_SMP_L2_DOS_SPI.bin
NSIH=/home/swpark/nxp4330/packaging/NSIH.txt
RESULT_PATH=/home/swpark/ws/jb-mr1.1/result
"""

import os
import os.path
import sys

def loadConfig(filename):
    """load "name=value" """
    d = {}
    f = open(filename)
    if not f:
        print "config file not exist: " + filename
        sys.exit(1)
    for line in f:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        k,v = line.split("=", 1)
        d[k] = v
    f.close()
    return d

def checkConfig(config):
    """check configs """
    if not config["BOOT_MODE"]:
        print "No BOOT_MODE"
        sys.exit(1)

    if not config["FASTBOOT_PATH"]:
        print "No FASTBOOT_PATH"
        sys.exit(1)

    if config["BOOT_MODE"] == "usb":
        if not config["SECOND_BOOT"]:
            print "When usb boot mode, You must specify SECOND_BOOT to config file"
            sys.exit(1)
        if not config["NSIH"]:
            print "When usb boot mode, You must specify SECOND_BOOT to config file"
            sys.exit(1)

    if not config["RESULT_PATH"]:
        print "No RESULT_PATH"
        sys.exit(1)

def main(argv):
    if len(argv) < 2:
        print __doc__
        sys.exit(1)

    config = loadConfig(argv[1])

    checkConfig(config)

    bootmode = config.get("BOOT_MODE", "")
    if bootmode == "usb":
        pass


