# pcDuino3B Armbian

面向 **LinkSprite pcDuino3B** 的独立 Armbian 镜像工程。正式镜像只由 GitHub Actions 构建，固定使用 Ubuntu 24.04 Noble、armhf 和 Armbian `current-sunxi` Linux 6.18.49 基线。

机器可读板型统一为 `pcduino3b`，默认主机名为 `pcduino3b`，设备树模型为 `LinkSprite pcDuino3B`。Release 镜像文件名必须包含 `Pcduino3b`。

## 下载与安装

从仓库的 **Releases** 下载已经通过镜像验收的 `*_Pcduino3b_*.img.xz` 及对应 SHA-256 文件。刷写、首次启动和实体板验收见 [安装文档](docs/INSTALL.md)。

候选镜像先作为 pre-release 上传；实体板验证的必须是该候选文件本身及其 SHA-256。正式发布只提升同一候选 Release，不重新构建或压缩。

## 独立板型、千兆网与板载 Wi-Fi

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

板载 2.4 GHz 802.11b/g/n Wi-Fi 走 A20 内部 USB。构建同时保证 `RTL8192CU`（RTL8188CUS，常见 USB ID `0bda:8176`）和 `RTL8XXXU`（RTL8188EUS，常见 USB ID `0bda:8179`）可用，并在镜像验收时检查两套模块、`armbian-firmware` 中的全部对应固件、`iw`、`wpa_supplicant`、regulatory database 和 NetworkManager。所有 profile 默认使用 NetworkManager，避免 Minimal recovery 镜像只能通过手工网络配置启用 Wi-Fi。当前实体板已确认 USB ID 为 `0bda:8179`，绑定内核自带的 `rtl8xxxu`，并成功扫描到无线网络。

`Linksprite_pcDuino3_defconfig`、`sun7i-a20-pcduino3.dts` 和 `linksprite,pcduino3` 仅作为 U-Boot、Linux 设备树的底层兼容实现；U-Boot 与 Linux 均由各自独立的 `sun7i-a20-pcduino3b.dts` 覆盖板级差异，它们不得成为镜像 hostname、Armbian `BOARD`、DT model、镜像名或 Release 产品名。

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
| `nand-installer` | 4GiB NAND 安装入口 | Minimal；基准 DTB + 固定布局 overlay；带显式安全门的安装器和 CI 生成的 raw FIT + SLC UBI bundle |
| `nand-recovery` | NAND 备份、恢复入口 | Minimal；基准 DTB + 无分区 recovery overlay；默认只读探测 |

NAND 命名保留为 `pcduino3b-nand-installer`、`pcduino3b-nand-recovery`、`pcduino3b-nand-rootfs`、`pcduino3b-nand-layout` 和 `pcduino3b-nand-boot.itb`。NAND 实验不进入普通 `sd-release` 镜像路径。

2026-09-04 正式 SD 镜像已在实体板通过 23 项自检：从 `/dev/mmcblk0p1` 启动，独立 DTB、身份、RTL8211E 千兆、DNS/APT、USB、I2C、SATA、SSH 和 NTP 均通过。普通 `sun7i-a20-pcduino3b.dtb` 继续把 NFC 设为 `disabled`。

实体板已读出完整 NAND ID `ad d7 94 91 60 44`，确认芯片为 Hynix `H27UBG8T2C`。原来的 4 KiB page / 128 B OOB 是通用 Hynix fallback 在 ONFI 参数页不可恢复时产生的错误解码；精确 ID 表修正后，Linux 实机成功枚举 `/dev/mtd0`，正确几何为 4 GiB、8 KiB page、640 B OOB、2 MiB eraseblock、40-bit/1 KiB ECC。隔离的 `sun7i-a20-pcduino3b-nand-recovery.dtb` 仍不声明分区，也不启用持久化 BBT。

需要快速生成探测卡时，`pcDuino3B fast NAND recovery repack` 工作流直接复用已经实机验收的正式 SD 镜像，保留原始普通 DTB，并让 U-Boot 在内存中应用经过预检的 NAND recovery overlay。2026-09-04 实机验证表明，主机构建工具预合成的 recovery DTB 无法正常启动，而“普通 DTB + U-Boot overlay”可正常进入 SSH。恢复镜像会禁止 `sunxi_nand` 在启动期间被 udev 自动加载；登录后再显式执行 `sudo modprobe sunxi_nand`。它不调用 Armbian 内核构建、不替换内核，也不改变普通 SD Release；输出仍作为独立的 NAND recovery 候选发布。

同日只读扫描确认 4 个已有坏块，位置为 `0xfe400000`、`0xfe600000`、`0xffc00000`、`0xffe00000`；除前约 28 MiB 的旧引导数据外，其余区域基本为空。已完成包含 OOB 的全盘原始备份，大小 `4,630,511,616` 字节，SHA-256 为 `42e946fff07ebbc0f1a3c4e84c14e99fd57566624b42042edc826c03efeab1d3`，并在独立主机副本上复核一致。

NAND installer 使用版本 2 布局：ECC 编码 SPL 主/备份分别位于 0 和 4 MiB，U-Boot proper 位于 8 MiB，32–128 MiB 是 U-Boot 可直接读取的 raw boot FIT，128 MiB 之后由 Linux 以 paired-page `slc-mode` 暴露为约 1984 MiB 逻辑 UBI `rootfs`。这是因为 Hynix MLC 原始分区会被 UBI 明确拒绝，而 U-Boot 又不能解释 Linux 的 SLC-on-MLC 映射。U-Boot 保持 microSD 优先；拔卡后读取并校验 FIT，再由 FIT 中的内核和运行时 DTB 挂载 SLC UBI。GitHub Actions 从已验收的 installer SD rootfs 生成 FIT、`pcduino3b-nand-rootfs.ubi` 和校验 bundle，安装器在任何擦除前核对板型、启动介质、精确 NAND ID/几何、SLC 标志、boot 区坏块、整包 SHA-256 和主机备份回执。代码和静态测试已就绪，但在同一 CI 候选尚未完成实体板写入/拔卡启动测试前，仍不宣称已经可从 NAND 启动。

## 板端验收

```bash
sudo pcduino3b-selftest
```

自检自动选择默认路由对应的有线接口（实机为 `end0`），检查四处身份、live DT、RTL8211E/Realtek PHY 绑定、千兆全双工、板载 Realtek Wi-Fi 驱动/固件/扫描、DNS、Ubuntu Noble HTTPS、APT、SATA、USB、I2C、SSH 和 NTP。核心结果应包括：

```text
[PASS] device tree model identifies LinkSprite pcDuino3B
[PASS] GMAC device tree uses rgmii-id
[PASS] RTL8211E PHY is bound
[PASS] Ethernet negotiated 1000Mb/s Full Duplex
[PASS] onboard Realtek Wi-Fi is bound to rtl8xxxu
[PASS] Wi-Fi scan completed
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
