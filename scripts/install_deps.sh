#!/bin/sh -e

apt update
apt install -y \
    android-sdk-libsparse-utils \
    binfmt-support \
    qemu-user-static \
    wget
