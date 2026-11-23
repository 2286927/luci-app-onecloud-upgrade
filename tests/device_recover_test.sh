#!/bin/sh
# 设备侧判定逻辑验证：只在 /tmp 下构造状态，不触碰真实 /opt/fwupgrade。
# 用法（设备上）：sh /tmp/device_recover_test.sh
set -u
CTL=/usr/libexec/fwupgrade/fwupgradectl
ROOT=/tmp/fwutest
export FWU_LIBDIR=/usr/libexec/fwupgrade FWU_ROOT=$ROOT FWU_LOCK=$ROOT.lock FWU_LAST_FILE=$ROOT.last

VER=$(cat /etc/oc-version)
NOW=$(date +%s)
BID=$(cat /proc/sys/kernel/random/boot_id | tr -d "-")
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  ok   $1"; }
bad(){ FAIL=$((FAIL+1)); echo "  FAIL $1"; }
eq(){ [ "$2" = "$3" ] && ok "$1" || bad "$1（期望 $3 实际 $2）"; }

fresh(){ rm -rf $ROOT $ROOT.lock $ROOT.last; mkdir -p $ROOT; }

echo "== A 未重启且未超时 =="
fresh
printf 'phase=boot_written\nversion=%s\nboot_id_pre=%s\napply_started=%s\n' "$VER" "$BID" "$NOW" >$ROOT/state.env
$CTL recover >/dev/null 2>&1
eq "阶段保持" "$(awk -F= '$1=="phase"{print $2}' $ROOT/state.env)" "boot_written"

echo "== B 未重启且已超时 =="
fresh
printf 'phase=boot_written\nversion=%s\nboot_id_pre=%s\napply_started=%s\n' "$VER" "$BID" "$((NOW-1200))" >$ROOT/state.env
$CTL recover >/dev/null 2>&1
eq "判失败" "$(awk -F= '$1=="last_result"{print $2}' $ROOT/state.env)" "failed"
eq "混合态 H1" "$(awk -F= '$1=="mixed_state"{print $2}' $ROOT/state.env)" "H1"
grep -q "未重启" $ROOT/state.env && ok "原因写明未重启" || bad "原因缺失"

echo "== C 已重启但记录过期 =="
fresh
printf 'phase=boot_written\nversion=%s\nboot_id_pre=deadbeef\napply_started=%s\n' "$VER" "$NOW" >$ROOT/state.env
printf '%s reboot-ok ver=%s kv=x\n' "$(date -d '2020-01-01 00:00:00' '+%F %T')" "$VER" >$ROOT.last
$CTL recover >/dev/null 2>&1
eq "过期记录判失败" "$(awk -F= '$1=="last_result"{print $2}' $ROOT/state.env)" "failed"
grep -q "stale_record" $ROOT/state.env && ok "原因标 stale_record" || bad "原因未标注"

echo "== D 已重启且记录新鲜 =="
fresh
printf 'phase=boot_written\nversion=%s\nboot_id_pre=deadbeef\napply_started=%s\n' "$VER" "$NOW" >$ROOT/state.env
printf '%s reboot-ok ver=%s kv=x\n' "$(date '+%F %T')" "$VER" >$ROOT.last
$CTL recover >/dev/null 2>&1
eq "判成功" "$(awk -F= '$1=="last_result"{print $2}' $ROOT/state.env)" "ok"
eq "混合态清零" "$(awk -F= '$1=="mixed_state"{print $2}' $ROOT/state.env)" "N"

echo "== E status 自动收敛（超时未重启）=="
fresh
printf 'phase=applying\nversion=%s\nboot_id_pre=%s\napply_started=%s\n' "$VER" "$BID" "$((NOW-1200))" >$ROOT/state.env
$CTL status --json >/dev/null 2>&1
eq "status 触发判定" "$(awk -F= '$1=="last_result"{print $2}' $ROOT/state.env)" "failed"

echo "== F 已重启但无记录 =="
fresh
printf 'phase=boot_written\nversion=%s\nboot_id_pre=deadbeef\napply_started=%s\n' "$VER" "$NOW" >$ROOT/state.env
$CTL recover >/dev/null 2>&1
eq "无记录判失败" "$(awk -F= '$1=="last_result"{print $2}' $ROOT/state.env)" "failed"

rm -rf $ROOT $ROOT.lock $ROOT.last
printf '设备判定测试: pass=%d fail=%d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
