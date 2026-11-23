# CHANGELOG

## v0.1.0-alpha (2026-11-23)

首个可内测版本。仅支持 OneCloud（ImmortalWrt 25.12 / apk / ucode LuCI），不承诺跨机型。

### 新增
- `fwupgrade-core`：状态机、设备侧单实例锁、清单解析、版本判定、配置备份、L1 回滚、诊断包。
- `fwupgrade-provider-github`：GitHub Release（stable）、静态 HTTPS、本地文件三种源。
- `fwupgrade-flasher-onecloud`：委托现网 `/usr/bin/upgrade`，支持 `--force`；`fwupgrade-flasher-dryrun` 用于不写盘验证。
- `luci-app-onecloud-upgrade`：状态卡、固件源配置、检测/升级、备份表与恢复、诊断导出；rpcd 九个方法，ACL 分 read/write/apply 三组。

### 修复
- **升级结局判定**：由「版本相等」改为「`boot_id` 变化 + 脚本 `reboot-ok` 记录时间不早于本次受理 + 版本一致」，避免同版本 `--force` 重刷时把失败误判为成功；`status` 轮询会自动收敛，超过 15 分钟未重启直接判失败。
- `luci-app` 依赖补 `fwupgrade-provider-github` 与 `jsonfilter`。
- `clean` 现在同时清理诊断包与回滚临时目录。

### 工程
- 增加 `LICENSE`（GPL-2.0）、`.gitignore`、`.gitattributes`（强制 LF）。
- 工具脚本不再内置设备地址，必须通过 `OC_HOST` 传入。
- 测试：32 条单测 + 10 条设备侧判定测试。

### 已知限制
- 未验签；只支持 stable 通道；无阶段进度；安装包尚未通过 SDK 构建验证。
