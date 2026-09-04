# pcDuino3B Armbian 安装与验收

本项目的日常系统是 **microSD 启动镜像**。先用 microSD 完成身份、千兆网络和外设回归；当前 NAND 状态尚不具备写入安装条件，不要覆盖板载 NAND。

## 1. 下载并核对候选文件

从仓库 **Releases** 下载：

- `*_Pcduino3b_*.img.xz`；
- 对应的 SHA-256 文件；
- 本轮 CI 验收和性能记录。

文件名必须包含 `Pcduino3b`。实体板验收前记录候选文件的校验值：

```bash
sha256sum -c Armbian_*_Pcduino3b_*.img.xz.sha
```

正式发布应提升这一份候选文件，不能重新构建或重新压缩。

## 2. 写入 microSD

推荐 8GB 或更大的可靠 microSD 卡。Windows/macOS 可用 Balena Etcher 或 Raspberry Pi Imager 直接写入 `.img.xz`。

Linux 下先用 `lsblk` 确认目标设备。以下 `/dev/sdX` 只是占位符，写错会破坏其它磁盘：

```bash
xz -dc Armbian_*_Pcduino3b_*.img.xz | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

## 3. 首次启动

1. pcDuino3B 断电并插入 microSD。
2. `end0` 网口接入千兆交换机/路由器，使用合格 Cat5e/Cat6 网线。
3. 建议连接 HDMI + 键盘或 3.3V TTL 串口（115200 8N1）。
4. 使用稳定的 5V 电源，开机后完成 Armbian 首次启动向导。

有线网络应通过 DHCP 获取地址，再通过 SSH 登录。

## 4. 身份验收

```bash
cat /etc/hostname
hostname
hostnamectl --static
grep -E '^(BOARD|BOARD_NAME)=' /etc/armbian-release
grep -E '^(BOARD|ARMBIAN_BOARD|ARMBIAN_FAMILY|UBUNTU_CODENAME)=' /etc/pcduino3b-build-info
tr -d '\0' </proc/device-tree/model; echo
grep -w pcduino3b /etc/hosts
```

期望值：

```text
hostname / hostnamectl: pcduino3b
BOARD=pcduino3b
BOARD_NAME=pcDuino3B
ARMBIAN_BOARD=pcduino3b
ARMBIAN_FAMILY=sunxi
UBUNTU_CODENAME=noble
DT model: LinkSprite pcDuino3B
127.0.1.1 pcduino3b
```

## 5. 一键实体板验收

```bash
sudo pcduino3b-selftest
```

自检通过默认 IPv4 路由自动识别有线接口，不假定接口名为 `eth0`。在当前实机上应识别 `end0`，并至少输出：

```text
[PASS] device tree model identifies LinkSprite pcDuino3B
[PASS] /etc/hostname is pcduino3b
[PASS] /etc/armbian-release BOARD is pcduino3b
[PASS] /etc/pcduino3b-build-info ARMBIAN_BOARD is pcduino3b
[PASS] GMAC device tree uses rgmii-id
[PASS] RTL8211E PHY is bound
[PASS] Ethernet negotiated 1000Mb/s Full Duplex
[PASS] DNS resolves ports.ubuntu.com
[PASS] HTTPS reaches Ubuntu Noble ARM archive
[PASS] apt-get update succeeds
```

脚本使用 `find -L` 读取 live device tree，因此 `/proc/device-tree` 是符号链接时也能找到 `phy-mode`。PHY 判断同时接受 sysfs Realtek driver、RTL8211 名称、ethtool/dmesg 证据和正常的 STMMAC PHY 绑定。

完整报告保存在 `/var/log/pcduino3b-selftest-YYYYMMDD-HHMMSS.log`。

## 6. 网络与外设回归

```bash
IFACE="$(ip -4 route show default | awk '{for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}')"
ip -br link show dev "$IFACE"
ethtool "$IFACE"
ethtool -i "$IFACE"
find -L /proc/device-tree -type f -name phy-mode \
  -exec sh -c 'tr -d "\0" < "$1"; echo' _ {} \;
apt-get update
systemctl --failed
lsusb
lsblk
```

实机基线应为 `end0`、`st_gmac`、RTL8211E、`rgmii-id`、1000Mb/s Full Duplex、Link detected yes。若只有 100Mb/s，先更换已验证的四对 Cat5e/Cat6 网线和千兆交换机端口。

吞吐测试可让局域网另一台机器运行 `iperf3 -s`，然后执行：

```bash
sudo pcduino3b-selftest --iperf-server 192.168.1.2
```

## 7. 启动排障

串口日志重点核对：

- U-Boot 从 microSD 载入；
- boot 配置加载 `sun7i-a20-pcduino3b.dtb`；
- DT model 是 `LinkSprite pcDuino3B`；
- `sun7i-dwmac` / `stmmac` 初始化，RTL8211E 位于已验证的 MDIO 地址；
- 根文件系统仍为 `/dev/mmcblk0p1` microSD ext4 分区。

## 8. NAND 只读研究边界

`nand-installer` 与 `nand-recovery` 是隔离的 Minimal profile 接口，不是已授权的写入工具。普通 `sd-release` 不包含 NAND 实验流程。

2026-09-04 实体板旧测试镜像的只读基线如下：

- live DT 中 `/soc/nand-controller@1c03000` 及 `nand@0` 的状态为 `okay`，片选和 ready/busy 均为 0，ECC mode 为 `hw`；
- 内核读到 Hynix `0xad:0xd7`，容量 4096 MiB、erase block 2048 KiB、page 4096 B、OOB 128 B；
- ONFI parameter page 的多数恢复失败，随后 `sunxi_nand` 初始化失败并返回 `-22`；
- `/proc/mtd` 没有设备，系统只有 `/dev/ubi_ctrl`，所以不存在可安全读取或写入的 raw MTD；
- raw NAND/sunxi NAND 驱动是模块，UBI/UBIFS 为 built-in。

这证明当前阻塞点已从“DT 节点未启用”推进到“NAND 参数/ECC 初始化失败”，但还不能据此确定唯一根因。旧测试镜像中的实验性 NAND DT 配置尚未纳入本仓库的普通 `sd-release`，不能把这次探测视为标准镜像已具备 NAND 支持。

`pcduino3b-nand-probe` 只安装到隔离的 NAND profile，普通 SD 镜像不携带 NAND 工具。用 NAND recovery 候选镜像启动后采集只读证据：

```bash
sudo pcduino3b-nand-probe
```

若 raw MTD 仍未枚举，脚本输出 `PROBE_STATUS=NOT_READY`、`INSTALLER=NOT_AUTHORIZED` 并以状态码 3 退出。这不是脚本故障，而是防止在芯片几何、ECC 参数、坏块、分区布局和可恢复备份均未确认前进入写入阶段的安全门。

NAND 研究产物统一命名为：

- `pcduino3b-nand-installer`
- `pcduino3b-nand-recovery`
- `pcduino3b-nand-rootfs`
- `pcduino3b-nand-layout`

旧厂商包名如需引用，只能放在明确标注的 legacy 研究资料中，不能作为当前系统身份。
