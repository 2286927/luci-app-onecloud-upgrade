# luci-app-onecloud-upgrade

给 **OneCloud（Amlogic S805 / meson8b / eMMC）** 用的在线升级 LuCI 应用。

设备固件里没有 `IMAGE/sysupgrade`，标准 OpenWrt 的升级路径在 OneCloud 上不存在。本应用把「固件仓的发布产物」和「设备自带的 `/usr/bin/upgrade`」包成一套可配置、可验证、可回滚的升级流程：**自己不做任何写盘逻辑**，只负责取清单、验签、比对、调度与判定。

只支持 OneCloud + ImmortalWrt 25.12（apk + ucode LuCI），**不承诺跨机型**。这里的"通用"指跨用户、跨固件仓、跨自编译固件——仓库地址、资产名、版本源都在页面上配，不写死。

## 能做什么

| 能力 | 说明 |
|---|---|
| 检测 | GitHub Release / 静态 HTTPS 目录 / 本地文件三种源，统一成 `manifest.json`；比版本、比平台、比资产 size 与 sha256。**可用 `tag` 指定具体 Release**（一仓多机型必备，否则 latest 会指到别的机型） |
| 验签 | manifest 用 usign(ed25519) detached 签名，公钥随包安装；`require_signature=1` 时无签名或验签失败直接拒绝 |
| 升级 | 默认演练（`dry_run=1`）不写盘；关闭演练后委托 `/usr/bin/upgrade --reboot`。成功判据是 **boot_id 变化 + 脚本 `reboot-ok` 记录 + 版本一致**，三者缺一即判失败 |
| 备份与回滚 | 写入前自动备份 `/etc/config`；merge / replace 两种恢复；掉电中断可见（`phase=rollback` → `failed/C1`），回滚幂等可重跑 |
| 诊断 | 一键打包 6 项脱敏信息，不含任何配置内容、不含 token |
| 通道 | stable（latest）、beta（releases 列表首个非 draft），或显式 `tag` |

## 五个包

| 包 | 作用 | 关键点 |
|---|---|---|
| `fwupgrade-core` | 状态机、单实例锁、清单解析、版本判定、备份/回滚、日志、恢复判定 | 唯一的状态所有者；不含任何写盘逻辑 |
| `fwupgrade-provider-github` | GitHub Release / 静态 HTTPS / 本地文件 → 统一清单 | Release 里有 `manifest.json` 就用它，没有则按配置的资产名合成（兼容旧发布） |
| `fwupgrade-flasher-onecloud` | 唯一的写入实现，委托 `/usr/bin/upgrade` | 不自建写入：那 848 行脚本已经吸收过三次真实事故 |
| `fwupgrade-flasher-dryrun` | 只模拟、不写盘 | 新设备接入验证、CI 与演练模式用 |
| `luci-app-onecloud-upgrade` | LuCI 视图 + rpcd + ACL | 所有方法秒回，长任务只返回 `job_id` |

全部 `PKGARCH=all`（纯 shell / ucode / JS），与目标架构无关。

## 安装

**方式一：随固件构建（推荐）** —— 把本仓当 feed 引入，编进镜像；这样升级后应用仍在 apk 管理内。步骤见 [固件接入](docs/固件接入.md)。

**方式二：装 apk** —— 从 [Releases](https://github.com/2286927/luci-app-onecloud-upgrade/releases) 取 5 个 apk：

```sh
scp *-0.1.0-r1.apk root@<设备IP>:/tmp/
# 设备上（本地包未签名，必须 --allow-untrusted；--repositories-file /dev/null 表示不联网取依赖）
apk add --allow-untrusted --force-overwrite --repositories-file /dev/null /tmp/*.apk
/etc/init.d/rpcd restart
```

菜单在 **系统 → OneCloud 升级**；命令行在 `/usr/libexec/fwupgrade/fwupgradectl`。

## 快速开始

页面上：填仓库与资产名 → 保持演练模式勾选 → 「检测新版本」→「升级」→ 看阶段迁移 → 确认无误后取消演练再保存。

命令行等价操作：

```sh
/usr/libexec/fwupgrade/fwupgradectl check              # 取清单、验签、比版本
/usr/libexec/fwupgrade/fwupgradectl status             # 阶段 / 结果 / 混合态 / 包管理
/usr/libexec/fwupgrade/fwupgradectl apply --confirm <目标版本>
/usr/libexec/fwupgrade/fwupgradectl backups            # 可寻址备份列表
/usr/libexec/fwupgrade/fwupgradectl rollback --confirm <备份ID> [--replace]
/usr/libexec/fwupgrade/fwupgradectl diag               # 生成脱敏诊断包
```

`/etc/config/onecloud-upgrade` 的字段：`provider` / `repo` / `base_url` / `asset_rootfs` / `asset_boot` / `channel` / `dry_run` / `force` / `require_signature`。

## 文档

| 文档 | 内容 |
|---|---|
| [安装与卸载](docs/安装与卸载.md) | apk 安装、首次使用、备份/回滚语义、`diag` 内容、卸载 |
| [固件接入](docs/固件接入.md) | feed 方式打进镜像；**升级后 apk 注册会丢**的场景与恢复 |
| [兼容性](docs/兼容性.md) | 支持范围、运行依赖、已验证矩阵、已知限制 |
| [救援指引](docs/救援指引.md) | 失败判定、boot 破坏现场特征、线刷与 U-Boot 提示符两条恢复路径 |
| [签名与密钥](docs/签名与密钥.md) | usign 清单签名、密钥轮换、私钥保管 |
| [开发备忘](docs/开发备忘.md) | LuCI / rpcd 的三处坑（视图目录、exec 协议、并发） |
| [发布说明 v0.1.1](docs/发布说明-0.1.1.md) | 本版修了什么（tag、按清单写入、快速失败、陈旧签名） |
| [发布说明 v0.1.0](docs/发布说明-0.1.0.md) | 首个正式版内容与已知限制 |
| [破坏性测试预案](docs/破坏性测试预案.md) | 掉电/损坏类测试的前置条件、步骤与实测结论 |
| [发布评估](docs/发布评估-20261123.md) | 完整评审记录：问题清单、修复、故障矩阵、升级验收 |
| [测试脚本索引](tests/README.md) | 单测与设备侧脚本怎么跑 |

## 发布状态

**v0.1.1**（2026-11-26）。产物：<https://github.com/2286927/luci-app-onecloud-upgrade/releases/tag/v0.1.1>，5 个 noarch apk。打 tag 时 CI 自动构建并附加到 Release。

已完成的实机验证：

- 真实在线升级 `26.11.17_17.35.18` → `26.11.18_16.27.30`：boot_id 变化、`reboot-ok` 记录、版本一致、`/etc/config` 40 个文件保留、升级后再检测不重复提示
- **跨仓库升级** `26.11.18_16.27.30` → `26.11.21_08.59.21`（固件来自 `ImmortalWrt-MultiDevice`，用 `tag` 指定）：完成，记录的 sha256 与 Release 摘要一致
- 故障矩阵 **24/24**；单测 **60 条**
- boot 分区写坏 = 不可引导（U-Boot `fatload mmc 1:1` 失败 → `Invalid boot device` → `m8b_onecloud#` 循环），线刷恢复两次实证

## 开发与测试

```sh
sh tests/test_core.sh          # 纯函数/状态/回滚单测，不需要设备（60 条）
python3 tools/gen_manifest.py  # 按 Release 资产生成 manifest + 签名
```

设备侧脚本需要先设 `OC_HOST`（详见 [tests/README](tests/README.md)），覆盖故障注入、恢复判定、并发、回滚中断等场景。CI 在 `.github/workflows/build-packages.yml`：拉 OpenWrt 25.12 x86/64 SDK → 注入本仓 → 编译 5 个包 → 产物数不为 5 直接失败 → tag 时附到 Release。

> SDK 日志会报 `ucode` / `ucode-mod-fs` / `ucode-mod-uci` 的 "dependency does not exist"——那是 SDK 包索引不含基础包导致的告警，apk 的 `depend` 字段正确，设备上这些依赖本就存在。

## 关键契约

| 项 | 约定 |
|---|---|
| 状态文件 | `/opt/fwupgrade/state.env`（内部真值）+ `state.json`（派生，给 UI/rpcd） |
| 日志 | `/opt/fwupgrade/journal.log`，单次 ≤0.5 MB，超限就地截半 |
| 锁 | `/var/run/fwupgrade.lock`，内容 `pid boot_id phase`；`writing_boot` 即使 pid 已死也拒绝自动继续 |
| 退出码 | 0 成功 / 2 参数或占用 / 3 网络或身份 / 4 空间 / 5 下载 / 6 校验 / 7 未实现 / 8 状态 |
| 版本比较 | 优先 `build_ts`；退回 `YY.MM.DD_HH.MM.SS` 字符串比较（零填充，可直接比） |
| 写入 | 只调用 `/usr/bin/upgrade --reboot --url=<清单 rootfs 直链>`，并导出 `OC_REPO=<配置的仓库>`；boot 永远由它最后写 |
| 安全默认 | `dry_run=1`：即使清单指定真实 flasher，worker 也强制走 dry-run；只有显式置 0 才写盘 |

## 不做 / 已知限制

**不做**：sysupgrade 后端、ASU / ImageBuilder、批量或远程下发、无人值守定时升级、「只下载不安装」入口、i18n（界面仅中文）、离线升级包（设备侧脚本 `--url` 模式仍会调 GitHub API 取 sha256，需改脚本）。

**已知限制**：

- **写 boot 中断 = 不可引导**。单机型、无 A/B、无自愈；恢复只能线刷（双公头线插上即进烧录模式，无需短接）或掉到 `m8b_onecloud#` 时人工修。
- **镜像未打包本应用时，在线升级会冲掉 apk 注册**：文件仍在、功能照常，但 `apk del/upgrade` 不再管它，重装要带 `--force-overwrite`。详见 [固件接入](docs/固件接入.md)。
- 进度是**阶段进度**（预检/备份/写入/收尾），不是字节进度。
- 默认 `require_signature=0`（有签名则校验、无签名放行）；自有发布流程稳定后建议置 1。

## English

`luci-app-onecloud-upgrade` is a LuCI application for **OneCloud (Amlogic S805 / meson8b)** running ImmortalWrt 25.12 (apk + ucode LuCI). OneCloud has no `IMAGE/sysupgrade`, so this app wraps the vendor `upgrade` script with a configurable firmware source (any GitHub repo, static HTTPS directory or local file), manifest signature verification (usign/ed25519), version checks, dry-run mode, config backup/rollback and a redacted diagnostics bundle.

It is **not** a generic sysupgrade frontend. All 5 packages are `PKGARCH=all` (shell/ucode/JS only) and built in this repo's CI with the OpenWrt 25.12 SDK. Docs are currently Chinese-only: [install](docs/安装与卸载.md), [rescue](docs/救援指引.md), [compatibility](docs/兼容性.md).

## License

Apache-2.0，见 [LICENSE](LICENSE)。
