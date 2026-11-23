#!/bin/sh
# 纯函数与状态层单测：可在开发机（Git Bash / Linux）直接跑，不依赖设备。
# 用法: sh tests/test_core.sh
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
LIB="$ROOT/package/fwupgrade-core/files/usr/libexec/fwupgrade/lib.sh"

TMP=$(mktemp -d 2>/dev/null || echo "/tmp/fwu-test.$$")
mkdir -p "$TMP"
cd "$TMP" || exit 1
# 用相对路径，避免 Windows 下 rm 绝对路径被安全策略拦截
FWU_ROOT="./root"
FWU_LOCK="./fwupgrade.lock"
FWU_JOURNAL="$FWU_ROOT/journal.log"
mkdir -p "$FWU_ROOT"
export FWU_ROOT FWU_LOCK FWU_JOURNAL

# shellcheck disable=SC1090
. "$LIB"

pass=0; fail=0
ok() { pass=$((pass+1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL %s\n' "$1"; }

eq() { [ "$2" = "$3" ] && ok "$1" || bad "$1（期望 [$3] 实际 [$2]）"; }

echo "== jesc =="
eq "引号转义" "$(jesc 'a"b')" 'a\"b'
eq "反斜杠转义" "$(jesc 'a\b')" 'a\\b'

echo "== 版本比较 =="
ver_gt "26.11.18_16.27.30" "26.11.11_16.46.12" && ok "新版 > 旧版" || bad "新版 > 旧版"
ver_gt "26.11.18_16.27.30" "26.11.18_16.27.30" && bad "同版本不应判新" || ok "同版本不判新"
ver_gt "26.11.10_00.00.00" "26.11.18_16.27.30" && bad "旧版不应判新" || ok "旧版不判新"

echo "== 版本归一 =="
eq "标准格式" "$(norm_version '26.11.18_16.27.30')" '26.11.18_16.27.30'
eq "非法格式返回空" "$(norm_version 'v1.2.3')" ''

echo "== 状态合并 =="
state_replace "phase=idle" "current=26.11.18_16.27.30"
state_replace "phase=ready" "version=26.11.20_04.18.00"
eq "phase 被更新" "$(state_get phase)" "ready"
eq "旧键保留" "$(state_get current)" "26.11.18_16.27.30"
eq "新键写入" "$(state_get version)" "26.11.20_04.18.00"
if command -v python3 >/dev/null 2>&1; then
    python3 -c "import json;json.load(open(r'$FWU_ROOT/state.json'))" && ok "state.json 是合法 JSON" || bad "state.json 解析失败"
fi
grep -q '"version":"26.11.20_04.18.00"' "$FWU_ROOT/state.json" && ok "JSON 含目标版本" || bad "JSON 缺目标版本"

echo "== 锁 =="
lock_acquire; eq "首次取锁" "$?" "0"
lock_acquire; eq "同进程重入被拒" "$?" "1"
lock_release
lock_acquire; eq "释放后可再取" "$?" "0"
lock_release

# 伪造一个已死 pid 的锁：同 boot_id，应被当作陈旧锁清理
printf '999999 %s applying\n' "$(boot_id)" >"$FWU_LOCK"
lock_acquire; eq "陈旧锁可清理" "$?" "0"
lock_release

# 伪造 writing_boot 且同 boot（pid 已死也要拦住：可能是写完 boot 没重启）
printf '999999 %s writing_boot\n' "$(boot_id)" >"$FWU_LOCK"
lock_acquire; eq "writing_boot 未确认时拒绝" "$?" "2"
rm -f "$FWU_LOCK"

echo "== 备份 ID 校验 =="
valid_backup_id "upgrade-backup-20261118-220750" && ok "合法 ID" || bad "合法 ID 被拒"
valid_backup_id "../etc" && bad "路径穿越未拦" || ok "路径穿越被拒"
valid_backup_id "a/b" && bad "带斜杠未拦" || ok "带斜杠被拒"

echo "== L1 回滚（临时配置目录）=="
CTL="$ROOT/package/fwupgrade-core/files/usr/libexec/fwupgrade/fwupgradectl"
LIBDIR="$ROOT/package/fwupgrade-core/files/usr/libexec/fwupgrade"
BK="./backups"; CUR="./current"; R2="./root2"
mkdir -p "$BK/test-bk/config" "$CUR" "$R2"
printf 'old\n' >"$BK/test-bk/config/a.conf"
printf 'three\n' >"$BK/test-bk/config/c.conf"
printf 'new\n' >"$CUR/a.conf"
printf 'two\n' >"$CUR/b.conf"

_out=$(FWU_LIBDIR="$LIBDIR" FWU_ROOT="$R2" FWU_BACKUP_ROOT="$BK" FWU_ETC_CONFIG="$CUR" FWU_LOCK="$TMP/l2.lock" sh "$CTL" rollback --confirm test-bk --dry-run 2>&1)
printf '%s' "$_out" | grep -q '"changed":2' && ok "dry-run 统计出 2 个差异" || bad "dry-run 差异统计错误：$_out"

_out=$(FWU_LIBDIR="$LIBDIR" FWU_ROOT="$R2" FWU_BACKUP_ROOT="$BK" FWU_ETC_CONFIG="$CUR" FWU_LOCK="$TMP/l2.lock" sh "$CTL" rollback --confirm test-bk 2>&1)
[ "$(cat "$CUR/a.conf")" = "old" ] && ok "备份文件已覆盖" || bad "a.conf 未恢复"
[ "$(cat "$CUR/c.conf")" = "three" ] && ok "缺失文件已补回" || bad "c.conf 未补回"
[ -f "$CUR/b.conf" ] && ok "合并模式保留新增配置" || bad "合并模式误删 b.conf"
echo "$_out" | grep -q '"ok":true' && ok "回滚返回 ok" || bad "回滚返回异常：$_out"
[ -f "$R2/rollback/$(ls "$R2/rollback" | grep -m1 pre)/MANIFEST" ] && ok "回滚前快照已生成" || bad "缺少回滚前快照"

echo "== 升级结局判定 =="
eq "重启+记录+版本一致 → ok" "$(recover_decide A B 30 1000 1100 '26.11.20_04.18.00' '26.11.20_04.18.00' '26.11.20_04.18.00')" "ok"
eq "未重启且未超时 → pending" "$(recover_decide A A 100 1000 '' '' 'v' 'v')" "pending"
eq "未重启已超时 → no_reboot" "$(recover_decide A A 1200 1000 '' '' 'v' 'v')" "no_reboot"
eq "重启但版本不符 → version_mismatch" "$(recover_decide A B 30 1000 1100 'v2' 'v2' 'v1')" "version_mismatch"
eq "重启但记录过期 → stale_record" "$(recover_decide A B 30 5000 4000 'v' 'v' 'v')" "stale_record"
eq "重启但无记录 → no_record" "$(recover_decide A B 30 5000 '' '' 'v' 'v')" "no_record"

printf '结果: pass=%d fail=%d\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
