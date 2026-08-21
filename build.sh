#!/bin/sh -e

# The SP970 build only produces an Alpine rootfs image. The device's ORIGINAL
# boot.img and bootloaders from the Debian flashing package are reused as-is,
# so the lk2nd/hyp bootloader build step is intentionally skipped.

echo "Install dependencies\n"
scripts/install_deps.sh

echo "\nExtract MSM8916 firmware (from prebuilt)\n"
scripts/extract_fw.sh

echo "\nCreate rootfs\n"
scripts/alpine_rootfs.sh

echo "\nCreate images\n"
scripts/build_images.sh