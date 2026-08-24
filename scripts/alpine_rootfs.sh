#!/bin/sh -e

export CHROOT=${CHROOT=$(pwd)/rootfs}
export HOST_NAME=${HOST_NAME=OpenStick}
export ROOT_PASSWORD=${ROOT_PASSWORD=password}
export RELEASE=${RELEASE=v3.24}
export PMOS_RELEASE=${PMOS_RELEASE=v25.12}
export MIRROR=${MIRROR=http://dl-cdn.alpinelinux.org/alpine}
export PMOS_MIRROR=${PMOS_MIRROR=http://mirror.postmarketos.org/postmarketos}
export APK_STATIC_URL=https://gitlab.alpinelinux.org/api/v4/projects/5/packages/generic/v3.0.6/x86_64/apk.static

DEVICE=${DEVICE=SP970V11}
PREBUILT=${PREBUILT=$(pwd)/prebuilt/${DEVICE}}
KVER=$(ls ${PREBUILT}/lib/modules/)

rm -rf ${CHROOT}

mkdir -p ${CHROOT}/etc/apk
cat << EOF >  ${CHROOT}/etc/apk/repositories
${MIRROR}/${RELEASE}/main
${MIRROR}/${RELEASE}/community
@pmos ${PMOS_MIRROR}/${PMOS_RELEASE}
EOF

cp /etc/resolv.conf ${CHROOT}/etc/

mkdir -p ${CHROOT}/usr/bin
cp $(which qemu-aarch64-static) ${CHROOT}/usr/bin

[ -e apk.static ] || wget ${APK_STATIC_URL}; chmod a+x apk.static

./apk.static add -p ${CHROOT} --initdb -U --arch aarch64 --allow-untrusted alpine-base

# install apps
chroot ${CHROOT} ash -l -c "
apk add --allow-untrusted postmarketos-keys@pmos
apk add \
    bridge-utils \
    chrony \
    dropbear \
    openssh-sftp-server \
    dbus \
    e2fsprogs-extra \
    eudev \
    gadget-tool \
    iptables \
    msm-firmware-loader@pmos \
    openrc \
    rmtfs \
    shadow \
    sudo \
    udev-init-scripts \
    udev-init-scripts-openrc \
    wireguard-tools \
    wireguard-tools-wg-quick \
    wireless-regdb \
    iw

# modem runtime libraries (the ModemManager binary itself comes from the
# build/modem-stage.tar.gz built by scripts/build_modem_host.sh)
apk add \
    libqmi \
    libqmi-utils \
    libmbim \
    libmbim-utils \
    libgudev \
    libqrtr-glib \
    qrtr \
    polkit

# clear
rm /etc/fstab
"

# extract NetworkManager from previous alpine version (v3.20)
sh scripts/extract_networkmanager.sh

# setup alpine
chroot ${CHROOT} ash -l -c "
echo user:1::::/home/user:/bin/ash | newusers

# update users used by chrooted apps
addgroup -S dnsmasq
adduser -S -D -H -h /dev/null -s /sbin/nologin -G dnsmasq -g dnsmasq dnsmasq

# sync
ln /etc/group    /usr/local/etc
ln /etc/passwd   /usr/local/etc
ln /etc/hostname /usr/local/etc

ln -sf /usr/local/etc/resolv.conf /etc

# add symlinks
for a in nm-online nmcli nmtui nmtui-connect nmtui-edit nmtui-hostname; do
    ln -s /usr/local/bin/chroot.sh /usr/bin/\${a};
done

rc-update add devfs sysinit
rc-update add dmesg sysinit
rc-update add udev sysinit
rc-update add udev-trigger sysinit
rc-update add udev-settle sysinit
rc-update add udev-postmount default
rc-update add hwclock boot
rc-update add modules boot
rc-update add sysctl boot
rc-update add hostname boot
rc-update add bootmisc boot
rc-update add mount-ro shutdown
rc-update add killprocs shutdown
rc-update add savecache shutdown
rc-update add dropbear default
rc-update add rmtfs default
rc-update add networkmanager default
rc-update add networkmanager-dispatcher default
rc-update add wpa_supplicant default
rc-update add chronyd default
rc-update add local default
"
echo 'user ALL=(ALL:ALL) NOPASSWD: ALL' > ${CHROOT}/etc/sudoers.d/user

# root password
chroot ${CHROOT} ash -l -c "echo 'root:${ROOT_PASSWORD}' | chpasswd"

# reboot bootloader / reboot edl support
# busybox reboot cannot pass a restart reason to the bootloader. The static
# reboot-ctrl helper is built on the BUILD HOST by scripts/build_modem_host.sh
# (into build/modem-stage.tar.gz) and shipped in the stage; only the /sbin/reboot
# PATH-precedence wrapper is created here.
cat << 'EOF' > ${CHROOT}/usr/local/bin/reboot
#!/bin/sh
case "$1" in
    bootloader|edl)
        exec /usr/local/bin/reboot-ctrl "$1"
        ;;
    *)
        exec /sbin/reboot "$@"
        ;;
esac
EOF
chmod +x ${CHROOT}/usr/local/bin/reboot

# configure chrony with domestic NTP servers (device clock resets to 1970 without RTC,
# causing TLS cert verification failures; default config already has makestep 1.0 3 + rtcsync)
sed -i 's|^pool pool.ntp.org iburst|server ntp.aliyun.com iburst\nserver ntp.tencent.com iburst\nserver cn.pool.ntp.org iburst|' ${CHROOT}/etc/chrony/chrony.conf

# add udev rules
cat << EOF > ${CHROOT}/etc/udev/rules.d/10-udc.rules
ACTION=="add", SUBSYSTEM=="udc", RUN+="/sbin/modprobe libcomposite", RUN+="/usr/local/bin/setup_ncm_gadget.sh"
EOF

cat << EOF > ${CHROOT}/etc/udev/rules.d/99-nm-usb0.rules
SUBSYSTEM=="net", ACTION=="add|change|move", ENV{DEVTYPE}=="gadget", ENV{NM_UNMANAGED}="0"
EOF

# enable autologin on console
sed -i '/^tty/ s/^/#/' ${CHROOT}/etc/inittab
echo 'ttyMSM0::respawn:/bin/sh' >> ${CHROOT}/etc/inittab

echo ${HOST_NAME} > ${CHROOT}/etc/hostname
sed -i "/localhost/ s/$/ ${HOST_NAME}/" ${CHROOT}/etc/hosts

# setup NetworkManager
cp configs/*.nmconnection ${CHROOT}/usr/local/etc/NetworkManager/system-connections
chmod 0600 ${CHROOT}/usr/local/etc/NetworkManager/system-connections/*
ln -s ../usr/local/etc/NetworkManager ${CHROOT}/etc/NetworkManager

# update fstab
echo "configfs\t/sys/kernel/config\tconfigfs\tnodev,noexec,nosuid\t0 0" >> ${CHROOT}/etc/fstab

# copy gadget-tool templates and script
cp -a configs/templates ${CHROOT}/etc/gt
cp scripts/setup_ncm_gadget.sh ${CHROOT}/usr/local/bin

# install kernel modules and wifi firmware from the flashing package
mkdir -p ${CHROOT}/lib/modules ${CHROOT}/lib/firmware
cp -a ${PREBUILT}/lib/modules/. ${CHROOT}/lib/modules/
cp -a ${PREBUILT}/lib/firmware/. ${CHROOT}/lib/firmware/

# rebuild module dependency db inside the chroot
chroot ${CHROOT} ash -l -c "depmod -a ${KVER}"

# kernel module autoload: wcnss (wifi) and cpufreq_ondemand
printf 'qcom_wcnss_pil\n'  > ${CHROOT}/etc/modules-load.d/wcnss.conf
printf 'cpufreq_ondemand\n' > ${CHROOT}/etc/modules-load.d/cpufreq.conf

# kernel module autoload: MSM8916 modem stack (QRTR core is built into the
# kernel; load the QMI ctrl port, data path and modem remoteproc driver)
printf 'rpmsg_wwan_ctrl\n' > ${CHROOT}/etc/modules-load.d/modem.conf
printf 'qcom_bam_dmux\n'   >> ${CHROOT}/etc/modules-load.d/modem.conf
printf 'qcom_common\n'     >> ${CHROOT}/etc/modules-load.d/modem.conf
printf 'qcom_pil_info\n'   >> ${CHROOT}/etc/modules-load.d/modem.conf
printf 'qcom_q6v5\n'       >> ${CHROOT}/etc/modules-load.d/modem.conf
printf 'qcom_q6v5_mss\n'   >> ${CHROOT}/etc/modules-load.d/modem.conf

# first boot: resize rootfs to fill the partition
mkdir -p ${CHROOT}/etc/local.d
cat << 'EOF' > ${CHROOT}/etc/local.d/resize-rootfs.start
#!/bin/sh
ROOT_DEV=$(awk '$2 == "/" {print $1}' /proc/mounts)
resize2fs ${ROOT_DEV}
EOF
chmod +x ${CHROOT}/etc/local.d/resize-rootfs.start

# cpu frequency scaling: ondemand governor
cat << 'EOF' > ${CHROOT}/etc/local.d/cpufreq.start
#!/bin/sh
echo ondemand > /sys/devices/system/cpu/cpufreq/policy0/scaling_governor
echo 75 > /sys/devices/system/cpu/cpufreq/ondemand/up_threshold
echo 20000 > /sys/devices/system/cpu/cpufreq/ondemand/sampling_rate
echo 4 > /sys/devices/system/cpu/cpufreq/ondemand/sampling_down_factor
EOF
chmod +x ${CHROOT}/etc/local.d/cpufreq.start

# install the modem stack: ModemManager (patched), qrtr-ns and reboot-ctrl are
# built on the BUILD HOST by scripts/build_modem_host.sh (into
# build/modem-stage.tar.gz), so nothing here compiles inside the image chroot.
if [ ! -f build/modem-stage.tar.gz ]; then
    echo "error: build/modem-stage.tar.gz missing - run scripts/build_modem_host.sh first" >&2
    exit 1
fi
tar -xzf build/modem-stage.tar.gz -C ${CHROOT}

# sim-init.sh: plain POSIX sh (ash) - activate the GW provisioning session so
# the USIM app becomes 'ready' (qmicli, from libqmi-utils, is the only tool)
cat > ${CHROOT}/usr/local/bin/sim-init.sh << 'SHEEOF'
#!/bin/sh
# Activate the primary GW provisioning session so the USIM app becomes 'ready'.
# Some firmware (e.g. MSM8916 SP970) does not auto-activate it, leaving the USIM
# in 'detected' state which ModemManager treats as "SIM not ready".

QMI_PORT=/dev/wwan0qmi0

# wait for the QMI control port
i=0
while [ "$i" -lt 30 ]; do
    [ -e "$QMI_PORT" ] && break
    sleep 1
    i=$((i+1))
done
[ -e "$QMI_PORT" ] || { echo "sim-init: $QMI_PORT not found"; exit 1; }

# wait for the QMI service to be responsive
i=0
while [ "$i" -lt 15 ]; do
    if qmicli -d "$QMI_PORT" --dms-get-ids >/dev/null 2>&1; then
        break
    fi
    sleep 1
    i=$((i+1))
done
if ! qmicli -d "$QMI_PORT" --dms-get-ids >/dev/null 2>&1; then
    echo "sim-init: QMI service not responsive"
    exit 1
fi

# skip if a primary GW provisioning session already exists
out=$(qmicli -d "$QMI_PORT" --uim-get-card-status 2>&1) || true
case "$out" in
    *"Primary GW:"*)
        case "$out" in
            *"session doesn't exist"*) ;;
            *) echo "sim-init: provisioning session already active"; exit 0 ;;
        esac ;;
esac

# determine the USIM AID from the card status output
aid=$(printf '%s\n' "$out" | awk '
    /Application type:/ { want = (tolower($0) ~ /(usim|sim)/) ? 1 : 0; next }
    want && /Application ID:/ {
        v = $0; sub(/^.*Application ID:[[:space:]]*/, "", v)
        if (v ~ /^[0-9A-Fa-f][0-9A-Fa-f](:[0-9A-Fa-f][0-9A-Fa-f])+/) { print v; exit }
        getline; sub(/^[[:space:]]*/, "")
        if ($0 ~ /^[0-9A-Fa-f][0-9A-Fa-f](:[0-9A-Fa-f][0-9A-Fa-f])+/) { print $0; exit }
    }
')
if [ -z "$aid" ]; then
    echo "sim-init: could not determine USIM AID"
    exit 1
fi

echo "sim-init: activating provisioning session with AID $aid"
if ! qmicli -d "$QMI_PORT" \
    --uim-change-provisioning-session \
    "session-type=primary-gw-provisioning,activate=yes,slot=1,aid=$aid" >/dev/null 2>&1; then
    echo "sim-init: provisioning session activation failed"
    exit 1
fi

sleep 2
out=$(qmicli -d "$QMI_PORT" --uim-get-card-status 2>&1) || true
case "$out" in
    *"ready"*) echo "sim-init: USIM ready" ;;
    *) echo "sim-init: activated but USIM not ready yet" ;;
esac
exit 0
SHEEOF
chmod +x ${CHROOT}/usr/local/bin/sim-init.sh

# OpenRC services: qrtr-ns (QRTR name service), sim-init (GW provisioning), modemmanager
cat > ${CHROOT}/etc/init.d/qrtr-ns << 'EOF'
#!/sbin/openrc-run
description="QRTR name service daemon"
command="/usr/local/bin/qrtr-ns"
command_background="yes"
pidfile="/run/qrtr-ns.pid"
depend() {
    need rmtfs
    after modules
}
EOF
chmod +x ${CHROOT}/etc/init.d/qrtr-ns

cat > ${CHROOT}/etc/init.d/sim-init << 'EOF'
#!/sbin/openrc-run
description="Activate USIM GW provisioning session before ModemManager"
command="/usr/local/bin/sim-init.sh"
depend() {
    need rmtfs qrtr-ns
}
EOF
chmod +x ${CHROOT}/etc/init.d/sim-init

cat > ${CHROOT}/etc/init.d/modemmanager << 'EOF'
#!/sbin/openrc-run
description="ModemManager mobile broadband management daemon"
command="/usr/sbin/ModemManager"
command_background="yes"
command_user="root"
pidfile="/run/ModemManager.pid"
depend() {
    need rmtfs qrtr-ns
    want sim-init
    after dbus
}
EOF
chmod +x ${CHROOT}/etc/init.d/modemmanager

# ModemManager does not self-daemonize, so OpenRC backgrounds it above. The
# stage's DBus service file would also let DBus auto-spawn a second instance
# (service-name conflict) - disable it.
MM_DBUS=${CHROOT}/usr/share/dbus-1/system-services/org.freedesktop.ModemManager1.service
if [ -f "${MM_DBUS}" ]; then
    mv "${MM_DBUS}" "${MM_DBUS}.disabled"
fi

# register modem services for auto-start at boot
chroot ${CHROOT} ash -l -c "
rc-update add qrtr-ns default
rc-update add sim-init default
rc-update add modemmanager default
"

# backup rootfs
rm -f alpine_rootfs.tgz
tar cpzf alpine_rootfs.tgz \
    --exclude="root/*" \
    --exclude="newroot" \
    --exclude="usr/bin/qemu-aarch64-static" \
    -C rootfs .
