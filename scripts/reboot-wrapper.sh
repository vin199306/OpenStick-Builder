#!/bin/sh
# reboot wrapper: support 'reboot bootloader' and 'reboot edl'
# on MSM8916 the reboot reason is set via the reboot-mode sysfs
# (mainline reboot-mode framework), then a normal reboot applies it.
mode=""
case "$1" in
    bootloader|fastboot) mode=bootloader ;;
    edl|dload)           mode=edl ;;
esac
if [ -n "$mode" ]; then
    if [ -w "/sys/reboot-mode/$mode" ]; then
        echo 1 > "/sys/reboot-mode/$mode"
    elif [ -w /sys/power/reboot_reason ]; then
        echo "$mode" > /sys/power/reboot_reason
    fi
    shift
fi
exec /sbin/reboot "$@"
