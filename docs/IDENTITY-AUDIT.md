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

整改后同一表达式（排除本报告自身）共返回 328 行。以下按文件聚合，每个命中都落入对应行的分类；数字用于防止漏扫新文件，并不把同一行内的多个关键词重复计数。

| 文件 | 命中行 | 分类 | 说明 |
| --- | ---: | --- | --- |
| `.github/workflows/image-build.yml` | 43 | 1、2、3 | 当前 board/artifact/验收身份；原板 DT 只用于无污染回归。 |
| `.github/workflows/preflight.yml` | 37 | 1、2、3、4 | 三条内核线的板型解析与 current DTB；原 DTS/defconfig 是兼容验收。 |
| `.github/workflows/release-promotion.yml` | 6 | 1、2 | 当前候选 tag、实体板和发布身份。 |
| `README.md` | 13 | 1、2、3、4 | 当前用户身份及明确标注的底层兼容说明。 |
| `docs/INSTALL.md` | 32 | 1、2、5 | 当前安装/验收身份；旧包只作 legacy 边界说明。 |
| `BUILD-PERFORMANCE.md` | 4 | 1、2 | 当前项目和 cache key。 |
| `packages/common.txt` | 1 | 1 | 注释中的当前展示名称；其它清单无被审计名称。 |
| `userpatches/config/boards/pcduino3b.csc` | 6 | 2、3、4 | 当前 board/DTB、sun7i family、共享 U-Boot defconfig。 |
| `userpatches/customize-image.sh` | 18 | 1、2 | 构建 target、hostname、hosts、build-info 与 profile。 |
| `userpatches/extensions/pcduino3b-gigabit.sh` | 5 | 2 | 当前板专用扩展名和隔离的 NAND 文件名后缀。 |
| `sunxi-6.12`、`sunxi-6.18`、`sunxi-7.1` kernel patches | 54 | 1、2、3 | 三条内核线的同源新 DTS/model/DTB；原 DTS、compatible、Nano DTB 行只是 include/说明/Makefile 上下文。 |
| `pcduino3b-selftest` | 41 | 1、2 | 当前运行身份及其严格期望值。 |
| `pcduino3b-nand-probe` | 9 | 1、2、3 | 当前工具名；`compatible` 仅为只读 DT 字段输出。 |
| `scripts/check-pcduino3b-identity.sh` | 28 | 1～6 | 身份 allow/deny、三内核线一致性规则本身，不生成产品身份。 |
| `tests/test-pcduino3b-selftest.sh` | 19 | 1、2 | 当前身份 fixture。 |
| `tests/test-pcduino3b-nand-probe.sh` | 7 | 1、2 | 当前工具与隔离测试 fixture。 |
| `tests/test-pcduino3b-profile-suffix.sh` | 5 | 1、2 | 当前 profile 与 NAND 文件名隔离 fixture。 |

| 路径 | 允许名称 | 分类 | 边界 |
| --- | --- | ---: | --- |
| `README.md`、`docs/INSTALL.md` | `pcDuino3B`、`pcduino3b`、`Pcduino3b` | 1 | 产品名、slug、镜像文件名大小写分别固定。旧名仅可出现在明确的兼容解释。 |
| `BUILD-PERFORMANCE.md` | `pcDuino3B`、`pcduino3b` | 1、2 | 记录当前产品与 cache key；历史 run 的错误名只能作为已标注的基线证据。 |
| `userpatches/config/boards/pcduino3b.csc` | `BOARD_NAME="pcDuino3B"`、`BOOT_FDT_FILE=...pcduino3b.dtb` | 2 | 决定 Armbian slug、用户可见名称和正式 DTB。 |
| 同一 board 文件 | `BOARDFAMILY="sun7i"` | 3 | 上游 Allwinner A20 family，不能改成产品名。 |
| 同一 board 文件 | `BOOTCONFIG="Linksprite_pcDuino3_defconfig"` | 4 | 允许复用的 U-Boot 内部配置，不能泄漏成产品身份。 |
| kernel patch 新 DTS | `#include "sun7i-a20-pcduino3.dts"`、`linksprite,pcduino3` fallback | 3 | 上游兼容基础；原 DTS 保持原行为。 |
| kernel patch 新 DTS | `model = "LinkSprite pcDuino3B"`、`sun7i-a20-pcduino3b.dtb` | 1、2 | 当前板唯一最终 model/DTB。 |
| kernel patch Makefile 上下文 | `sun7i-a20-pcduino3-nano.dtb` | 3 | 只是上游 Makefile 相邻条目，不代表当前板；不可用于当前 boot 选择。 |
| `.github/workflows/image-build.yml` | `BOARD: pcduino3b`、compile `BOARD="$BOARD"`、`Pcduino3b` artifact | 1、2 | 当前 workflow 直接调用固定 Armbian `compile.sh`，因为固定 composite Action 会在构建后立即发布，无法实现 `publish=false` 和“先验收再上传”。CLI 的正式等价入口明确传 `BOARD=pcduino3b`，并由 `config-dump-json` 与镜像内 `BOARD` 双重验收；若改回 Action wrapper，其 `armbian_board` 同样必须为 `pcduino3b`。 |
| preflight/image acceptance 的原板回归项 | `sun7i-a20-pcduino3.dtb`、`model = "LinkSprite pcDuino3"`、`phy-mode = "mii"` | 3 | 只用于证明原板 DTS 未受 3B patch 污染；不得作为当前镜像 boot DTB。 |
| `userpatches/customize-image.sh` | hostname、`BOARD=pcDuino3B`、`ARMBIAN_BOARD=pcduino3b` | 1、2 | 生成时落盘，不依赖启动后手工修复。 |
| overlay 工具和 `tests/` | `pcduino3b-*`、期望身份值 | 1、2 | 当前命令/fixture；不得接受旧 slug 作为 PASS。 |
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
| `fdtfile` | 仓库不手工覆写；由正式 board/boot 配置机制生成，workflow 只验收其最终值。 |
| `sun7i-a20-pcduino3` | 带 `b` 的 DTB 是当前成品；不带 `b` 的 DTS 仅为上游 include/兼容验证。 |
| `Linksprite_pcDuino3_defconfig` | 分类 4，允许作为 U-Boot 内部兼容配置。 |

## 验收门

整改完成后 identity lint 应至少拒绝：workflow 使用旧 board target、build-info 的旧 `ARMBIAN_BOARD`、旧 DTB 作为启动文件、原 DTS 被补成 RGMII-ID、当前硬件说明出现 Nano 类比、以及用户可见文件把当前产品称为旧板型。允许列表必须按路径和语义匹配，不能简单禁止所有 `pcduino3` 子串。
