import sys
import ctypes
import re

def process_nsih(nsih_file):
    header_list = []

    p = re.compile('^[a-zA-Z0-9]{,8}')
    while True:
        line = nsih_file.readline()
        if not line: break
        m = p.match(line)
        if m and m.group():
            header_list.append(int(m.group(), 16))

    buffer_len = len(header_list)
    while buffer_len < 128:
        header_list.append(0)
        buffer_len = buffer_len + 1

    return header_list

if __name__ == '__main__':

    if len(sys.argv) < 4:
        print("usage: %s NSIH-FILE 2NDBOOT-FILE OUTPUT-FILE" % sys.argv[0])
        sys.exit(0)

    nsih_file = open(sys.argv[1], 'r')
    if nsih_file is None:
        print("Invalid nsih file %s" % sys.argv[1])
        sys.exit(0)

    secondboot_file = open(sys.argv[2], 'rb')
    if secondboot_file is None:
        print("Invalid secondboot_file %s" % sys.argv[2])
        sys.exit(0)

    output_file = open(sys.argv[3], 'wb')
    if output_file is None:
        print("Can't open output file")
        sys.exit(0)

    header_list = process_nsih(nsih_file)
    header_buffer = (ctypes.c_uint32 * len(header_list))(*header_list)
    output_file.write(header_buffer)
    print output_file.tell()

    bin_buffer = secondboot_file.read()
    output_file.write(bin_buffer)
    print output_file.tell()

    nsih_file.close()
    secondboot_file.close()
    output_file.close()
