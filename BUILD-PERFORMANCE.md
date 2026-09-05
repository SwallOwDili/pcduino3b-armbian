# pcDuino3B build performance

## 实测基线

数据源：[GitHub Actions run 33793510041](https://github.com/SwallOwDili/pcduino3b-armbian/actions/runs/33793510041)，仓库提交 `5ef1ee111cddd8681a7746efc8de01710bdb4a45`，2026-09-03 UTC。该轮使用固定 Armbian build commit `34e66c37211c70ef5cfad9c80dd76389720e19b7`、`armbian_runner_clean=yes` 和 `sha,img,xz`。

这不是全冷构建：U-Boot 与 Noble armhf rootfs 命中 Armbian OCI 远端缓存，内核仍完整重建。

## 2026-09-04 加速对照

同一套固定 Armbian 源码和 pcDuino3B 配置的后续实测已经把“冷编译”和“命中缓存”分开：

| 场景 | 实测 | 关键结果 |
| --- | ---: | --- |
| GitHub 冷 `dev`，[run 33836056196](https://github.com/SwallOwDili/pcduino3b-armbian/actions/runs/33836056196) | 88m21s | kernel 4431s；首次没有可复用的本项目缓存 |
| GitHub 热 `dev`，[run 33841755158](https://github.com/SwallOwDili/pcduino3b-armbian/actions/runs/33841755158) | 7m56s | kernel/U-Boot 均为 0s；Armbian 主路径 327s |
| GitHub 正式 `sd-release`，[run 33843467845](https://github.com/SwallOwDili/pcduino3b-armbian/actions/runs/33843467845) | 15m49s | kernel/U-Boot 均为 0s；xz 压缩 150s、完整性检查 29s |
| 本机 Docker，6 CPU（Armbian `-j9`） | kernel 4824s | 冷内核比 GitHub 冷构建慢约 9%；最终因 Docker Desktop 未建立 `/dev/loop0p1` 停在镜像组装，不是编译失败 |

结论：真正的数量级加速来自复用已完成的内核、U-Boot 和 rootfs，而不是把所有宿主机 CPU 交给容器。DTS 或内核配置变化会正确使内核缓存失效；仅改用户态、文档或发布状态时，热构建可从约 88 分钟降到 8～16 分钟。正式镜像的 xz 相比开发镜像的 zstd 额外消耗约 2.5 分钟，但换来更小的发布文件。

| 阶段 | 实测耗时 | 结论 |
| --- | ---: | --- |
| Armbian Action 总计 | 3,879,371 ms（约 64m39s） | 完整构建主路径 |
| runner clean | 约 2m08s | clean=yes 将可用空间约 86GiB 提升到 108GiB；只有这一组样本 |
| Action 下载 | 约 10s | 非主要瓶颈 |
| framework container / requirements | 71s | 容器工具准备 |
| kernel source OCI + git prepare | 64s + 22s | 复用 source gitball，仍需准备工作树 |
| kernel patch/config prepare | 约 29s | drivers patch 15s、main patch 5s、config 9s |
| kernel build | 2,945s（49m05s） | 主瓶颈，占 Action 总时长约 76% |
| kernel package | 43s | 内核编译后的打包 |
| U-Boot artifact | remote cache hit，约 1s 级 | 无需重编 U-Boot |
| rootfs artifact | remote cache hit，下载约 3s | Noble armhf CLI rootfs 已复用 |
| distribution-agnostic install | 227s | rootfs 组装的重要次级成本 |
| customize-image | 85s | 包含源更新、工具安装与 HTTPS 验证；新流程已把包安装移至 Armbian 聚合阶段 |
| image assembly（压缩前） | 约 77s | 从分区准备到 raw image 完成 |
| xz compression | 183s | 2008MiB → 515MiB，约 25% |
| image acceptance | 约 18s | 解压/挂载前后的工作流边界估算 |
| release report | 约 47s 后失败 | 原因是 `gh` 未显式指定 repository；不代表镜像构建失败 |

最优先优化项是内核 artifact 命中，而不是削弱 Noble 软件源验证。只改 rootfs、hostname、自检或文档时，不应重编内核/U-Boot；DTS 或内核配置变化必须进入内核/DTB 依赖检查。

## 当前策略

- Fast preflight 不创建 rootfs、镜像或压缩包，目标 2～5 分钟。
- `dev` 使用 Minimal rootfs 和快速压缩/短期 artifact，不创建正式 Release。
- `sd-release` 使用 xz、SHA-256 和完整镜像验收。
- `nand-installer`、`nand-recovery` 使用 Minimal rootfs；recovery 保持只读探测，installer 另带显式安全门，并由 CI 从同一已验收 rootfs 生成 raw boot FIT 与 SLC-emulated UBI 安装 bundle。
- Release promotion 复用已验收候选文件，不重新编译、组装或压缩。
- 包清单由 `packages/common.txt` 与 `packages/<profile>.txt` 聚合，再由 extension 的 `add_packages_to_image` 正式接口加入镜像；定制脚本仍执行一次必须成功的 `apt-get update`、DNS 和 Noble InRelease HTTPS 检查，但不再维护第二份安装列表。

## 缓存边界

固定 Armbian 版本已经证明会解析并使用 artifact/OCI cache：该基线 U-Boot 与 rootfs 命中，kernel 因补丁/配置身份变化未命中。安全的附加缓存限于 ccache、下载、工具链、rootfs 和已完成的 kernel/U-Boot artifact；不缓存挂载状态、loop device、完整工作 rootfs、整个源码工作树或最终镜像。

缓存 key 至少绑定 runner OS、`arm`、Armbian commit、`sun7i`、`pcduino3b`、kernel branch/version、Noble、profile、kernel config/DTS patch hash 和 U-Boot config hash。缓存只在成功构建后保存，并在 Job summary 报告命中状态和恢复体积。

## runner clean 决策

基线只有 `clean=yes`，尚不能据此证明 `clean=no` 对所有完整构建都安全。Fast preflight 不执行 runner clean；开发构建优先试验 `clean=no`；正式 release 冷构建在得到至少一次 `df -h`、`df -i`、`docker system df` 和关键目录体积的成功对照前保留安全清理。每轮记录清理自身耗时和构建结束余量。

## 每次完整构建必须记录

| 字段 | 记录要求 |
| --- | --- |
| runner | 初始化、clean、构建前后磁盘/ inode/容器占用 |
| inputs | Armbian commit、板型、kernel、release、profile、相关 hash |
| cache | 每类 cache hit/miss、恢复/保存大小 |
| build | Action 下载、host prepare、source/toolchain、U-Boot、kernel、rootfs、customize、assembly |
| acceptance | raw image 验收、压缩、解压完整性、release upload |
| sizes | raw / compressed 大小、压缩比 |
| status | `BUILD`、`IMAGE_ACCEPTANCE`、`RELEASE_UPLOAD`、`HARDWARE_ACCEPTANCE` 分开报告 |

后续实测结果追加到本文，保留 run URL、提交 SHA 和原始日志依据；不得用目标值冒充实测值。
