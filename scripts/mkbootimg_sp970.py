#!/usr/bin/env python3
"""Self-contained Android boot.img packer (header v0, classic format).

Replaces the Ubuntu `mkbootimg` package, which is broken on Noble (24.04):
it imports the `gki` module that no Ubuntu package ships, so it crashes with
"ModuleNotFoundError: No module named 'gki'" even for a plain boot image.

The format below matches what the stock MSM8916 aboot loads (same offsets as
the original boot.img and the action-build-openstick-kernel repack hook).
"""

import argparse
import struct


def pack_bootimg(kernel, ramdisk, output, page_size=2048, base=0x80000000,
                 kernel_offset=0x00008000, ramdisk_offset=0x01000000,
                 tags_offset=0x00000100, cmdline=""):
    kernel_addr = base + kernel_offset
    ramdisk_addr = base + ramdisk_offset
    tags_addr = base + tags_offset

    def pad(data):
        return data + b"\x00" * ((-len(data)) % page_size)

    # struct boot_img_hdr_v0: magic(8) + 10x u32 + name(16) + cmdline(512)
    #                        + id(32) + extra_cmdline(1024) = 1632 bytes
    header = struct.pack(
        "8s10I16s512s32s1024s",
        b"ANDROID!",
        len(kernel), kernel_addr,
        len(ramdisk), ramdisk_addr,
        0, 0,                      # second stage (unused)
        tags_addr,
        page_size,
        0,                         # header_version
        0,                         # os_version
        b"\x00" * 16,              # name
        cmdline.encode()[:511].ljust(512, b"\x00"),
        b"\x00" * 32,              # id
        b"\x00" * 1024,            # extra_cmdline
    )
    header = pad(header)

    with open(output, "wb") as f:
        f.write(header)
        f.write(pad(kernel))
        f.write(pad(ramdisk))


def main():
    ap = argparse.ArgumentParser(description="Pack an Android boot image (v0)")
    ap.add_argument("--kernel", required=True)
    ap.add_argument("--ramdisk", required=True)
    ap.add_argument("--pagesize", type=int, default=2048)
    ap.add_argument("--base", type=lambda x: int(x, 0), default=0x80000000)
    ap.add_argument("--kernel_offset", type=lambda x: int(x, 0), default=0x00008000)
    ap.add_argument("--ramdisk_offset", type=lambda x: int(x, 0), default=0x01000000)
    ap.add_argument("--tags_offset", type=lambda x: int(x, 0), default=0x00000100)
    ap.add_argument("--cmdline", default="")
    ap.add_argument("-o", "--output", required=True)
    args = ap.parse_args()

    with open(args.kernel, "rb") as f:
        kernel = f.read()
    with open(args.ramdisk, "rb") as f:
        ramdisk = f.read()

    pack_bootimg(kernel, ramdisk, args.output, args.pagesize, args.base,
                 args.kernel_offset, args.ramdisk_offset, args.tags_offset,
                 args.cmdline)
    print(f"boot.img written: {args.output}")


if __name__ == "__main__":
    main()
