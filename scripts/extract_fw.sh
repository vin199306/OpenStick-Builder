#!/bin/sh -e

# Collect the SP970 bootloader / partition firmware already present in the
# device's Debian flashing package (kept in prebuilt/<DEVICE>/). No downloads:
# the original boot.img and bootloaders are flashed untouched by the package's
# own flash script.

DEVICE=${DEVICE=SP970}
PREBUILT=${PREBUILT=$(pwd)/prebuilt/${DEVICE}}

mkdir -p files

cp ${PREBUILT}/aboot.bin     files/aboot.bin
cp ${PREBUILT}/gpt_both0.bin files/gpt_both0.bin
cp ${PREBUILT}/hyp.mbn       files/hyp.mbn
cp ${PREBUILT}/rpm.mbn       files/rpm.mbn
cp ${PREBUILT}/sbl1.mbn      files/sbl1.mbn
cp ${PREBUILT}/tz.mbn        files/tz.mbn