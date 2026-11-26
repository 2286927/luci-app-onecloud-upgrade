# CHANGELOG

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
