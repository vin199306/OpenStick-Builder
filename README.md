# OpenStick-Builder-alpine (SP970V11)

为 **SP970V11**（MSM8916 平台 4G 上网棒）构建 Alpine Linux 根文件系统镜像。

本分支与上游不同：**不编译内核、不生成 boot.img**。内核和 boot.img 直接使用
刷机包（Debian 一键刷机包）里的原始文件，本仓库只构建 `rootfs.img`。

## 方案说明

- 内核：刷机包自带的 `boot-sp970.img`（`7.0.0-lkiuyu-compile+`），**原样使用，绝不修改**
- 内核模块：从刷机包 `rootfs.img` 提取，存放在 `prebuilt/SP970V11/lib/modules/7.0.0-lkiuyu-compile+/`
- WiFi 固件：从刷机包 `rootfs.img` 提取，存放在 `prebuilt/SP970V11/lib/firmware/`
- 底层固件：`prebuilt/SP970V11/aboot.mbn`（刷机包附带，刷机时单独写入 aboot 分区）

## 系统配置

| 项目 | 值 |
| ---- | ---- |
| 主机名 | `OpenStick` |
| root 密码 | `password` |
| SSH | dropbear，host keys 构建时预生成 |
| USB 网络 | NCM gadget，VID `1d6b` / PID `0104`，`192.168.5.1/24` shared |
| WiFi 热点 | SSID `Openstick`，密码 `12345678`，`192.168.4.1/24` shared |
| CPU 调频 | ondemand governor（up_threshold 75 / sampling_rate 20000） |
| 首次启动 | 自动 `resize2fs` 扩容 rootfs 分区 |
| 其他 | zram 由内核模块提供，无 ModemManager（不插 SIM） |

## 构建

### GitHub Actions

1. Fork 本仓库
2. 运行 **Build SP970V11 Alpine** workflow
3. 下载 artifact `SP970V11-alpine`，其中包含 `SP970V11-alpine-rootfs.img`

### 本地构建（Ubuntu 22.04+）

```shell
git clone -b alpine --recurse-submodules <repo-url>
cd OpenStick-Builder-alpine/
sudo ./build.sh
```

产物在 `files/SP970V11-alpine-rootfs.img`。

## 刷机

> [!WARNING]
> 刷机有变砖风险，请先备份原厂固件，谨慎操作！

1. 用刷机包自带的 `aboot.mbn` 更新 aboot 分区（旧版 aboot 有 bug，刷新内核会砖）
2. 用刷机包自带的 `boot-sp970.img` 刷 boot 分区
3. 用本仓库构建的 `SP970V11-alpine-rootfs.img` 刷 rootfs 分区

```shell
fastboot flash aboot aboot.mbn
fastboot flash boot boot-sp970.img
fastboot flash rootfs SP970V11-alpine-rootfs.img
fastboot reboot
```

## 目录结构

```
prebuilt/SP970V11/            # 从刷机包提取的预编译文件
├── aboot.mbn                 # 新版 aboot（备用）
└── lib/
    ├── modules/7.0.0-lkiuyu-compile+/   # 内核模块
    └── firmware/             # WiFi 固件（wcnss、mba、wlan/prima、qcom/a300、venus-1.8）
scripts/
├── alpine_rootfs.sh          # 构建 Alpine rootfs
├── build_images.sh           # 打包 512MB ext4 sparse rootfs 镜像
├── install_deps.sh           # 安装构建依赖
└── ...
```
