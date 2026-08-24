#!/bin/sh -e

export CHROOT=${CHROOT=$(pwd)/rootfs}
export HOST_NAME=${HOST_NAME=Alpine}
export DEVICE=${DEVICE=sp970}
export KERNEL_VERSION=${KERNEL_VERSION=7.0.0-lkiuyu-compile+}
export RELEASE=${RELEASE=v3.24}
export PMOS_RELEASE=${PMOS_RELEASE=v25.12}
export MIRROR=${MIRROR=http://dl-cdn.alpinelinux.org/alpine}
export PMOS_MIRROR=${PMOS_MIRROR=http://mirror.postmarketos.org/postmarketos}
export APK_STATIC_URL=https://gitlab.alpinelinux.org/api/v4/projects/5/packages/generic/v3.0.6/x86_64/apk.static

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
    dbus \
    e2fsprogs-extra \
    eudev \
    gadget-tool \
    iptables \
    modemmanager \
    msm-firmware-loader@pmos \
    openrc \
    openssh \
    rmtfs \
    shadow \
    sudo \
    udev-init-scripts \
    udev-init-scripts-openrc \
    wireguard-tools \
    wireguard-tools-wg-quick \
    wireless-regdb \
    zram-init \
    iw

# clear
rm /etc/fstab
"

# extract NetworkManager from previous alpine version (v3.20)
scripts/extract_networkmanager.sh

# copy kernel modules and firmware
mkdir -p ${CHROOT}/lib/modules ${CHROOT}/lib/firmware
cp -a prebuilt/${DEVICE}/lib/modules/${KERNEL_VERSION} ${CHROOT}/lib/modules/
cp -a prebuilt/${DEVICE}/lib/firmware/* ${CHROOT}/lib/firmware/

# setup alpine
chroot ${CHROOT} ash -l -c "
echo 'root:password' | chpasswd
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
rc-update add sshd default
rc-update add rmtfs default
rc-update add modemmanager default
rc-update add networkmanager default
rc-update add networkmanager-dispatcher default
rc-update add wpa_supplicant default
rc-update add local default
rc-update add zram-init boot
"
echo 'user ALL=(ALL:ALL) NOPASSWD: ALL' > ${CHROOT}/etc/sudoers.d/user

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

# setup SSH
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' ${CHROOT}/etc/ssh/sshd_config
cp prebuilt/${DEVICE}/ssh/ssh_host_* ${CHROOT}/etc/ssh/
chmod 0600 ${CHROOT}/etc/ssh/ssh_host_*_key

# setup modules auto-load
echo 'qcom_wcnss_pil' > ${CHROOT}/etc/modules-load.d/wcnss.conf
echo 'cpufreq_ondemand' > ${CHROOT}/etc/modules-load.d/cpufreq.conf

# setup local.d scripts
mkdir -p ${CHROOT}/etc/local.d
cat << 'EOF' > ${CHROOT}/etc/local.d/resize-rootfs.start
#!/bin/sh
ROOT_DEV=$(awk '$2 == "/" {print $1}' /proc/mounts)
resize2fs ${ROOT_DEV}
EOF
chmod +x ${CHROOT}/etc/local.d/resize-rootfs.start

cat << 'EOF' > ${CHROOT}/etc/local.d/cpufreq.start
#!/bin/sh
echo ondemand > /sys/devices/system/cpu/cpufreq/policy0/scaling_governor
echo 75 > /sys/devices/system/cpu/cpufreq/ondemand/up_threshold
echo 20000 > /sys/devices/system/cpu/cpufreq/ondemand/sampling_rate
echo 4 > /sys/devices/system/cpu/cpufreq/ondemand/sampling_down_factor
EOF
chmod +x ${CHROOT}/etc/local.d/cpufreq.start

# setup zram
cat << EOF > ${CHROOT}/etc/conf.d/zram-init
load_on_start=yes
unload_on_stop=yes
num_devices=1
type0=swap
size0=256
algo0=zstd
EOF

# setup NetworkManager
cp configs/*.nmconnection ${CHROOT}/usr/local/etc/NetworkManager/system-connections
chmod 0600 ${CHROOT}/usr/local/etc/NetworkManager/system-connections/*
ln -s ../usr/local/etc/NetworkManager ${CHROOT}/etc/NetworkManager

mkdir -p ${CHROOT}/boot/extlinux
cp configs/extlinux.conf ${CHROOT}/boot/extlinux

# copy custom dtb's
mkdir -p ${CHROOT}/boot/dtbs/qcom
cp dtbs/* ${CHROOT}/boot/dtbs/qcom

# copy gadget-tool templates and script
cp -a configs/templates ${CHROOT}/etc/gt
cp scripts/setup_ncm_gadget.sh ${CHROOT}/usr/local/bin

# compile and install reboot helper (reboot bootloader / reboot edl)
aarch64-linux-gnu-gcc -static -O2 -o ${CHROOT}/usr/local/bin/reboot scripts/reboot-helper.c

# cleanup to reduce rootfs size
rm -rf ${CHROOT}/var/cache/apk/*
rm -rf ${CHROOT}/var/log/*
rm -rf ${CHROOT}/tmp/*
rm -rf ${CHROOT}/root/.cache
rm -f ${CHROOT}/root/.ash_history

# backup rootfs
rm -f alpine_rootfs.tgz
tar cpzf alpine_rootfs.tgz \
    --exclude="root/*" \
    --exclude="newroot" \
    --exclude="usr/bin/qemu-aarch64-static" \
    -C rootfs .
