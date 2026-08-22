#!/bin/sh -e

# Build the latest msm8916-mainline kernel for the SP970V11 and package a
# boot.img (Android boot image) that the stock aboot can load.
#
# Requires: kernel source already checked out at $KERNEL_DIR (see
# build-sp970v11.yml), aarch64 cross toolchain, mkbootimg, dtc.

KERNEL_DIR=${KERNEL_DIR=$(pwd)/linux-src}
CONFIG_FILE=${CONFIG_FILE=$(pwd)/configs/kernel-sp970v11.config}
DTB_NAME=msm8916-gexing-sp970v11
OUT_DIR=${OUT_DIR=$(pwd)/files}
MODULES_DIR=${MODULES_DIR=$(pwd)/modules}

export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-

mkdir -p ${OUT_DIR} ${MODULES_DIR}

cd ${KERNEL_DIR}

# 1. add the SP970V11 device tree to the kernel source
cp "$(pwd)/../dtbs/${DTB_NAME}.dts"  arch/arm64/boot/dts/qcom/
cp "$(pwd)/../dtbs/msm8916-sp970.dtsi" arch/arm64/boot/dts/qcom/
grep -q "${DTB_NAME}" arch/arm64/boot/dts/qcom/Makefile || \
    echo "dtb-\$(CONFIG_ARCH_QCOM) += ${DTB_NAME}.dtb" >> arch/arm64/boot/dts/qcom/Makefile

# 2. configure kernel: msm8916 defconfig + custom feature config
make msm8916_defconfig
scripts/kconfig/merge_config.sh -m -Q .config "${CONFIG_FILE}"
make olddefconfig

# 3. build kernel image, device tree and modules
make -j"$(nproc)" Image.gz dtbs modules
make -j"$(nproc)" INSTALL_MOD_PATH="${MODULES_DIR}" modules_install

# 4. package boot.img (Android boot image, stock aboot compatible)
#    kernel = Image.gz concatenated with the SP970V11 dtb
cat arch/arm64/boot/Image.gz arch/arm64/boot/dts/qcom/${DTB_NAME}.dtb \
    > "${OUT_DIR}/Image.gz-dtb"

# empty initramfs so the kernel falls through to root=LABEL=rootfs
rm -rf /tmp/empty-ramdisk
mkdir -p /tmp/empty-ramdisk
( cd /tmp/empty-ramdisk && find . | cpio -o -H newc > "${OUT_DIR}/ramdisk.img" 2>/dev/null )

mkbootimg \
    --kernel "${OUT_DIR}/Image.gz-dtb" \
    --ramdisk "${OUT_DIR}/ramdisk.img" \
    --pagesize 2048 \
    --base 0x80000000 \
    --kernel_offset 0x00008000 \
    --ramdisk_offset 0x01000000 \
    --tags_offset 0x00000100 \
    --cmdline "console=ttyMSM0,115200 root=LABEL=rootfs rw rootwait" \
    -o "${OUT_DIR}/boot.img"

echo "Kernel version: $(make kernelversion)"
echo "boot.img: $(ls -l ${OUT_DIR}/boot.img)"
echo "modules staged in: ${MODULES_DIR}"
