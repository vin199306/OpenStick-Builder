#!/bin/sh -e

# Build a minimal Alpine rootfs for the SP970 (MSM8916) dongle using the STOCK
# kernel and firmware extracted from the device's Debian flashing package.
#
# The stock boot.img (from the flashing package) is used as-is; this script only
# produces the rootfs that boot.img mounts as "/".

export CHROOT=${CHROOT=$(pwd)/rootfs}
export HOST_NAME=${HOST_NAME=OpenStick}
export ROOT_PASSWORD=${ROOT_PASSWORD=password}
export RELEASE=${RELEASE=v3.24}
export MIRROR=${MIRROR=http://dl-cdn.alpinelinux.org/alpine}
export APK_STATIC_URL=https://gitlab.alpinelinux.org/api/v4/projects/5/packages/generic/v3.0.6/x86_64/apk.static

DEVICE=${DEVICE=SP970}
PREBUILT=${PREBUILT=$(pwd)/prebuilt/${DEVICE}}
KVER=5.15.0-handsomekernel+

rm -rf ${CHROOT}
mkdir -p ${CHROOT}/etc/apk

cat << EOF > ${CHROOT}/etc/apk/repositories
${MIRROR}/${RELEASE}/main
${MIRROR}/${RELEASE}/community
EOF

cp /etc/resolv.conf ${CHROOT}/etc/

mkdir -p ${CHROOT}/usr/bin
cp $(which qemu-aarch64-static) ${CHROOT}/usr/bin

[ -e apk.static ] || wget ${APK_STATIC_URL}
chmod a+x apk.static
./apk.static add -p ${CHROOT} --initdb -U --arch aarch64 --allow-untrusted alpine-base

# install apps
chroot ${CHROOT} ash -l -c "
apk add --allow-untrusted \
    dbus \
    dbus-openrc \
    dropbear \
    e2fsprogs-extra \
    eudev \
    eudev-openrc \
    iptables \
    ip6tables \
    iproute2 \
    iw \
    kmod \
    networkmanager \
    networkmanager-dnsmasq \
    networkmanager-openrc \
    networkmanager-wifi \
    openrc \
    wireless-regdb \
    wpa_supplicant
"

# postmarketOS packages (msm-firmware-loader, rmtfs). Kept as a guarded, last-
# resort step on their own repo so a pmOS problem can never affect the core
# image. rmtfs hard-depends on systemd-udevd, which is NOT in the Alpine v3.24
# repos; if that (or any pmOS repo) cannot be resolved apk fails, so never let
# it abort the build. This device has no SIM, so skipping rmtfs is non-fatal.
cat << EOF >> ${CHROOT}/etc/apk/repositories
http://mirror.postmarketos.org/postmarketos/v25.12
EOF
if chroot ${CHROOT} ash -l -c \
      "apk update && apk add --allow-untrusted msm-firmware-loader msm-firmware-loader-openrc rmtfs rmtfs-openrc" 2>/dev/null; then
    echo "postmarketos: msm-firmware-loader + rmtfs installed"
else
    echo "postmarketos: skipped (repo/deps not resolvable) -> core image unaffected"
fi

# UKI/initramfs style: the stock boot.img mounts the rootfs at '/' via the
# bootloader-passed root parameter, so fstab only adds the configfs mount that
# the USB NCM gadget (setup_ncm_gadget.sh) requires.
cat << 'EOF' > ${CHROOT}/etc/fstab
configfs /sys/kernel/config configfs nodev,noexec,nosuid 0 0
EOF

# hostname
echo ${HOST_NAME} > ${CHROOT}/etc/hostname
sed -i "/localhost/ s/\$/ ${HOST_NAME}/" ${CHROOT}/etc/hosts

# root password
chroot ${CHROOT} ash -l -c "echo 'root:${ROOT_PASSWORD}' | chpasswd"

# install stock kernel modules and wifi firmware
mkdir -p ${CHROOT}/lib/modules ${CHROOT}/lib/firmware
cp -a ${PREBUILT}/lib/modules/. ${CHROOT}/lib/modules/
cp -a ${PREBUILT}/lib/firmware/. ${CHROOT}/lib/firmware/

# rebuild module dependency db inside the chroot
chroot ${CHROOT} ash -l -c "depmod -a ${KVER}"

# kernel module autoload: wcnss (wifi) and cpufreq_ondemand
printf 'qcom_wcnss_pil\n'  > ${CHROOT}/etc/modules-load.d/wcnss.conf
printf 'cpufreq_ondemand\n' > ${CHROOT}/etc/modules-load.d/cpufreq.conf

# NCM USB gadget: bring it up when the UDC appears
mkdir -p ${CHROOT}/etc/udev/rules.d ${CHROOT}/usr/local/bin
cp scripts/setup_ncm_gadget.sh ${CHROOT}/usr/local/bin/setup_ncm_gadget.sh
cat << 'EOF' > ${CHROOT}/etc/udev/rules.d/10-udc.rules
ACTION=="add", SUBSYSTEM=="udc", RUN+="/sbin/modprobe libcomposite", RUN+="/usr/local/bin/setup_ncm_gadget.sh"
EOF
# Bring usb0 up as soon as it appears. NetworkManager only autoconnects an
# ethernet device once it has carrier, but a gadget interface only reports
# carrier after it is administratively UP - without this the NCM link stays
# down and the host always shows "not connected".
cat << 'EOF' > ${CHROOT}/etc/udev/rules.d/11-usb0.rules
ACTION=="add", SUBSYSTEM=="net", KERNEL=="usb0", RUN+="/sbin/ip link set usb0 up"
EOF

# NetworkManager system connections: USB NCM (192.168.5.1/24 shared) and
# WiFi hotspot (192.168.4.1/24 shared). LTE connection is intentionally absent
# (no SIM / no ModemManager).
mkdir -p ${CHROOT}/etc/NetworkManager/system-connections
cat << 'EOF' > ${CHROOT}/etc/NetworkManager/system-connections/usb.nmconnection
[connection]
id=usb
uuid=6d73d069-b482-41ec-bbc2-f769089700cb
type=ethernet
interface-name=usb0

[ethernet]

[ipv4]
address1=192.168.5.1/24
method=shared

[ipv6]
addr-gen-mode=default
method=auto

[proxy]
EOF
cat << 'EOF' > ${CHROOT}/etc/NetworkManager/system-connections/hotspot.nmconnection
[connection]
id=hotspot
uuid=8f9b8a1e-3c2f-4b5a-9d1e-6f0d2c1b7a9e
type=wifi
interface-name=wlan0

[wifi]
band=bg
mode=ap
ssid=Openstick

[wifi-security]
group=ccmp;
key-mgmt=wpa-psk
pairwise=ccmp;
proto=rsn;
psk=12345678

[ipv4]
address1=192.168.4.1/24
method=shared

[ipv6]
addr-gen-mode=default
method=disabled

[proxy]
EOF
chmod 0600 ${CHROOT}/etc/NetworkManager/system-connections/*

# first-boot partition resize
mkdir -p ${CHROOT}/etc/local.d
cat << 'EOF' > ${CHROOT}/etc/local.d/resize-rootfs.start
#!/bin/sh
ROOTDEV=$(awk '$2 == "/" {print $1}' /proc/mounts)
case "${ROOTDEV}" in
    /dev/mmcblk*) ;;
    *) exit 0 ;;
esac
resize2fs "${ROOTDEV}" 2>/dev/null || true
EOF
chmod +x ${CHROOT}/etc/local.d/resize-rootfs.start

# CPU ondemand governor
cat << 'EOF' > ${CHROOT}/etc/local.d/cpufreq.start
#!/bin/sh
[ -w /sys/devices/system/cpu/cpufreq/policy0/scaling_governor ] || exit 0
echo ondemand > /sys/devices/system/cpu/cpufreq/policy0/scaling_governor
echo 75     > /sys/devices/system/cpu/cpufreq/ondemand/up_threshold
echo 20000  > /sys/devices/system/cpu/cpufreq/ondemand/sampling_rate
echo 4      > /sys/devices/system/cpu/cpufreq/ondemand/sampling_down_factor
EOF
chmod +x ${CHROOT}/etc/local.d/cpufreq.start

# enable services
chroot ${CHROOT} rc-update add devfs sysinit
chroot ${CHROOT} rc-update add dmesg sysinit
# udev scripts may differ between eudev and systemd-udev; enable only what exists
# so a udev implementation change (e.g. from rmtfs swapping eudev) never aborts.
chroot ${CHROOT} sh -c '[ -e /etc/init.d/udev ]           && rc-update add udev           sysinit || true'
chroot ${CHROOT} sh -c '[ -e /etc/init.d/udev-trigger ]   && rc-update add udev-trigger   sysinit || true'
chroot ${CHROOT} sh -c '[ -e /etc/init.d/udev-settle ]    && rc-update add udev-settle    sysinit || true'
chroot ${CHROOT} sh -c '[ -e /etc/init.d/udev-postmount ] && rc-update add udev-postmount default || true'
chroot ${CHROOT} rc-update add sysctl boot
chroot ${CHROOT} rc-update add localmount boot
chroot ${CHROOT} rc-update add swap boot
chroot ${CHROOT} rc-update add hostname boot
chroot ${CHROOT} rc-update add bootmisc boot
chroot ${CHROOT} rc-update add hwclock boot
chroot ${CHROOT} rc-update add dbus default
chroot ${CHROOT} rc-update add wpa_supplicant default
chroot ${CHROOT} rc-update add local default
chroot ${CHROOT} rc-update add dropbear default
chroot ${CHROOT} rc-update add networkmanager default

# pre-generate dropbear host keys so the first boot has none to create.
# dropbear installs its binaries under /usr/bin in Alpine, so locate it with
# command -v; on any failure dropbear's own init script regenerates the keys on
# first start (so a miss never aborts the build under set -e).
chroot ${CHROOT} sh -c '
    mkdir -p /etc/dropbear
    if command -v dropbearkey >/dev/null 2>&1; then
        dropbearkey -t rsa -s 2048     -f /etc/dropbear/dropbear_rsa_host_key      >/dev/null 2>&1 || true
        dropbearkey -t ed25519         -f /etc/dropbear/dropbear_ed25519_host_key  >/dev/null 2>&1 || true
    fi
'

# backup rootfs
rm -f alpine_rootfs.tgz
tar cpzf alpine_rootfs.tgz \
    --exclude="root/*" \
    --exclude="newroot" \
    --exclude="usr/bin/qemu-aarch64-static" \
    -C rootfs .