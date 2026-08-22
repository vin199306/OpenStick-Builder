# OpenStick Image Builder
Image builder for MSM8916 based 4G modem dongles

This builder uses the precompiled [kernel](https://pkgs.postmarketos.org/package/v24.06/postmarketos/aarch64/linux-postmarketos-qcom-msm8916) provided by [postmarketOS](https://postmarketos.org/) for Qualcomm MSM8916 devices.

> [!NOTE]
> This branch generates an `alpine` image, use the [main branch](https://github.com/kinsamanka/OpenStick-Builder/tree/main) for a `debian` image.

## Build Instructions
### Build locally
This has been tested to work on **Ubuntu 22.04**
- clone
  ```shell
  git clone -b alpine --recurse-submodules https://github.com/kinsamanka/OpenStick-Builder.git
  cd OpenStick-Builder/
  ```
#### Quick
- build
  ```shell
  cd OpenStick-Builder/
  sudo ./build.sh
  ```
#### Detailed
- install dependencies
  ```shell
  sudo scripts/install_deps.sh
  ```
- build hyp and lk2nd

  these custom bootloader allows basic support for `extlinux.conf` file, similar to u-boot and depthcharge.
  ```shell
  sudo scripts/build_hyp_aboot.sh
  ```
- extract Qualcomm firmware

  extracts the bootloader and creates a new partition table that utilizes the full emmc space
  ```shell
  sudo scripts/extract_fw.sh
  ```
- create rootfs
  ```shell
  sudo scripts/alpine_rootfs.sh
  ```
- create images
  ```shell
  sudo scripts/build_images.sh
  ```

The generated firmware files will be stored under the `files` directory

### On the cloud using Github Actions
1. Fork this repo
2. Run the [Build workflow](../../actions/workflows/build.yml)
   - click and run ***Run workflow***
   - once the workflow is done, click on the workflow summary and then download the resulting artifact

## Customizations
Edit [`scripts/alpine_rootfs.sh`](scripts/alpine_rootfs.sh#L33) to add/remove packages.

## SP970V11: Build a Latest Mainline Kernel Alpine Image
This builder also ships a second workflow that compiles the **latest
msm8916-mainline kernel** (instead of reusing the stock kernel) and packages a
new `boot.img` for the **SP970V11** device.

### What it produces
- `boot.img` — mainline kernel (`Image.gz` + SP970V11 device tree), packed in
  the Android boot image format the stock aboot loads (pagesize 2048,
  base 0x80000000, offsets identical to the original boot.img).
- `SP970V11-alpine-rootfs.img` — Alpine rootfs (label `rootfs`, 512MiB sparse
  ext4, auto-resized on first boot) with the freshly built kernel modules.
- `aboot.bin`, `gpt_both0.bin`, `hyp.mbn`, `rpm.mbn`, `sbl1.mbn`, `tz.mbn` —
  unchanged bootloader / partition firmware from the flashing package.

### How to trigger
1. Fork this repo.
2. Run the [Build SP970V11 workflow](../../actions/workflows/build-sp970v11.yml).
3. Pick the kernel branch (default `wip/msm8916/7.2-rc1`, the latest
   msm8916-mainline development branch).
4. Download the release assets and flash with the device's flashing package
   script (replace its `boot.img` and `rootfs.img`).

### Key files
| File | Purpose |
| ---- | ------- |
| `dtbs/msm8916-gexing-sp970v11.dts` | SP970V11 board device tree (GPIO layout) |
| `dtbs/msm8916-sp970.dtsi` | shared SP970 base device tree (UART, eMMC, WiFi) |
| `configs/kernel-sp970v11.config` | kernel feature fragment (zram, USB NCM, WireGuard, …) |
| `scripts/build_kernel_sp970v11.sh` | compile kernel + dtb + modules, pack boot.img |
| `scripts/alpine_rootfs_sp970v11.sh` | build Alpine rootfs with the new kernel modules |

> [!NOTE]
> The stock-kernel build (`build.yml` / `scripts/alpine_rootfs.sh`) keeps using
> the original `boot.img` from the flashing package; only the SP970V11 workflow
> replaces `boot.img` with the mainline kernel build.

## Firmware Installation
> [!WARNING]  
> The following commands can potentially brick your device, making it unbootable. Proceed with caution and at your own risk!

> [!IMPORTANT]  
> Make sure to perform a backup of the original firmware using the command `edl rf orig_fw.bin`

### Prerequisites
- [EDL](https://github.com/bkerler/ed)
- Android fastboot tool
  ```
  sudo apt install fastboot
  ```

### Steps
- Enter Qualcom EDL mode using this [guide](https://wiki.postmarketos.org/wiki/Zhihe_series_LTE_dongles_(generic-zhihe)#How_to_enter_flash_mode)
- Backup required partitions

  The following files are required from the original firmware:
  
     - `fsc.bin`
     - `fsg.bin`
     - `modem.bin`
     - `modemst1.bin`
     - `modemst2.bin`
     - `persist.bin`
     - `sec.bin`

  Skip this step if these files are already present
  ```shell
  for n in fsc fsg modem modemst1 modemst2 persist sec; do
      edl r ${n} ${n}.bin
  done
  ```
- Install `aboot`
  ```shell
  edl w aboot aboot.mbn
  ```
- Reboot to fastboot
  ```shell
  edl e boot
  edl reset
  ```
- Flash firmware
  ```shell
  fastboot flash partition gpt_both0.bin
  fastboot flash aboot aboot.mbn
  fastboot flash hyp hyp.mbn
  fastboot flash rpm rpm.mbn
  fastboot flash sbl1 sbl1.mbn
  fastboot flash tz tz.mbn
  fastboot flash boot boot.bin
  fastboot flash rootfs alpine_rootfs.bin
  ```
- Restore original partitions
  ```shell
  for n in fsc fsg modem modemst1 modemst2 persist sec; do
      fastboot flash ${n} ${n}.bin
  done
  ```
- Reboot
  ```shell
  fastboot reboot
  ```

## Post-Install
- Network configuration
  
  | wlan0 | |
  | ----- | ---- |
  | ssid | Openstick |
  | password | openstick |
  | ip addr | 192.168.4.1 |

  | usb0 | |
  | ----- | ---- |
  | ip addr | 192.168.5.1 |

- Default user
  
  | | |
  | ----- | ---- |
  | username | user |
  | password | 1 |
 
- If your device is not based on **UZ801**, modify `/boot/extlinux/extlinux.conf` to use the correct devicetree
  ```shell
  sed -i 's/yiming-uz801v3/<BOARD>/' /boot/extlinux/extlinux.conf
  ```

  where `<BOARD>` is
     - `thwc-uf896` for **UF896** boards
     - `thwc-ufi001c` for **UFIxxx** boards
     - `jz01-45-v33` for **JZxxx** boards
     - `fy-mf800` for **MF800** boards

- To maximize the `rootfs` partition
  ```shell
  resize2fs /dev/disk/by-partlabel/rootfs
  ```
