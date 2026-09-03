# pcDuino3B Armbian

面向 **LinkSprite pcDuino3B** 的可直接刷写 Armbian 镜像工程。镜像在 GitHub Actions 云端构建，使用 Ubuntu 24.04 Noble armhf 用户空间和 Armbian `current-sunxi` 内核线；不要求使用者在本地编译。

## 下载

打开本仓库 **Releases**，下载 `pcduino3b-noble-current` 发行版中的 `*.img.xz`。

完整刷机、首次启动、千兆网口验收和排障步骤见：[docs/INSTALL.md](docs/INSTALL.md)。

## pcDuino3B 的关键适配

pcDuino3B 与原 pcDuino3 的关键差异是千兆以太网。上游 `sun7i-a20-pcduino3.dts` 描述的是原版 pcDuino3 的 MII/100M 接法，因此本项目在 Armbian 内核构建时应用 3B 专用补丁：

```dts
&gmac {
    pinctrl-names = "default";
    pinctrl-0 = <&gmac_rgmii_pins>;
    phy-handle = <&phy1>;
    phy-mode = "rgmii-id";
    status = "okay";
};
```

同时强制把以下驱动编入内核，而不是依赖模块自动加载：

```text
CONFIG_STMMAC_ETH=y
CONFIG_STMMAC_PLATFORM=y
CONFIG_DWMAC_SUNXI=y
CONFIG_REALTEK_PHY=y
```

## 发布前自动验证

GitHub Actions 分为两层：

1. **Static preflight**：对 Linux v6.18 上游 DTS 实际执行 `git apply --check`，并校验定制脚本。
2. **Cloud build and image acceptance**：使用固定的 Armbian build commit 完整编译，然后挂载生成的 `.img`，反编译镜像内 DTB，检查 Noble rootfs、内核配置、`rgmii-id` 和自检脚本。镜像构建过程中还会执行 `apt-get update` 和 Ubuntu ARM archive HTTPS 探测。

发行版先以 pre-release 创建；只有 post-build acceptance 全部通过后，工作流才会上传 `CI-VERIFICATION.txt` 并提升为正式 release。

## 板端最终验收

CI 没有真实的 pcDuino3B 物理 RJ45 端口，因此不会虚构“硬件已跑到 1000M”。实际板子启动后执行：

```bash
sudo pcduino3b-selftest
```

脚本会检查实时 Device Tree、GMAC/PHY 驱动、`ethtool` 链路速率/双工、默认路由、DNS、Ubuntu Noble HTTPS、`apt-get update`、SATA/USB/MMC、SSH、NTP 和 systemd 状态。

接入千兆交换机/路由器及合格 Cat5e/Cat6 网线时，核心验收项应为：

```text
[PASS] Ethernet negotiated 1000Mb/s Full Duplex
```

如局域网有另一台运行 `iperf3 -s` 的主机，还可以执行：

```bash
sudo pcduino3b-selftest --iperf-server <服务器IP>
```

## 构建基线

- Board target: Armbian `pcduino3`
- SoC family: Allwinner A20 / `sun7i`
- Architecture: `armhf`
- Userspace: Ubuntu 24.04 Noble
- Kernel: Armbian `current`, pinned build framework currently selects Linux 6.18.y
- Armbian build framework pin: `34e66c37211c70ef5cfad9c80dd76389720e19b7`
- Output: raw `.img` + compressed `.img.xz` + checksums + CI verification report

## 目录

```text
.github/workflows/build.yml
userpatches/kernel/archive/sunxi-6.18/0001-arm-dts-sun7i-a20-pcduino3b-gigabit.patch
userpatches/extensions/pcduino3b-gigabit.sh
userpatches/customize-image.sh
userpatches/overlay/usr/local/sbin/pcduino3b-selftest
docs/INSTALL.md
```
