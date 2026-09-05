# pcDuino3B identity audit

## 范围与方法

审计基线为 `5ef1ee111cddd8681a7746efc8de01710bdb4a45`。扫描覆盖版本库全部受控文件与 workflow，排除 `.git/`，使用大小写敏感和不敏感两轮搜索：

```bash
rg -n -i --hidden --glob '!.git/**' \
  'pcduino3 nano|pcduino3b|pcduino3|hostname|BOARD=|BOARD_NAME=|ARMBIAN_BOARD=|model[[:space:]]*=|compatible[[:space:]]*=|armbian_board:|BOOT_FDT_FILE|fdtfile|sun7i-a20-pcduino3|Linksprite_pcDuino3_defconfig|nano' .
```

不能用全局字符串替换：独立产品身份、Armbian slug、Linux DT 兼容基础和 U-Boot defconfig 属于不同层，错误替换底层兼容名会破坏构建或驱动匹配。

## 分类规则

1. **最终用户可见身份**：标题、Release 名、镜像名、hostname、`/etc/armbian-release`、build-info、DT model 和安装输出。
2. **Armbian 内部板型标识**：`BOARD=pcduino3b`、`armbian_board: pcduino3b`、board 配置、扩展名和 profile。
3. **上游兼容实现**：Linux `sun7i` family、被 include 的原始 DTS、已注册 DT compatible fallback 和上游 Makefile 上下文。
4. **U-Boot 内部兼容配置**：`Linksprite_pcDuino3_defconfig` 及共享 A20/DRAM 启动实现。
5. **历史资料或旧 NAND 包名称**：只允许存在于明确标注的 legacy/审计说明中，不代表当前产品。
6. **应删除的错误引用**：会把构建目标、镜像、运行系统或当前板级硬件错误标识为旧板型/Nano 的引用。

## 基线命中与处置

| 文件/位置 | 基线命中 | 分类 | 判断与处置 |
| --- | --- | ---: | --- |
| `.github/workflows/build.yml` 名称、group、tag、title、报告 | `pcDuino3B` / `pcduino3b` | 1 | 产品名正确，保留并拆分到分层 workflow。 |
| `.github/workflows/build.yml` build input | `armbian_board: pcduino3` | 6 | 构建出的 `/etc/armbian-release` 和文件名泄漏旧 slug；改为独立 `pcduino3b`。 |
| `.github/workflows/build.yml` patch/DTB 验收 | `sun7i-a20-pcduino3.dts/.dtb` | 6 | 把原 DT 当作 3B 成品；改验独立 `sun7i-a20-pcduino3b.dtb`，同时断言原 DT 未被改成 RGMII-ID。 |
| `.github/workflows/build.yml` release body | `pcDuino3 boot target` | 6 | 用户可见发布说明泄漏旧产品名；删除。 |
| `README.md` 标题、命令 | `pcDuino3B` / `pcduino3b-*` | 1 | 当前产品身份，保留。 |
| `README.md` 构建基线 | `Board target: Armbian pcduino3` | 6 | 改为 `pcduino3b`。 |
| `README.md` 上游说明 | `sun7i-a20-pcduino3.dts` / 原版 pcDuino3 | 3 | 只有明确说明“上游兼容基础、非产品身份”时允许。 |
| `docs/INSTALL.md` 旧 DTB/排障 | `sun7i-a20-pcduino3.dtb`、`eth0` | 6 | 改为独立 DTB，并按默认路由自动发现实机 `end0`。 |
| `userpatches/customize-image.sh` target/build-info | `BOARD=pcduino3`、`ARMBIAN_BOARD=pcduino3` | 6 | 拒绝旧 target；统一为 `pcduino3b`，同时从构建源写 hostname/hosts。 |
| 旧 kernel patch 的目标与说明 | 修改 `sun7i-a20-pcduino3.dts` | 6 | 删除对原 DTS 的行为修改；新增专用 DTS/DTB。 |
| 旧 kernel patch 的说明 | `GMAC wiring matches pcDuino3 Nano` | 6 | 无原理图/官方资料支撑且把 Nano 混入当前硬件说明；删除，改用实体板 RTL8211E/千兆验证事实。 |
| `userpatches/extensions/pcduino3b-gigabit.sh` | `pcduino3b` / `sunxi` | 2 | 当前板扩展与 family，保留。 |
| `userpatches/overlay/.../pcduino3b-selftest` | `pcduino3b` | 1、2 | 命令名和验收身份，保留；补齐 hostname、Armbian board、build-info、DT model 检查。 |

基线仓库没有独立 board 配置，因此 `BOARD_NAME=pcDuino3B`、`BOOT_FDT_FILE=...pcduino3b.dtb`、当前产品 `model = "LinkSprite pcDuino3B"` 均缺失；这是“未命中但必须补齐”的身份缺口。

## 整改后允许引用清单

同一搜索表达式仍作为发现入口，但不再记录总命中行数或逐文件行数。该数字会随补丁上下文、测试 fixture 和 workflow 验收语句正常波动，不能证明身份正确，也不适合作为防漏扫门槛。实际门槛是下表的路径/语义分类，以及 `scripts/check-pcduino3b-identity.sh` 的可执行 allow/deny 规则。

| 文件 | 分类 | 说明 |
| --- | --- | --- |
| `.github/workflows/image-build.yml` | 1、2、3、4 | 当前 board/artifact/镜像验收与隔离 NAND bundle；生成 v2 布局的 raw boot FIT 和 SLC-emulated UBI rootfs；原板 DT 只用于无污染回归，旧 U-Boot 名只作内部兼容。 |
| `.github/workflows/nand-recovery-repack.yml` | 1、2、3 | 当前 recovery 候选、运行时 overlay 与基准 DTB；不会改变当前产品身份。 |
| `.github/workflows/preflight.yml` | 1、2、3、4 | 三条内核线的板型解析、专用 DTB、`dist6` pairing、v2 NAND layout、FIT 与 U-Boot 内部兼容验收。 |
| `.github/workflows/release-promotion.yml` | 1、2 | 当前候选 tag、实体板、NAND bundle 摘要和发布身份。 |
| `README.md` | 1、2、3、4 | 当前用户身份、Wi-Fi/NAND 状态、v2 NAND 启动架构及明确标注的底层兼容说明。 |
| `docs/INSTALL.md` | 1、2、3、4、5 | 当前 SD/NAND 安装和验收身份；解释 raw MLC 被 UBI 拒绝、paired-page SLC emulation 与 raw FIT 的边界；旧包只作 legacy 边界说明。 |
| `BUILD-PERFORMANCE.md` | 1、2 | 当前项目、profile 和 cache key。 |
| `packages/common.txt` | 1 | 注释中的当前展示名称；其它清单无被审计名称。 |
| `userpatches/config/boards/pcduino3b.csc` | 2、3、4 | 当前 board/DTB、sun7i family、共享 U-Boot defconfig、独立 3B control DT，以及 NAND profile 的 FIT/raw NAND 配置。 |
| `userpatches/customize-image.sh` | 1、2 | 构建 target、hostname、hosts、build-info、Wi-Fi/NAND profile。 |
| `userpatches/dts/sun7i-a20-pcduino3b-nand-recovery.dtso` | 2、3 | 当前板只读 recovery overlay；只描述已验证的 NAND 控制器、RB 和 ECC，不声明持久分区。 |
| `userpatches/dts/sun7i-a20-pcduino3b-nand-layout.dtso` | 2、3 | 当前板 v2 installer layout：`spl-primary`、`spl-backup`、`uboot`、`bootfit`、`rootfs`；仅 rootfs 带 `slc-mode`。 |
| `userpatches/extensions/pcduino3b-gigabit.sh` | 2 | 当前板专用扩展、Wi-Fi 保证、profile 后缀及 NAND U-Boot 产物名。 |
| 三条 `0001` kernel patches | 1、2、3 | 6.12、6.18、7.1 三条内核线的同源专用 DTS/model/DTB；原 DTS、compatible、Nano DTB 行只是 include/说明/Makefile 上下文。 |
| 三条 `0002` kernel patches | 2、3 | 6.12、6.18、7.1 均为实机 H27UBG8T2CTR-BC 增加精确 ID、`dist6_pairing_scheme` 并绑定 SLC emulation；不生成旧板身份。 |
| `userpatches/pcduino3b-nand-boot.its` | 1、2、3 | 当前板 raw NAND 启动 FIT 模板，封装内核、gzip initramfs 和专用 runtime DTB，并对三者启用 SHA-256；`linksprite,pcduino3` 仅是已注册的兼容链。 |
| `userpatches/u-boot/**` | 2、3、4 | 只对 pcduino3b board patch 目录生效；新增独立 `sun7i-a20-pcduino3b.dts`、3B 前缀 NAND 节点和 v2 分区，只把上游 pcDuino3 defconfig/DTS 作为兼容基础。 |
| `pcduino3b-selftest` | 1、2 | 当前运行身份及其严格期望值。 |
| `pcduino3b-nand-probe` | 1、2、3 | 当前工具名；`compatible` 仅为只读 DT 字段输出。 |
| `pcduino3b-nand-install` 与 `nand-layout.env` | 1、2、3 | 当前板 v2 固定 NAND 几何、raw boot FIT、SLC-emulated rootfs、备份凭证和多重写前安全门。 |
| `scripts/check-pcduino3b-identity.sh` | 1～6 | 身份 allow/deny、三内核线、U-Boot control DT 与 NAND v2 overlay 一致性规则本身，不生成产品身份。 |
| `tests/test-pcduino3b-selftest.sh` | 1、2 | 当前身份 fixture，并覆盖实机缺失 PHY name 文件的场景。 |
| `tests/test-pcduino3b-nand-probe.sh` | 1、2 | 当前工具、精确 NAND 几何与隔离测试 fixture。 |
| `tests/test-pcduino3b-nand-installer.sh` | 1、2、3 | v2 固定布局、SLC 标志、FIT、备份、安全确认、写入顺序与禁止整片写入 fixture。 |
| `tests/test-pcduino3b-nand-uboot-config.sh` | 2、3、4 | 独立 3B control DT、raw NAND/FIT 配置、v2 分区、SD 优先与固定 FIT 读取路径 fixture。 |
| `tests/test-pcduino3b-nand-boot-fit.sh` | 1、2、3、4 | FIT 三组件/hash、内存区间、64 MiB 上限、runtime DT 的 `slc-mode`/自动 UBI 绑定及候选摘要 fixture。 |
| `tests/test-pcduino3b-nand-pairing.sh` | 2、3 | 用数据手册固定页对验证 `dist6` 映射，并穷举 256 个物理页的双向映射；同时要求三条内核线均携带该 scheme。 |
| `tests/test-pcduino3b-profile-suffix.sh` | 1、2 | 当前 profile、软件包注入与 NAND 文件名隔离 fixture。 |
| `tests/test-pcduino3b-wifi-config.sh` | 1、2 | 当前板 Wi-Fi 驱动、固件和 NetworkManager 策略 fixture。 |

| 路径 | 允许名称 | 分类 | 边界 |
| --- | --- | ---: | --- |
| `README.md`、`docs/INSTALL.md` | `pcDuino3B`、`pcduino3b`、`Pcduino3b` | 1 | 产品名、slug、镜像文件名大小写分别固定。旧名仅可出现在明确的兼容解释。 |
| `BUILD-PERFORMANCE.md` | `pcDuino3B`、`pcduino3b` | 1、2 | 记录当前产品与 cache key；历史 run 的错误名只能作为已标注的基线证据。 |
| `userpatches/config/boards/pcduino3b.csc` | `BOARD_NAME="pcDuino3B"`、`BOOT_FDT_FILE=...pcduino3b.dtb` | 2 | 决定 Armbian slug、用户可见名称和正式 DTB。 |
| 同一 board 文件 | `BOARDFAMILY="sun7i"` | 3 | 上游 Allwinner A20 family，不能改成产品名。 |
| 同一 board 文件 | `BOOTCONFIG="Linksprite_pcDuino3_defconfig"` | 4 | 允许复用的 U-Boot 内部配置，不能泄漏成产品身份。 |
| 同一 board 文件 | `CONFIG_DEFAULT_DEVICE_TREE/CONFIG_OF_LIST="sun7i-a20-pcduino3b"` | 2 | 即使复用上游 defconfig，U-Boot 运行时也必须选择独立 3B control DT。 |
| kernel patch 新 DTS | `#include "sun7i-a20-pcduino3.dts"`、`linksprite,pcduino3` fallback | 3 | 上游兼容基础；原 DTS 保持原行为。 |
| kernel patch 新 DTS | `model = "LinkSprite pcDuino3B"`、`sun7i-a20-pcduino3b.dtb` | 1、2 | 当前板唯一最终 model/DTB。 |
| kernel patch Makefile 上下文 | `sun7i-a20-pcduino3-nano.dtb` | 3 | 只是上游 Makefile 相邻条目，不代表当前板；不可用于当前 boot 选择。 |
| `.github/workflows/image-build.yml` | `BOARD: pcduino3b`、compile `BOARD="$BOARD"`、`Pcduino3b` artifact | 1、2 | 当前 workflow 直接调用固定 Armbian `compile.sh`，因为固定 composite Action 会在构建后立即发布，无法实现 `publish=false` 和“先验收再上传”。CLI 的正式等价入口明确传 `BOARD=pcduino3b`，并由 `config-dump-json` 与镜像内 `BOARD` 双重验收；若改回 Action wrapper，其 `armbian_board` 同样必须为 `pcduino3b`。 |
| preflight/image acceptance 的原板回归项 | `sun7i-a20-pcduino3.dtb`、`model = "LinkSprite pcDuino3"`、`phy-mode = "mii"` | 3 | 只用于证明原板 DTS 未受 3B patch 污染；不得作为当前镜像 boot DTB。 |
| `userpatches/customize-image.sh` | hostname、`BOARD=pcDuino3B`、`ARMBIAN_BOARD=pcduino3b` | 1、2 | 生成时落盘，不依赖启动后手工修复。 |
| overlay 工具和 `tests/` | `pcduino3b-*`、期望身份值 | 1、2 | 当前命令/fixture；不得接受旧 slug 作为 PASS。 |
| `userpatches/overlay/usr/share/pcduino3b/nand-layout.env` | `PCDUINO3B_NAND_LAYOUT_VERSION=2`、`bootfit`、`rootfs` | 2、3 | v2 固定把 32–128 MiB 留给 U-Boot 可读的 raw FIT，从 128 MiB 起仅由 Linux 以 paired-page `slc-mode` 暴露约一半逻辑容量。 |
| `userpatches/pcduino3b-nand-boot.its` | `pcDuino3B`、`pcduino3b-nand-runtime.dtb`、`linksprite,pcduino3` | 1、2、3 | FIT 的 description/runtime DTB 必须使用 3B 身份；compatible 继续使用内核已注册的上游 fallback，不虚构新绑定。 |
| 三条 `0002` kernel patches | `H27UBG8T2CTR-BC`、`dist6_pairing_scheme` | 3 | 芯片型号和 paired-page 算法是底层实现事实，不是板型展示名；6.12、6.18、7.1 必须同步。 |
| `packages/*.txt` | `pcDuino3B`（注释）与 profile 名 | 1、2 | 软件集由 profile 隔离；NAND 包不散入 SD profile。 |
| legacy/审计说明 | `pcDuino3 Nano`、历史旧包名 | 5 | 必须同时出现“历史/legacy/非当前身份”的限定。当前仓库没有需要保留的旧包实体。 |
| 本审计文件 | 被审计的全部拼写与变量名 | 5 | 仅用于列举规则、基线证据和禁用示例，不参与产品身份生成。 |

## 指定名称逐项结论

| 搜索项 | 结论 |
| --- | --- |
| `pcduino3b` | 机器可读 slug，允许用于 board/profile/hostname/命令和文件路径。 |
| `pcDuino3B` | 唯一展示名称，允许用于 UI、DT model、`BOARD_NAME` 和 build-info `BOARD`。 |
| `Pcduino3b` | 仅用于 Armbian 生成的镜像文件名大小写形式。 |
| `pcduino3` / `pcDuino3` | 仅允许在上游 DTS compatible/include 或清晰的兼容说明中；不得作为当前 target/hostname/model/artifact。 |
| `Pcduino3` | 当前产品配置/产物名不允许；原板 DT 回归测试中的 model 为分类 3，历史错误产物名为分类 6。 |
| `pcduino3 nano` / `pcDuino3 Nano` / `nano` | 仅 legacy 历史说明或上游 Makefile 条目允许；当前硬件断言、变量和普通安装说明禁用。 |
| `hostname` | 用户可见身份；最终值严格为 `pcduino3b`，`/etc/hosts` 同步。 |
| `BOARD=` | `/etc/armbian-release` 必须为 `pcduino3b`；build-info 的展示字段 `BOARD=pcDuino3B`。 |
| `BOARD_NAME=` | 必须为 `pcDuino3B`。 |
| `ARMBIAN_BOARD=` | 必须为 `pcduino3b`。 |
| `model =` | 专用 DT 的最终值必须为 `LinkSprite pcDuino3B`。 |
| `compatible =` | 新 DTS 继承已注册的上游兼容链，不虚构未注册的 3B compatible。 |
| `armbian_board:` | 基线 Action wrapper 的旧值为分类 6；当前 direct-compile workflow 等价传入 `BOARD=pcduino3b`，若再使用 wrapper 必须传 `pcduino3b`。 |
| `BOOT_FDT_FILE` | board 配置必须选择 `allwinner/sun7i-a20-pcduino3b.dtb`。 |
| `fdtfile` | 正式 board 配置生成独立基准 DTB；NAND workflow 只把它规范化为同一基准值并追加经 CI 编译/合成验收的 profile overlay。 |
| `sun7i-a20-pcduino3` | 带 `b` 的 DTB 是当前成品；不带 `b` 的 DTS 仅为上游 include/兼容验证。 |
| `Linksprite_pcDuino3_defconfig` | 分类 4，允许作为 U-Boot 内部兼容配置。 |

## 验收门

整改完成后 identity lint 应至少拒绝：workflow 使用旧 board target、build-info 的旧 `ARMBIAN_BOARD`、旧 DTB 作为启动文件、原 DTS 被补成 RGMII-ID、当前硬件说明出现 Nano 类比、用户可见文件把当前产品称为旧板型，以及 NAND v2 overlay 缺少 `bootfit`/`rootfs` 或 `slc-mode`。允许列表必须按路径和语义匹配，不能简单禁止所有 `pcduino3` 子串。

NAND 架构的补充验收由专门 fixture 承担：pairing 测试要求 6.12、6.18、7.1 三条补丁都实现并绑定 `dist6_pairing_scheme`；FIT 测试要求模板的内核、initramfs、runtime DTB 和 SHA-256 完整，且自动 UBI 绑定只进入 FIT 内的 runtime DTB，不得提前进入 installer overlay。精确命中行数不再作为 PASS 条件。
