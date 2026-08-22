#!/bin/sh -e

CHROOT=${CHROOT=$(pwd)/rootfs}
DEVICE=${DEVICE=SP970V11}
ROOTFS_SIZE=${ROOTFS_SIZE=536870912} # 512MiB, resized to the full partition on first boot

# package rootfs
rm -f rootfs.raw
mkdir -p files mnt

# create root img
truncate -s ${ROOTFS_SIZE} rootfs.raw
mkfs.ext4 -L rootfs rootfs.raw
mount rootfs.raw mnt
tar xpf alpine_rootfs.tgz -C mnt --exclude='./boot/*' --exclude='./root/*' --exclude='./dev/*'

umount mnt

# create sparse android image
img2simg rootfs.raw files/${DEVICE}-alpine-rootfs.img
