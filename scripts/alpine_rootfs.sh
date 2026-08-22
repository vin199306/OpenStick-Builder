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
rc-update add local default
"
echo 'user ALL=(ALL:ALL) NOPASSWD: ALL' > ${CHROOT}/etc/sudoers.d/user

# root password
chroot ${CHROOT} ash -l -c "echo 'root:${ROOT_PASSWORD}' | chpasswd"

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

# pre-generate dropbear host keys
mkdir -p ${CHROOT}/etc/dropbear
chroot ${CHROOT} ash -l -c "
dropbearkey -t rsa -s 2048 -f /etc/dropbear/dropbear_rsa_host_key
dropbearkey -t ecdsa -s 256 -f /etc/dropbear/dropbear_ecdsa_host_key
dropbearkey -t ed25519 -f /etc/dropbear/dropbear_ed25519_host_key
"

# backup rootfs
rm -f alpine_rootfs.tgz
tar cpzf alpine_rootfs.tgz \
    --exclude="root/*" \
    --exclude="newroot" \
    --exclude="usr/bin/qemu-aarch64-static" \
    -C rootfs .
