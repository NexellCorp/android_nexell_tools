#!/usr/bin/env python3

import yaml
import struct
import os
import sys

def p32(x): return struct.pack('<L', x)
def p8(x): return struct.pack('B', x)
def p64(x): return struct.pack('<Q', x)


def load_yaml(yaml_file_name):
    ''' load image description yaml file
    return dictionay
    '''
    fin = open(yaml_file_name, 'r')
    data = fin.read()
    fin.close()
    yaml_data = yaml.load(data)
    return yaml_data


def align_with(value, base):
    return (value + base - 1) & ~(base - 1)


def calc_files(d):
    ''' calculation src offset, src size and
    add d['images'][number]['src_offset'], d['images'][index]['src_size]'
    src_offset and src_size is aligned to 512 byte
    return new dictionay
    '''

    img_dir = d['image_dir']

    # start at 512
    # image header is located at first block(MBR)
    cur_offset = 512

    # bootloader for sdboot
    if 'bootloader' in d:
        file_name = img_dir + '/' + d['bootloader']
        # print("bootloader file --> ", file_name)
        file_size = os.path.getsize(file_name)
        file_size_aligned = align_with(file_size, 512)
        cur_offset += file_size_aligned

    for image in d['images']:
        file_name = img_dir + '/' + image['file']
        # print("image file --> ", file_name)
        file_size = os.path.getsize(file_name)
        file_size_aligned = align_with(file_size, 512)
        image['src_offset'] = cur_offset
        image['src_size'] = file_size
        cur_offset += file_size_aligned

    return d


def write_header(output_file, d):
    ''' write header data to output_file by d
    return True/False
    '''
    image_count = len(d['images'])
    # header tag: 4byte
    output_file.write(b'NIDH')
    # image count: 4byte
    output_file.write(p32(image_count))
    
    for image in d['images']:
        # image tag: 4byte
        output_file.write(b'IMGH')
        # image type: 4byte
        output_file.write(p32(image['type']))
        # dest offset: 8byte
        if 'dest_offset' in image:
            output_file.write(p64(image['dest_offset']))
        else:
            output_file.write(p64(0))
        # src offset
        output_file.write(p64(image['src_offset']))
        # src size
        output_file.write(p64(image['src_size']))

def write_file(output_file, offset, input_file_name):
    input_size = os.path.getsize(input_file_name)
    input_file = open(input_file_name, 'rb')
    count = align_with(input_size, 512)/512
    output_file.seek(offset)

    while input_size > 0:
        read_size = 512 if input_size >= 512 else input_size
        data = input_file.read(read_size)
        write_size = output_file.write(data)
        input_size -= write_size


if __name__ == '__main__':
    d = load_yaml(sys.argv[1])
    # print("load_yaml --> ", d)
    
    d = calc_files(d)
    # print("calc_files --> ", d)

    output_file = open(sys.argv[2], 'wb')
    write_header(output_file, d)

    # write bootloader for sd
    write_file(output_file, 512, d['image_dir'] + '/' + d['bootloader'])

    # write images
    for image in d['images']:
        write_file(output_file, image['src_offset'], d['image_dir'] + '/' +
                image['file'])

    output_file.close()
    print("Done")

