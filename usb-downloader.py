# run : sudo python usb-downloader.py -b pyrope_2ndboot_USB.bin -f u-boot.bin -a 0x41000000 -j 0x41000000 -n NSIH_USB.txt
import os
import sys
import argparse
import usb.core
import usb.util
import ctypes
import pexpect
import re
import time

class logging_spawn(pexpect.spawn):
    def __init__(self, command, timeout=30):
        pexpect.spawn.__init__(self, command, timeout=timeout)
        self.delaybeforesend = 0.05

    def sendline(self, s=''):
        return super(logging_spawn, self).sendline(s)

class USBNotConnected(Exception): pass
class USBDownloadFail(Exception): pass
class SpawnSerialFail(Exception): pass

class UsbDownloader():
    def __init__(self):
        ''' check usb connection '''
        dev = usb.core.find(idVendor=0x2375, idProduct=0x4330)
        if not dev:
            raise USBNotConnected
        dev.set_configuration()
        self.dev = dev

    def process_nsih(self):
        header_list = []

        p = re.compile('^[a-zA-Z0-9]{,8}')
        while True:
            line = self.nsih_file.readline()
            if not line: break
            m = p.match(line)
            if m and m.group():
                header_list.append(int(m.group(), 16))

        buffer_len = len(header_list)
        while buffer_len < 128:
            header_list.append(0)
            buffer_len = buffer_len + 1

        self.nsih_file.close()

        return header_list

    def register_options(self):
        parser = argparse.ArgumentParser()
        parser.add_argument("-b", "--bootfile", help="download file")
        parser.add_argument("-f", "--downfile", help="download file")
        parser.add_argument("-a", "--downaddr", help="download address hex")
        parser.add_argument("-j", "--jumpaddr", help="jump address hex")
        parser.add_argument("-n", "--nsih", help="nsih file")
        return parser

    def parse_and_check_options(self, parser):
        args = parser.parse_args()
        if not args.bootfile or not args.downfile or not args.nsih or not args.downaddr or not args.jumpaddr:
            print("Invalid arguments!!!")
            raise ValueError("Invalid arguments")

        self.download_addr = int(args.downaddr, 16)
        self.jump_addr = int(args.jumpaddr, 16)

        self.boot_file = open(args.bootfile, "rb")
        if not self.boot_file:
            print("No boot file %s" % args.bootfile)
            raise ValueError("No boot file")

        self.download_file = open(args.downfile, "rb")
        if not self.download_file:
            print("No download file %s" % args.downfile)
            raise ValueError("No download file")

        self.nsih_file = open(args.nsih, "r")
        if not self.nsih_file:
            print("No download file %s" % args.nsih)
            raise ValueError("No nsih file")

        print("===========================================")
        print("Boot File: %s" % args.bootfile)
        print("Download File: %s" % args.downfile)
        print("NSIH File: %s" % args.nsih)
        print("Download Address: %#x" % me.download_addr)
        print("Jump Address: %#x" % me.jump_addr)
        print("===========================================")

    def download_header(self, header_list):
        header_buffer = (ctypes.c_uint32 * len(header_list))(*header_list)

        write_len = self.dev.write(2, buffer(header_buffer), 0, 1000)
        if write_len != 512:
            print("error: failed to download header")
            raise USBDownloadFail

        del header_buffer

    def download_boot_file(self):
        boot_file_data = me.boot_file.read()
        try:
            me.dev.write(2, boot_file_data, 0, 1000)
        except:
            print("error: failed to download bootfile");
            raise USBDownloadFail

    def spawn_serial(self):
        serial = logging_spawn("screen -t 'ttyUSB0 115200 8n1' /dev/ttyUSB0 115200,-ixoff,-ixon")
        if not serial:
            print("error spawn serial channel")
            raise SpawnSerialFail
        return serial

    def close_serial(self, serial):
        serial.sendcontrol('a')
        serial.send('k')
        serial.sendline('y')
        del serial
        dirlist = os.listdir("/var/run/screen/S-root")
        print dirlist

    def check_second_boot(self, serial):
        dummy_buffer = (ctypes.c_uint32 * 128)()

        while True:
            try:
                me.dev.write(2, buffer(dummy_buffer), 0, 1000)
            except:
                print("check second boot running...")
                print("success")
                break
                # if serial:
                #     index = serial.expect(['Second Boot by Nexell', pexpect.EOF, pexpect.TIMEOUT])
                #     if index == 1 or index == 2:
                #         print("second boot fail... check board!!!")
                #         break
                #     else:
                #         print("success!!!")
                #         break
                #     break

    def check_uboot(self, serial):
        pass
        # if serial:
        #     print("check u-boot running...")
        #     index = serial.expect(['U-BOOT', pexpect.EOF, pexpect.TIMEOUT])
        #     if index == 1 or index == 2:
        #         print("u-boot failed... check board!!!")
        #     else:
        #         print("success!!!")

if __name__ == '__main__':

    try:
        me = UsbDownloader()
    except:
        print("failed to connect to device!!!")
        sys.exit(1)

    parser = me.register_options()
    try:
        me.parse_and_check_options(parser)
    except:
        sys.exit(1)

    del parser

    header_list = me.process_nsih()
    # load size : 17, load addr : 18, launch addr : 19
    download_file_data = me.download_file.read()
    print("download file size %d" % len(download_file_data))
    header_list[17] = len(download_file_data)
    header_list[18] = me.download_addr
    header_list[19] = me.jump_addr
    me.download_header(header_list)

    me.download_boot_file()

    # serial = me.spawn_serial()
    serial = None
    me.check_second_boot(serial)
    del me

    time.sleep(1)


    # while True:
    #     try:
    #         me = UsbDownloader()
    #         if me: break
    #     except:
    #         pass

    try:
        me = UsbDownloader()
    except:
        print("Error connect to device!!!")
        sys.exit(1)

    try:
        me.download_header(header_list)
        me.dev.write(2, download_file_data, 0, 5000)
    except:
        print("error: failed to download downfile")
        raise USBDownloadFail

    me.check_uboot(serial)
    # me.close_serial(serial)

    print("exit")
