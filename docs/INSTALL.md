# pcDuino3B Armbian 安装与验收

本项目提供的是 **microSD 启动镜像**。建议先通过 microSD 完整验证系统、千兆网口、SATA/USB 等功能，再考虑其它启动介质。不要先覆盖板载 NAND。

## 1. 下载刷机包

进入仓库的 **Releases**，打开标签 `pcduino3b-noble-current`，下载：

- `*.img.xz`：刷机镜像（推荐下载这个）
- 对应的 `*.sha`：Armbian 生成的校验文件
- `CI-VERIFICATION.txt`：本次镜像的 CI 验收记录

Release 只有通过下列 CI 检查后才会从 pre-release 提升为正式 release：

- Linux v6.18 pcDuino3 DTS 补丁可以干净应用；
- Armbian 完整编译成功；
- Ubuntu Noble 构建阶段 `apt-get update` 成功；
- `ports.ubuntu.com` Noble `InRelease` DNS/HTTPS 可访问；
- 生成镜像可挂载；
- 镜像内确实是 Ubuntu Noble；
- 生成 DTB 中 `phy-mode = "rgmii-id"`；
- 内核配置中 `STMMAC_ETH`、`STMMAC_PLATFORM`、`DWMAC_SUNXI`、`REALTEK_PHY` 均为 built-in；
- 板端自检脚本已经写入镜像。

> CI 能验证“驱动、设备树、内核配置、rootfs 与软件源配置正确且可构建”，但无法替代真实 pcDuino3B 物理网口。1000BASE-T 协商必须在板子接入千兆交换机/路由器并使用 Cat5e 或更好网线后验收。

## 2. 写入 microSD

推荐 8GB 或更大的可靠 microSD 卡。

### Windows / macOS

使用 Balena Etcher 或 Raspberry Pi Imager，直接选择下载的 `.img.xz`，选择 microSD，开始写入。软件支持直接解压 `.xz`，不需要手工解压。

### Linux

先确认 SD 卡设备，例如 `/dev/sdX`，**不要写错系统盘**：

```bash
lsblk
```

解压并写盘：

```bash
xz -dc Armbian_*.img.xz | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

写完后安全弹出 microSD。

## 3. 首次启动

1. pcDuino3B 断电。
2. 插入写好的 microSD。
3. 千兆网口接到支持 1000BASE-T 的交换机/路由器，使用 Cat5e/Cat6 网线。
4. 建议首次启动同时接 HDMI + 键盘，或接 3.3V TTL 串口以便看到完整启动日志。
5. 使用稳定的 5V 电源供电。
6. 按 Armbian 首次启动向导设置 root 密码和普通用户。

有线网络默认应通过 DHCP 获取地址。可在路由器 DHCP 客户端列表中找到设备地址，然后通过 SSH 登录。

## 4. 一键板端验收

登录后执行：

```bash
sudo pcduino3b-selftest
```

重点应看到：

```text
[PASS] GMAC device tree uses rgmii-id
[PASS] Ethernet carrier is up
[PASS] Ethernet negotiated 1000Mb/s Full Duplex
[PASS] Realtek PHY driver is bound
[PASS] DNS resolves ports.ubuntu.com
[PASS] HTTPS reaches Ubuntu Noble ARM archive
[PASS] apt-get update succeeds
```

完整报告保存在：

```text
/var/log/pcduino3b-selftest-YYYYMMDD-HHMMSS.log
```

如网口只显示 `100Mb/s`，先换一根已确认可跑千兆的 Cat5e/Cat6 网线、换千兆交换机端口，再重测。1000M 协商依赖四对线全部正常，线材问题最常见。

## 5. 千兆吞吐测试

`ethtool` 显示 1000Mb/s 只说明链路已经按千兆协商。要验证实际 TCP 吞吐，局域网另一台千兆设备先运行：

```bash
iperf3 -s
```

pcDuino3B 上运行：

```bash
sudo pcduino3b-selftest --iperf-server 192.168.1.2
```

或直接：

```bash
iperf3 -c 192.168.1.2 -P 4 -t 30
```

A20 的 CPU、内存和协议栈会让实际 TCP 吞吐低于 1Gbit/s 物理线速，因此验收时应把“链路是否 1000Mb/s”与“业务吞吐多少”分开看。

## 6. 常用排障命令

```bash
ip -br addr
ip route
ethtool eth0
ethtool -i eth0
dmesg | grep -Ei 'sun7i-dwmac|stmmac|RTL821|Link is Up'
lsblk
lsusb
systemctl --failed
apt-get update
```

如果接口名不是 `eth0`，用 `ip -br link` 查看实际名称。

## 7. 串口启动日志

如果系统无法正常进入用户空间，优先收集串口日志。A20/U-Boot 与内核控制台通常为 115200 8N1。务必使用 **3.3V TTL** 串口，不要使用 RS-232 电平。

把从 U-Boot 开始到故障点的完整日志保存下来，尤其关注：

- U-Boot 是否从 microSD 载入；
- `sun7i-a20-pcduino3.dtb` 是否被加载；
- `sun7i-dwmac` / `stmmac` 初始化；
- PHY 地址、PHY 型号与 `rgmii-id`；
- DHCP、rootfs 挂载和 systemd 失败单元。
