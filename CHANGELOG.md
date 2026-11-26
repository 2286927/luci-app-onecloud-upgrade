# CHANGELOG

## v0.1.7 (2026-11-26)

许可证变更：Apache-2.0 → **PolyForm Noncommercial 1.0.0**（禁止商业使用，版权人保留商业化权利）。

### 变更
- `LICENSE` 改为 PolyForm Noncommercial 1.0.0：个人/研究/教育/公益/政府用途可自由使用与修改；**商业使用需单独授权**；分发须保留版权声明与 `Required Notice`。
- 5 个包的 `PKG_LICENSE` 由 `GPL-2.0-only` 改为 `PolyForm-Noncommercial-1.0.0`（此前 Makefile 与 LICENSE 文件本身就不一致，一并纠正）。
- 新增 [许可与商业使用](docs/许可与商业使用.md)：常见情形对照表（自用/公司内部/随硬件销售/SaaS/改名发布等）、商业授权方式、旧版本说明。

### 说明
- **v0.1.0 – v0.1.6 仍以 Apache-2.0 授权**，已获得这些版本的人其权利不因本次变更而收回（Apache-2.0 授权不可撤销）。
- PolyForm Noncommercial 不是 OSI 认可的开源协议，属 source-available。

## v0.1.6 (2026-11-26)

交互验收暴露的两个健壮性问题，加上备份保护的可视化。

### 修复
- **检测可能「卡住」**：`uclient-fetch` 的 `-T` 只是空闲超时，遇到细水长流的连接会一直挂着，`check` 就会长期停在 `checking`，页面永远显示「检测中」。现在每次取件都有 40 秒硬上限（`run_timeout`：后台执行 + 轮询 + kill，因为本机 busybox 没有 `timeout`）。
- **`checking` 状态会永久残留**：`status` 现在也会对 `checking` 做收口——超过 240 秒未完成直接判 `failed` 并提示「网络卡住或 DNS 失败，请重试」，不再让界面停在检测中。

### 改进
- **备份表标出受保护的那一份**：`backups --json` 增加 `newest` 字段（判定与 `forget` 一致：按 mtime，跨本应用与现网脚本两类备份），页面在「来源」列显示「（最新·受保护）」。此前点删除才被拒，用户不知道原因。

### 测试
- 新增 `tests/device_ui_actions_test.sh`：按页面按钮实际调用的 RPC 做功能验收——保存/清空、检测（含异步收敛与耗时）、升级（force + 演练，验证不写盘不重启）、导出诊断包（6 条目/脱敏/不含配置）、恢复（merge）、删除（受保护被拒 + 普通备份可删）、日志。

## v0.1.5 (2026-11-26)

默认固件源改为 OneCloud 官方仓；包版本号与发布 tag 对齐。

### 变更
- `onecloud-upgrade.main.repo` 默认值由空改为 `2286927/onecloud-25.12-onlineFirmware`，`tag` 默认留空（走 `stable`/latest）。开箱即可检测官方固件，换仓库或一仓多机型时在页面改。
- **5 个包的 `PKG_VERSION` 由 0.1.0 改为 0.1.5**：此前每次发布都是 `0.1.0-r1`，`apk` 无法区分新旧，覆盖安装只能靠 `--force-overwrite`；现在版本号随 tag 递增，`apk` 能识别升级。

### 测试
- 本版在实机上做完整交互验收：保存/清空、检测、升级（演练）、导出诊断包、备份恢复与删除、日志与状态轮询，逐项核对页面动作与设备侧真实结果。

## v0.1.4 (2026-11-26)

移除「阶段进度」进度条。

### 变更
- **状态卡不再显示进度条**。理由：进度只有 5 个粗粒度节点（5/40/45/70/100），其中「写入中」的真实耗时在设备脚本里、应用无法细分；空闲时又只能显示 `—`，反而让用户以为坏了。当前处在哪一步，上面「阶段」与「说明」两行已经写清楚（如 `阶段：写入 boot` / `说明：正在写入（boot 为最后一步）`）。
- `progress` 字段仍保留在 `state.json`（诊断包与 `status --json` 用），只是不再上界面。

### 测试
- `tests/ui_render_test.js` 同步：断言状态卡里**不存在** `oc-prog` 元素，并校验写入阶段的阶段名与说明文案。

## v0.1.3 (2026-11-26)

清空输入框保存不生效（服务端把「空串」当成「没传这个字段」跳过）。

### 修复
- **`config_set` 区分「值为空」与「字段未传」**：`jsonfilter` 对「键存在但值为空串」返回 rc=0、对「键不存在」返回 rc=1。原实现只看输出是否非空（`[ -n "$_v" ] || continue`），于是清空「指定 tag」被当成没传而跳过，保存刷新后旧值又回来了。文本字段（`repo` / `base_url` / `asset_rootfs` / `asset_boot` / `tag`）现在允许清空；枚举字段（`provider` / `channel` / `dry_run` / `force` / `require_signature`）收到非法或空值仍保持原值。
- **保存后按设备实际值回填表单**：保存成功会重新 `config_get` 一次并刷新输入框/勾选框，用户能立刻确认「清空」是否真的落盘。

### 测试
- 新增 `tests/device_config_set.sh`（设备侧 6 项）：显式空串可清空、未传字段不改写、具体值可写入、重复清空仍生效、非法枚举被拒、结束后自动恢复原配置。

## v0.1.2 (2026-11-26)

界面两个「假数据」修掉：阶段进度条显示上一次写入残留的百分比，日志区永远是空白。

### 修复
- **阶段进度只在写入阶段显示**：`ready/idle/failed` 一律显示 `—`、进度条归零。原因是 `progress` 是上一次写入留下的值，页面无脑画出来，空闲时也会显示 70%。检测收尾（`check` 的四个分支）与 `worker` 的失败收尾现在都把 `progress` 归零，`status --json` 也不再谎报。
- **日志区永远是空的**：`rpc.declare` 的 `expect: { lines: '' }` 等于要求返回值里 `lines` 恰好是空串，而 `log_tail` 返回的是非空日志，于是每次调用都被 LuCI 判为「返回值不符」直接 reject，页面连错误都不显示。去掉该 `expect`，并补空态提示 `（暂无日志）`、失败提示与自动滚到底。
- **首屏多拉一次状态**：`poll` 由 LuCI 启动，若挂载时机不巧会一直不触发，日志会停在初始占位。现在渲染后 300ms 主动 `refresh()` 一次。

### 测试
- 新增 `tests/ui_render_test.js`（Node + 桩件跑真实视图代码）：空闲显示 `—`、写入显示百分比、`log_tail` 内容渲染、空日志提示，7 项断言。该测试同时模拟 LuCI 的 `expect` 语义，能挡住这类「声明错就静默失败」的回归。
- CI 增加「静态检查与单测」步骤：全量 `sh -n` + `sh tests/test_core.sh` + `node tests/ui_render_test.js`。

## v0.1.1 (2026-11-26)

跨仓库升级可用性修复（由「用另一个仓库的玩客云固件实测」暴露）。

### 修复
- **`tag` 选项**：`provider` 支持按 tag 取 Release（`/releases/tags/<tag>`），配置项 `onecloud-upgrade.main.tag`，页面新增「指定 tag」输入。一仓多机型时 `latest` 会指到别的机型，必须用它。
- **写入链路改用清单地址**：`flashers/onecloud.sh` 现在以 `--url=<清单里的 rootfs 直链>` 调用设备脚本，并导出 `OC_REPO=<配置的仓库>`。此前脚本完全忽略应用解析结果，按自己的 `/etc/oc-repo` 判「已是最新」后 exit 0，一个字节没写。
- **「已是最新」不再冒充写入成功**：`worker.sh` 在 `rc=0` 后检查 `/opt/oc-upgrade.last` 的末条记录，若是本轮的 `uptodate`，立刻判 `failed` 并说明原因（原来要干等 15 分钟超时）。
- **陈旧签名误报**：`check` 现在把 `manifest.json` 与 `manifest.json.sig` 一起清；provider 解析前也清残留 `.sig`。否则从「有签名的源」切到「无签名的源」会拿旧签名验新清单，误报 rc=6。

### 测试
- 单测 60 → 63 条（`asset_url_by_role`、清单资产地址、包注册自检）。
- 实测：固件源切到 `ImmortalWrt-MultiDevice` 的 `26.11.21_08.59.21`，`26.11.18_16.27.30 → 26.11.21_08.59.21` 升级成功，配置 40 文件保留，`reboot-ok` 记录的 sha 与 Release 摘要一致。

## Unreleased

- `status` 新增「包管理」一行：`pkg_registered()` 读 `/lib/apk/db/installed`，区分「已注册 / 未注册（文件在位但 apk 无记录）/ 无法确认」。在线升级会用新镜像的数据库整包覆盖，若镜像未打包本应用，文件残留但注册丢失——重装需 `--force-overwrite`（细节见 `docs/固件接入.md`）。
- 单测 57 → 60 条。
- 文档重构：README 由 267 行（混入 11-23 的开发流水账）精简为 131 行产品说明；新增 `docs/开发备忘.md`（LuCI/rpcd 三处坑、打包与并发约定）；`安装与卸载` 补备份/回滚语义与 `diag` 内容；`兼容性` 补 11-26 破坏性验证与「设备脚本镜像表被 cron 重排」的说明；删除无引用的遗留文件 `page.html`、`arr.json`。

## v0.1.0 (2026-11-26)

首个正式版本。仅支持 OneCloud（ImmortalWrt 25.12-SNAPSHOT / apk / ucode LuCI），不承诺跨机型。

回滚路径掉电加固；故障矩阵补满 24/24；「boot 分区写坏 = 不可引导、线刷可恢复」经串口证据确认。

### 修复
- **配置回滚掉电安全**（三个缺口）：
  - `--replace` 改为「旁路目录构建 + 逐文件校验 + 两次 rename 切换」，消除「`/etc/config` 被移走后掉电导致配置目录消失」的窗口；
  - 合并模式改为逐文件「临时名 + rename」，避免 `cp -a` 半途掉电留下截断文件；
  - 写入前落 `phase=rollback` 标记，掉电后 `status` 收口为 `failed / mixed_state=C1` 并给出备份 ID 与补救方式，不再把中断当成上一次的 `ok`；
  - 下次执行自动清理残留的 `.fwu-tmp` 与 `config.new-*`。
- 回滚可重复执行（幂等）：中断后直接重跑同一备份即可收敛到一致状态。

### 测试
- `tests/test_core.sh` 增至 57 条（新增中断标记、C1 收口、幂等重跑、陈旧临时文件清理、replace 两阶段）。
- 新增 `tests/device_rollback_interrupt.sh`：设备侧 `kill -9` 近似掉电，覆盖合并/replace 两条路径，实测 fail=0。
- 故障矩阵 24/24；「boot 分区写坏 = 不可引导、线刷可恢复」经串口证据确认（U-Boot `fatload mmc 1:1` 失败 → `Invalid boot device` → `m8b_onecloud#` 循环，线刷两次均恢复成功）。

### 其它
- `clean` 现在清理 `/etc/config.pre-*`（只保留最新一份）与 `/etc/config.new-*` 残骸。
- CI：`prerelease` 改按 tag 判定（含 `-rc` 才是预发布）。

## v0.1.0-rc1 (2026-11-23)

首个候选发布版本（rc1）。仅支持 OneCloud（ImmortalWrt 25.12 / apk / ucode LuCI），不承诺跨机型。

### 新增
- **清单签名**：usign(ed25519)  detached 签名，公钥随包安装；`require_signature=1` 时无签名/验签失败直接拒绝。
- 资产获取带镜像回退（直连失败依次尝试 `gh-proxy.org` / `gh-proxy.com`）。
- `tools/gen_manifest.py`：按 Release 资产生成 manifest（含 target/board/asset sha256）。
- `fwupgrade-core`：状态机、设备侧单实例锁、清单解析、版本判定、配置备份、L1 回滚、诊断包。
- `fwupgrade-provider-github`：GitHub Release（stable）、静态 HTTPS、本地文件三种源。
- `fwupgrade-flasher-onecloud`：委托现网 `/usr/bin/upgrade`，支持 `--force`；`fwupgrade-flasher-dryrun` 用于不写盘验证。
- `luci-app-onecloud-upgrade`：状态卡、固件源配置、检测/升级、备份表与恢复、诊断导出；rpcd 九个方法，ACL 分 read/write/apply 三组。

### 修复
- **升级结局判定**：由「版本相等」改为「`boot_id` 变化 + 脚本 `reboot-ok` 记录时间不早于本次受理 + 版本一致」，避免同版本 `--force` 重刷时把失败误判为成功；`status` 轮询会自动收敛，超过 15 分钟未重启直接判失败。
- `luci-app` 依赖补 `fwupgrade-provider-github` 与 `jsonfilter`。
- `clean` 现在同时清理诊断包与回滚临时目录。

### 工程
- 资产成套性检查：清单必须同时含 rootfs 与 boot，否则检测阶段即失败。
- 页面增加「演练模式（dry_run）」与「强制重刷（force）」开关、阶段进度条。
- 故障注入 6 条（配置缺失/缺资产/平台不符/空间不足/重复 apply/非法备份 ID）全部通过。
- apk 真机安装验证：5 个包纳入 apk 包管理，配置与运行态保持。
- CI：公开仓内用 OpenWrt 25.12 x86/64 SDK 构建，5 个 apk 全部产出（noarch）；修正 luci 包注册方式（改普通包定义）。
- 增加 `LICENSE`（GPL-2.0）、`.gitignore`、`.gitattributes`（强制 LF）。
- 工具脚本不再内置设备地址，必须通过 `OC_HOST` 传入。
- 测试：32 条单测 + 10 条设备侧判定测试。

### 已知限制
- 签名默认不强制（`require_signature=0`）；只支持 stable 通道；界面仅中文（i18n 未做）；故障矩阵已覆盖 9/24 条。
