#!/bin/sh -e
# Build the SP970 mobile baseband stack on the BUILD HOST (x86_64 runner) and
# package only the *installed* files, so alpine_rootfs.sh can simply extract them
# into the image. Nothing of the build toolchain is ever carried into the final
# image (avoids python3/bloat and removes the apk-del cleanup dance).
#
# It creates an isolated aarch64 Alpine chroot (binfmt/qemu-aarch64-static runs
# the aarch64 binaries transparently), compiles ModemManager (patched) and
# qrtr-ns, then DESTDIR-installs them under $CHROOT/stage and tars that as:
#     build/modem-stage.tar.gz
#
# Output is consumed by scripts/alpine_rootfs.sh on the same CI runner.

export STAGE=${STAGE=$(pwd)/modem-stage}
CHROOT=${STAGE}/rootfs
APK_STATIC_URL=https://gitlab.alpinelinux.org/api/v4/projects/5/packages/generic/v3.0.6/x86_64/apk.static
RELEASE=${RELEASE=v3.24}

rm -rf ${STAGE}
mkdir -p ${CHROOT}/etc/apk

cat << EOF > ${CHROOT}/etc/apk/repositories
http://dl-cdn.alpinelinux.org/alpine/${RELEASE}/main
http://dl-cdn.alpinelinux.org/alpine/${RELEASE}/community
EOF

cp /etc/resolv.conf ${CHROOT}/etc/

mkdir -p ${CHROOT}/usr/bin
cp $(which qemu-aarch64-static) ${CHROOT}/usr/bin/

[ -e apk.static ] || wget -O apk.static ${APK_STATIC_URL}; chmod +x apk.static
./apk.static add -p ${CHROOT} --initdb -U --arch aarch64 --allow-untrusted alpine-base

# stage the sources + inner build script
mkdir -p ${CHROOT}/tmp
cp src/modemmanager-src.tar.gz ${CHROOT}/tmp/
cp src/qrtr-v1.2.tar.gz ${CHROOT}/tmp/

cat << 'BUILDEOF' > ${CHROOT}/tmp/build.sh
#!/bin/sh -e
# inner build, runs as aarch64 under qemu
apk add --no-cache \
    build-base meson samurai ninja pkgconf pkgconfig \
    glib-dev libqmi-dev libmbim-dev libqrtr-glib-dev libgudev-dev \
    polkit-dev dbus-dev eudev-dev linux-headers

cd /tmp
tar -xzf /tmp/modemmanager-src.tar.gz
mv ModemManager-fcc9d19f5ed6 ModemManager
cd /tmp/ModemManager

chmod +x build-aux/* 2>/dev/null || true

plugins="altair_lte anydata broadmobi cellient cinterion dell dlink fibocom \
    foxconn gosuncn haier huawei intel iridium linktop longcheer mbm motorola \
    mtk_legacy mtk netprisma nokia nokia_icera novatel novatel_lte option \
    option_hso pantech quectel rolling samsung sierra_legacy sierra simtech \
    telit thuraya tplink ublox via wavecom x22x zte"
disable_opts=""
for p in ${plugins}; do disable_opts="${disable_opts} -Dplugin_${p}=disabled"; done

meson setup build \
    --prefix=/usr --sysconfdir=/etc --libdir=/usr/lib \
    --buildtype=release \
    -Dgtk_doc=false -Dvapi=false -Dintrospection=false -Dtests=false -Dexamples=false \
    -Dbash_completion=false \
    -Dsystemdsystemunitdir=no \
    -Dsystemd_journal=false -Dsystemd_suspend_resume=false \
    -Dpolkit=permissive \
    -Dplugin_generic=enabled -Dplugin_qcom_soc=enabled \
    ${disable_opts}

ninja -C build -j2
DESTDIR=/stage ninja -C build install

# qrtr-ns (reference daemon; Alpine's qrtr package ships none). The MM ninja
# install does not create /stage/usr/local/bin so create it here for qrtr-ns
# and reboot-ctrl below.
mkdir -p /stage/usr/local/bin

cd /tmp
tar -xzf /tmp/qrtr-v1.2.tar.gz
cd /tmp/qrtr-1.2
gcc -O2 -o qrtr-ns \
    src/addr.c src/hash.c src/map.c src/ns.c src/util.c src/waiter.c \
    lib/logging.c lib/qmi.c lib/qrtr.c \
    -Iinclude -Ilib
cp qrtr-ns /stage/usr/local/bin/
chmod +x /stage/usr/local/bin/qrtr-ns

# reboot-ctrl: static helper that passes a restart reason ("bootloader"|"edl")
# to the bootloader via reboot(RB_AUTOBOOT, ...). busybox reboot cannot, and the
# wireguard build-base here is available, so compile it with the stage instead of
# building it inside the image (avoids apk add/del build-base at image build time).
cat > /tmp/reboot-ctrl.c << 'CEOF'
#include <unistd.h>
#include <sys/syscall.h>
#include <linux/reboot.h>
#include <string.h>
#include <stdio.h>
int main(int argc, char **argv) {
    const char *mode = (argc > 1) ? argv[1] : "bootloader";
    if (strcmp(mode, "bootloader") != 0 && strcmp(mode, "edl") != 0) {
        fprintf(stderr, "usage: reboot-ctrl bootloader|edl\n");
        return 1;
    }
    sync();
    syscall(SYS_reboot, LINUX_REBOOT_MAGIC1, LINUX_REBOOT_MAGIC2,
            LINUX_REBOOT_CMD_RESTART2, mode);
    return 0;
}
CEOF
gcc -O2 -static -o /stage/usr/local/bin/reboot-ctrl /tmp/reboot-ctrl.c
chmod +x /stage/usr/local/bin/reboot-ctrl
BUILDEOF

chroot ${CHROOT} ash -l -c "sh /tmp/build.sh"

# package only the installed files
mkdir -p build
tar -czf build/modem-stage.tar.gz -C ${CHROOT}/stage .

rm -rf ${STAGE}
echo "modem stage built:"
ls -la build/modem-stage.tar.gz