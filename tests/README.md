# 测试脚本索引

所有设备侧脚本都在设备上跑，**不写 boot、不重启**（除显式标注）。运行前会备份/还原 UCI 配置。

| 脚本 | 覆盖 | 运行 |
|---|---|---|
| `test_core.sh` | 纯函数/状态/锁/回滚 merge、签署判定（40+ 断言，开发机可跑） | `sh tests/test_core.sh` |
| `device_recover_test.sh` | 升级结局判定 6 种输入（ok/pending/no_reboot/version_mismatch/stale_record/no_record） | 设备上 `sh` |
| `device_fault_injection.sh` | 配置缺失、缺 boot、平台不符、空间不足、重复 apply、非法备份 ID | 设备上 `sh` |
| `device_fault_injection_extra.sh` | 坏 JSON、缺 rootfs、未知 provider | 设备上 `sh` |
| `device_fault_matrix2.sh` | schema 过高、sha 格式、size=0、未知版本、备份目录不可写、状态损坏、并发 check | 设备上 `sh` |
| `device_fault_longtail.sh` | 时钟错误、缺 usign、缺公钥、签名损坏、404、连接拒绝 | 设备上 `sh`（需先放已签名清单到 `/tmp/signed-src`） |
| `concurrent_check.sh` | 两个 check 并发（唯一临时文件回归） | 设备上 `sh` |
| `fixtures/` | 清单样例（含 dryrun/签名场景） | 静态数据 |
| `device_rollback_interrupt.sh` | 回滚中断（`kill -9` 近似掉电）：合并/replace 两条路径，验标记、原子性、C1 收口、幂等重跑 | 设备上 `sh`（自带兜底副本与自动还原） |

## 前置

- 设备可 SSH（auth none 或 key）、`/usr/libexec/fwupgrade` 已安装；
- 脚本会 `trap` 还原 `provider/repo/base_url/require_signature`；
- 任何写 `/etc/config` 的回滚测试都在 `/tmp` 副本上做，不动现网。

## 未执行

- **写 boot 中途掉电**：需要 USB 双公头线 + 现场烧录能力；串口 `bootdelay=0` 无法停在 U-Boot。步骤见 `docs/破坏性测试预案.md`。
- **回滚中途掉电**：依赖 L2 快照能力（未实现）。
| `ui_render_test.js` | 视图渲染冒烟：进度文本（空闲 `—` / 写入百分比）、`log_tail` 内容、空日志提示；用桩件跑真实 overview.js | 工作站 `node tests/ui_render_test.js` |
| `device_config_set.sh` | `config_set` 空值语义：清空生效、未传字段不改写、非法枚举被拒（自动恢复原配置） | 设备上 `sh` |
