#!/bin/sh -e

DEVICE=${DEVICE=sp970}
PREBUILT=prebuilt/${DEVICE}

mkdir -p files

# copy base firmware from prebuilt
cp ${PREBUILT}/gpt_both0.bin files/
cp ${PREBUILT}/hyp.mbn files/
cp ${PREBUILT}/rpm.mbn files/
cp ${PREBUILT}/sbl1.mbn files/
cp ${PREBUILT}/tz.mbn files/
cp ${PREBUILT}/aboot.mbn files/

# copy modem firmware and baseband partitions
cp ${PREBUILT}/modem files/
cp ${PREBUILT}/baseband/fsg files/
cp ${PREBUILT}/baseband/modemst1 files/
cp ${PREBUILT}/baseband/modemst2 files/
