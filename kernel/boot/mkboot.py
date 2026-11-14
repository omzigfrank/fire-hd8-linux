#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Build a boot_x image the stock Fire HD 8 (2017, "douglas") bootloader can start.

Layout (Android boot image v0, 2048-byte pages):
  header | MTK "KERNEL" header + gzip(relocation shim + Image) + DTB (+64 KiB slack) | initramfs

The stock LK
  * expects a 512-byte MediaTek header in front of the kernel blob,
  * decompresses the kernel to 0x40080000 and silently hangs if the result exceeds
    about 28 MiB, so the payload is limited to 0x1bf0000 bytes,
  * finds the DTB appended after the gzip stream and patches it in place, so the DTB
    gets 64 KiB of free space for those fixups.

Usage: mkboot.py --image Image --dtb board.dtb --initramfs initramfs.cpio.gz --out boot.img
"""
import argparse
import gzip
import hashlib
import struct
import subprocess
import tempfile
from pathlib import Path

PAGE = 2048
KERNEL_ADDR = 0x40080000
RAMDISK_ADDR = 0x46000000
SECOND_ADDR = 0x40F00000
TAGS_ADDR = 0x48000000
LK_PAYLOAD_LIMIT = 0x1BF0000      # decompressed shim+Image must stay below this
BL31_BASE = 0x43000000            # vendor secure firmware; the kernel must not overlap it
RELOC_BASE = 0x40200000

DEFAULT_CMDLINE = ('bootopt=64S3,32N2,64N2 console=tty0 fbcon=vc:2-63 vt.global_cursor_default=0 '
                   'loglevel=4 nokaslr clk_ignore_unused pd_ignore_unused regulator_ignore_unused '
                   'douglas_genpd_keep_on rdinit=/init')


def align(n):
    return (n + PAGE - 1) // PAGE * PAGE


def mtk_header(name, data):
    hdr = bytearray(b'\xff' * 512)
    struct.pack_into('<II', hdr, 0, 0x58881688, len(data))
    hdr[8:40] = name.encode().ljust(32, b'\0')
    return bytes(hdr) + data


def boot_id(kernel, ramdisk):
    h = hashlib.sha1()
    for part in (kernel, ramdisk, b''):
        h.update(part)
        h.update(struct.pack('<I', len(part)))
    return h.digest()


def build_shim(image, mem_bytes, cross):
    src = Path(__file__).with_name('relocate-kernel.S')
    with tempfile.TemporaryDirectory() as tmp:
        obj, binf = Path(tmp, 'shim.o'), Path(tmp, 'shim.bin')
        subprocess.run([f'{cross}gcc', '-c', '-x', 'assembler-with-cpp',
                        f'-DIMAGE_BYTES={len(image)}', f'-DIMAGE_MEMORY_BYTES={mem_bytes}',
                        str(src), '-o', str(obj)], check=True)
        subprocess.run([f'{cross}objcopy', '-O', 'binary', str(obj), str(binf)], check=True)
        shim = binf.read_bytes()
    if len(shim) != 4096 or shim[56:60] != b'ARM\x64':
        raise SystemExit('relocation shim did not assemble to a 4 KiB arm64 header')
    return shim


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--image', required=True, type=Path)
    ap.add_argument('--dtb', required=True, type=Path)
    ap.add_argument('--initramfs', required=True, type=Path)
    ap.add_argument('--out', required=True, type=Path)
    ap.add_argument('--cmdline', default=DEFAULT_CMDLINE)
    ap.add_argument('--cross', default='aarch64-linux-gnu-')
    a = ap.parse_args()

    image = a.image.read_bytes()
    if image[56:60] != b'ARM\x64':
        raise SystemExit(f'{a.image} is not an arm64 Image')
    mem_bytes = struct.unpack_from('<Q', image, 16)[0]
    if RELOC_BASE + mem_bytes > BL31_BASE:
        raise SystemExit(f'kernel footprint {mem_bytes:#x} would overlap BL31 at {BL31_BASE:#x}; trim the config')

    payload = build_shim(image, mem_bytes, a.cross) + image.ljust((len(image) + 7) // 8 * 8, b'\0')
    if len(payload) > LK_PAYLOAD_LIMIT:
        raise SystemExit(f'kernel payload {len(payload):#x} exceeds the LK limit {LK_PAYLOAD_LIMIT:#x}; trim the config')

    dtb = bytearray(a.dtb.read_bytes())
    if struct.unpack_from('>I', dtb, 0)[0] != 0xD00DFEED or struct.unpack_from('>I', dtb, 4)[0] != len(dtb):
        raise SystemExit(f'{a.dtb} is not a valid DTB')
    struct.pack_into('>I', dtb, 4, len(dtb) + 65536)
    dtb += bytes(65536)

    kernel = mtk_header('KERNEL', gzip.compress(payload, compresslevel=9, mtime=0) + bytes(dtb))
    ramdisk = a.initramfs.read_bytes()
    if ramdisk[:2] != b'\x1f\x8b':
        raise SystemExit(f'{a.initramfs} is not a gzip-compressed cpio archive')

    cmdline = a.cmdline.encode()
    if len(cmdline) >= 512:
        raise SystemExit('command line too long (max 511 bytes)')

    hdr = bytearray(PAGE)
    hdr[0:8] = b'ANDROID!'
    struct.pack_into('<10I', hdr, 8, len(kernel), KERNEL_ADDR, len(ramdisk), RAMDISK_ADDR,
                     0, SECOND_ADDR, TAGS_ADDR, PAGE, 0, 0)
    hdr[64:576] = cmdline.ljust(512, b'\0')
    hdr[576:608] = boot_id(kernel, ramdisk).ljust(32, b'\0')

    out = bytes(hdr) + kernel.ljust(align(len(kernel)), b'\0') + ramdisk.ljust(align(len(ramdisk)), b'\0')
    a.out.write_bytes(out)
    print(f'{a.out}: {len(out)} bytes, payload {len(payload):#x} of {LK_PAYLOAD_LIMIT:#x}, '
          f'sha256 {hashlib.sha256(out).hexdigest()}')


if __name__ == '__main__':
    main()
