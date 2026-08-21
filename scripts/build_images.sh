#!/bin/sh -e

# Package the Alpine rootfs into a sparse ext4 image (label "rootfs").
# The device's ORIGINAL boot.img from the Debian flashing package is used as-is
# and is flashed untouched; only the rootfs is replaced with this image.

CHROOT=${CHROOT=$(pwd)/rootfs}
ROOTFS_SIZE=${ROOTFS_SIZE=536870912} # 512MiB, resized to the full partition on first boot

rm -f rootfs.raw
mkdir -p files mnt

truncate -s ${ROOTFS_SIZE} rootfs.raw
mkfs.ext4 -L rootfs rootfs.raw
mount rootfs.raw mnt
tar xpf alpine_rootfs.tgz -C mnt --exclude='./root/*' --exclude='./dev/*'

umount mnt

# create sparse android image
img2simg rootfs.raw files/alpine_rootfs.bin