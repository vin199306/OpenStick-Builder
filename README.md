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
- extract Qualcomm firmware

  copies the prebuilt bootloader and modem firmware from `prebuilt/sp970/` into the output
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
  | password | 12345678 |
  | ip addr | 192.168.4.1 |
  
  | usb0 | |
  | ----- | ---- |
  | ip addr | 192.168.5.1 |

- Default user
  
  | | |
  | ----- | ---- |
  | username | root |
  | password | password |

- This build is adapted for the **SP970** device (MSM8916). The kernel modules and WiFi firmware are extracted from the stock Debian rootfs and placed under `prebuilt/sp970/`. The `boot.img` is provided by the stock flashing package and must **not** be rebuilt.

- To maximize the `rootfs` partition
  ```shell
  resize2fs /dev/disk/by-partlabel/rootfs
  ```
