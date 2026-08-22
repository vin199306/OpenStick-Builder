#!/bin/sh -e

echo "Install dependencies\n"
scripts/install_deps.sh

echo "\nCreate rootfs\n"
scripts/alpine_rootfs.sh

echo "\nCreate images\n"
scripts/build_images.sh
