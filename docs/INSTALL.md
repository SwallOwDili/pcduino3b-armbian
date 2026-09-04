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

## 6. 板载 Wi-Fi

镜像同时携带 RTL8188CUS/RTL8188EUS 的主线内核驱动与固件。先确认 USB ID、驱动和扫描能力：

```bash
lsusb
iw dev
sudo iw dev "$(iw dev | awk '$1 == "Interface" { print $2; exit }')" scan | sed -n '1,80p'
dmesg | grep -Ei 'rtl8xxxu|rtl8192cu|8188(cu|eu)|firmware.*rtl'
```

常见结果是 `0bda:8176` 绑定 `rtl8192cu`，或 `0bda:8179` 绑定 `rtl8xxxu`。连接无线网络时使用交互式密码输入，避免密码进入 shell 历史：

```bash
sudo nmcli radio wifi on
sudo nmcli --ask device wifi connect "你的SSID"
nmcli -f DEVICE,TYPE,STATE,CONNECTION device
```

如果没有无线接口，先看 `lsusb` 是否出现 Realtek 设备，再检查 `dmesg` 是否报告 `rtl8192cufw*.bin` 或 `rtl8188eufw.bin` 缺失；不要直接安装来源不明的厂商 DKMS 驱动。

## 7. 网络与外设回归

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

## 8. 启动排障

串口日志重点核对：

- U-Boot 从 microSD 载入；
- boot 配置加载 `sun7i-a20-pcduino3b.dtb`；
- DT model 是 `LinkSprite pcDuino3B`；
- `sun7i-dwmac` / `stmmac` 初始化，RTL8211E 位于已验证的 MDIO 地址；
- 根文件系统仍为 `/dev/mmcblk0p1` microSD ext4 分区。

## 9. NAND 安装与恢复边界

`nand-installer` 与 `nand-recovery` 是相互隔离的 Minimal profile。三者都保留已经过实体板验收的 `sun7i-a20-pcduino3b.dtb`：普通 `sd-release` 不应用 NAND overlay；recovery 由 U-Boot 应用无分区的 `pcduino3b-nand-recovery.dtbo`；installer 应用固定布局的 `pcduino3b-nand-layout.dtbo`。不再把主机预合成 DTB 直接作为启动 DTB。

2026-09-04 实体板只读探测的最终基线如下：

- live DT 中 `/soc/nand-controller@1c03000` 及 `nand@0` 的状态为 `okay`，片选和 ready/busy 均为 0，ECC mode 为 `hw`；
- 完整 ID 为 `ad d7 94 91 60 44`，芯片是 Hynix `H27UBG8T2C`；
- ONFI parameter page 无法恢复，通用 Hynix fallback 会错误解码成 4 KiB page / 128 B OOB，并使 `sunxi_nand` 返回 `-22`；
- 增加精确 ID 表后，`/dev/mtd0` 已在实机枚举为 4096 MiB、8 KiB page、640 B OOB、2 MiB eraseblock、40-bit/1 KiB ECC；
- raw NAND/sunxi NAND 驱动是模块，UBI/UBIFS 为 built-in。

2026-09-04 当前镜像的实机复测进一步确认：

- 主机 `fdtoverlay` 预合成并直接选中的 recovery DTB 启动后网络不能保持在线；
- 保留已验收的普通 DTB、改由 U-Boot 应用同一 recovery overlay 后，系统可正常进入 SSH，live DT 中 NAND 状态为 `okay`，GMAC 仍为 `rgmii-id`；
- `modprobe.blacklist=sunxi_nand` 与 `/etc/modprobe.d` 黑名单均生效，启动期间没有自动探测；
- 登录后显式加载带精确 ID 的 NAND core 与 `sunxi_nand`，系统保持在线，`/proc/mtd` 和 sysfs 参数均符合 8 KiB / 640 B / 2 MiB / ECC40 的预期；
- 全盘抽样发现 4 个已有坏块：`0xfe400000`、`0xfe600000`、`0xffc00000`、`0xffe00000`；除前约 28 MiB 的旧引导内容外，其余区域基本为空；
- 已用 `nanddump --bb=dumpbad -n -o` 完成数据加 OOB 的全盘原始备份，文件大小为 `4,630,511,616` 字节，SHA-256 为 `42e946fff07ebbc0f1a3c4e84c14e99fd57566624b42042edc826c03efeab1d3`。

这证明内核侧 NAND 识别与 ECC 参数问题已经定位并修复。recovery overlay 只复现经过观测的 CS0、RB0 和硬件 ECC 配置；它不声明 NAND 分区，也不包含 `nand-on-flash-bbt`。普通 SD 镜像仍不受影响。

`pcduino3b-nand-probe` 只安装到隔离的 NAND profile，普通 SD 镜像不携带 NAND 工具。快速 recovery 镜像保留已经实机验收的普通 DTB，由 U-Boot 在启动内存中应用 `pcduino3b-nand-recovery.dtbo`；不要安装由主机 `fdtoverlay` 预合成的 DTB。NAND recovery 默认禁止 udev 在启动期间自动加载 `sunxi_nand`，确保网络和 SSH 先进入可观察状态。登录后先确认系统稳定，再显式加载驱动并采集只读证据：

```bash
sudo modprobe sunxi_nand
sudo pcduino3b-nand-probe
```

若 raw MTD 未枚举，脚本输出 `PROBE_STATUS=NOT_READY`、`INSTALLER=NOT_AUTHORIZED` 并以状态码 3 退出。即使 MTD 已枚举，探针也不会自动进入写入流程。

pcDuino3B 构建仍复用上游 `Linksprite_pcDuino3_defconfig`，但 U-Boot control DT 已独立为 `sun7i-a20-pcduino3b.dts`，运行时 model、RGMII-ID 与新增 NAND 节点均使用 3B 身份，原 `sun7i-a20-pcduino3.dts` 不被修改。NAND profile 会启用 sunxi NAND、MTD、UBI 和 UBIFS，并额外打包 `pcduino3b-nand-spl-with-ecc.bin` 与 `pcduino3b-nand-u-boot.bin`。前者是 Allwinner BROM 可直接读取的 ECC/randomizer 编码 SPL。U-Boot 的启动目标按 `microSD -> NAND UBI` 排列：插着 installer/recovery 卡时总是优先走救援系统；移除卡后才挂载 NAND 的 `ubi:rootfs` 并扫描 `/boot/boot.scr`。

固定布局版本 1 如下，所有边界均按 2 MiB eraseblock 对齐：

| 区域 | 起始 | 大小 | 写入方式 |
| --- | ---: | ---: | --- |
| `spl-primary` | `0x00000000` | 4 MiB | 预编码 data+OOB，raw/no-ECC |
| `spl-backup` | `0x00400000` | 4 MiB | 预编码 data+OOB，raw/no-ECC |
| `uboot` | `0x00800000` | 24 MiB 保留区 | Linux NAND ECC/randomizer；镜像最多 768 KiB |
| `ubi` | `0x02000000` | 4064 MiB | `ubiformat` 写入动态、自动扩容的 `rootfs` volume |

`image-build` 的 `nand-installer` profile 会同时生成 SD 候选镜像和 `pcduino3b-nand-installer-<run>.tar.zst`。后者包含 CI 从同一已验收 rootfs 生成的 `pcduino3b-nand-rootfs.ubi`、两段引导文件、layout overlay、安装器、manifest 和内部 `SHA256SUMS`。UBIFS 参数固定为 8192 B min-I/O、2080768 B LEB、最多 2032 LEB，压缩只使用 U-Boot 同样支持的 LZO/ZLIB 组合。

安装器不带参数运行时只检查并打印计划，不写 NAND：

```bash
sudo pcduino3b-nand-install --payload-dir /root/pcduino3b-nand-payload
```

实际写入必须同时满足：从 microSD 启动、profile 为 `nand-installer`、完整 NAND ID/几何正确、三个 boot 分区均无坏块、bundle 内部 SHA-256 全部通过、主机上的 data+OOB 备份 SHA-256 与已记录基线一致，并提供完整确认 token。当前实体板基线备份为：

```text
bytes  = 4630511616
sha256 = 42e946fff07ebbc0f1a3c4e84c14e99fd57566624b42042edc826c03efeab1d3
```

满足这些条件后使用：

```bash
sudo pcduino3b-nand-install \
  --install \
  --payload-dir /root/pcduino3b-nand-payload \
  --backup-sha256 42e946fff07ebbc0f1a3c4e84c14e99fd57566624b42042edc826c03efeab1d3 \
  --host-backup-confirmed \
  --confirm ERASE-PCDUINO3B-NAND-add794916044
```

写入顺序是 UBI rootfs、备用 SPL、U-Boot、主 SPL。每一步都在进入下一步前做读回比较；UBI 会重新挂载为只读并检查 Noble、`nand-rootfs` 身份、内核、initrd、boot script、DTB 与 overlay。脚本成功后不会自动重启，先保存 `/var/log/pcduino3b-nand-install-*.log`，再关机、拔出 microSD 并测试 NAND 启动。若失败，重新插入 recovery SD；不要在未确认日志和分区状态时重复整片擦除。

安装链路虽已实现并有静态/镜像验收门，但在 CI 产物写入这块实体板并完成拔卡启动、SSH、千兆网及 `pcduino3b-selftest` 之前，发布状态仍必须保持 `HARDWARE_ACCEPTANCE=PENDING`。

只为启动只读探测时，可用 `pcDuino3B fast NAND recovery repack` 工作流从已通过实体板验收的 SD Release 生成恢复卡。该路径复用原镜像和原内核，只把 recovery DTB、启动选择和探针加入镜像，避免为设备树探测重复完整内核编译。来源 Release 和 SHA-256 会写入候选镜像及验证报告。

NAND 研究产物统一命名为：

- `pcduino3b-nand-installer`
- `pcduino3b-nand-recovery`
- `pcduino3b-nand-rootfs`
- `pcduino3b-nand-layout`

旧厂商包名如需引用，只能放在明确标注的 legacy 研究资料中，不能作为当前系统身份。
