# pcDuino3B Armbian

面向 **LinkSprite pcDuino3B** 的独立 Armbian 镜像工程。正式镜像只由 GitHub Actions 构建，固定使用 Ubuntu 24.04 Noble、armhf 和 Armbian `current-sunxi` Linux 6.18.49 基线。

机器可读板型统一为 `pcduino3b`，默认主机名为 `pcduino3b`，设备树模型为 `LinkSprite pcDuino3B`。Release 镜像文件名必须包含 `Pcduino3b`。

## 下载与安装

从仓库的 **Releases** 下载已经通过镜像验收的 `*_Pcduino3b_*.img.xz` 及对应 SHA-256 文件。刷写、首次启动和实体板验收见 [安装文档](docs/INSTALL.md)。

候选镜像先作为 pre-release 上传；实体板验证的必须是该候选文件本身及其 SHA-256。正式发布只提升同一候选 Release，不重新构建或压缩。

## 独立板型与千兆网适配

本项目通过 `userpatches/config/boards/pcduino3b.csc` 注册独立板型，并生成、加载 `sun7i-a20-pcduino3b.dtb`。原版板型的设备树保持不变。

pcDuino3B 专用设备树以其上游 A20 板级定义为兼容基础，只表达已经过实体板验证的差异：

```dts
/ {
    model = "LinkSprite pcDuino3B";
};

&gmac {
    pinctrl-0 = <&gmac_rgmii_pins>;
    phy-mode = "rgmii-id";
};
```

内核配置保证 `STMMAC_ETH`、`STMMAC_PLATFORM`、`DWMAC_SUNXI` 和 `REALTEK_PHY` 可用。实体板基线为 `end0`、`st_gmac`、RTL8211E、1000Mb/s Full Duplex。

`Linksprite_pcDuino3_defconfig`、`sun7i-a20-pcduino3.dts` 和 `linksprite,pcduino3` 仅作为 U-Boot、Linux 设备树的底层兼容实现；它们不得成为镜像 hostname、Armbian `BOARD`、DT model、镜像名或 Release 产品名。

## 构建层次

- **Fast preflight**：语法、板型解析、DTS/DTB、身份 lint、自检夹具和 NAND 只读安全检查，不生成 rootfs 或镜像。
- **Image build**：显式选择 `dev`、`sd-release`、`nand-installer` 或 `nand-recovery` profile；软件包由 `packages/common.txt` 与对应 profile 清单统一汇总。
- **Release promotion**：只提升已上传、已记录 SHA-256、已在实体板验证的候选文件。

普通 README/文档修改不触发完整镜像构建。历史构建性能与每轮应记录的数据见 [BUILD-PERFORMANCE.md](BUILD-PERFORMANCE.md)。

## 镜像 profile

| Profile | 用途 | rootfs/压缩策略 |
| --- | --- | --- |
| `dev` | 快速网络、身份和板级验证 | Minimal；快速产物；不创建正式 Release |
| `sd-release` | 日常 microSD 系统 | 完整验收；xz；SHA-256 |
| `nand-installer` | 4GiB NAND 安装研究入口 | Minimal；当前仅接口和只读诊断，不具备写入授权 |
| `nand-recovery` | NAND 备份、恢复研究入口 | Minimal；当前仅接口和只读诊断，不具备写入授权 |

NAND 命名保留为 `pcduino3b-nand-installer`、`pcduino3b-nand-recovery`、`pcduino3b-nand-rootfs` 和 `pcduino3b-nand-layout`。NAND 实验不进入普通 `sd-release` 镜像路径。

当前实体板 `/proc/mtd` 为空，仅存在 `/dev/ubi_ctrl`，live DT 的 NFC 节点为 disabled。NAND profile 中的 `sudo pcduino3b-nand-probe` 只采集现状，普通 SD profile 不安装它；在芯片几何、ECC、坏块和完整备份得到验证前，输出会保持 `INSTALLER=NOT_AUTHORIZED`，仓库不提供可写安装器。

## 板端验收

```bash
sudo pcduino3b-selftest
```

自检自动选择默认路由对应的有线接口（实机为 `end0`），检查四处身份、live DT、RTL8211E/Realtek PHY 绑定、千兆全双工、DNS、Ubuntu Noble HTTPS、APT、SATA、USB、I2C、SSH 和 NTP。核心结果应包括：

```text
[PASS] device tree model identifies LinkSprite pcDuino3B
[PASS] GMAC device tree uses rgmii-id
[PASS] RTL8211E PHY is bound
[PASS] Ethernet negotiated 1000Mb/s Full Duplex
```

## 固定基线

- Board target：`pcduino3b`
- SoC family：Allwinner A20 / `sun7i`
- Architecture：`armhf`
- Userspace：Ubuntu 24.04 Noble
- Kernel：Armbian `current-sunxi` Linux 6.18.49
- Armbian build framework：`34e66c37211c70ef5cfad9c80dd76389720e19b7`

板型配置同时暴露 `legacy` 6.12、`current` 6.18、`edge` 7.1 三条内核线，并分别携带同源的专用 DT 补丁；自动发布基线只使用经过完整镜像验收的 `current` 6.18.49。

身份引用的逐项分类和允许边界见 [身份审计](docs/IDENTITY-AUDIT.md)。
