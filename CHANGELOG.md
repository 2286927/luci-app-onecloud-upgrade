# CHANGELOG

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
