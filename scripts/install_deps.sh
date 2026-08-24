#!/bin/sh -e

apt update
apt install -y \
    android-sdk-libsparse-utils \
    binfmt-support \
    qemu-user-static \
    wget \
    gcc-aarch64-linux-gnu \
    libc6-dev-arm64-cross
