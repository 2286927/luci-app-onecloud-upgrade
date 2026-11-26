#!/bin/sh
# 设备侧：回滚中断（强杀 / 模拟掉电）安全测试
# 用法：sh device_rollback_interrupt.sh
# 前提：/usr/libexec/fwupgrade/ 已是待测版本
# 说明：本机 busybox 无 timeout、sleep 不支持小数，故用「后台跑 + kill -9」近似掉电
set -u
CTL=/usr/libexec/fwupgrade/fwupgradectl
ROOT=/opt/fwupgrade
BKROOT="$ROOT/backup"
TS=$(date +%Y%m%d-%H%M%S)
ID="upgrade-backup-$TS"
DIR="$BKROOT/$ID"
DUMMY_MB=250
KILL_AFTER=2
fail=0
ok() { printf '  ok   %s\n' "$1"; }
bad() { printf '  FAIL %s\n' "$1"; fail=$((fail+1)); }

# run_kill <秒> <命令...>：后台执行，睡 N 秒后 KILL（模拟掉电）
run_kill() {
    _n=$1; shift
    "$@" >/tmp/rb.out 2>&1 &
    _pid=$!
    sleep "$_n"
    kill -9 "$_pid" 2>/dev/null
    wait "$_pid" 2>/dev/null
    _rc=$?
    sleep 2          # 等可能残留的子进程（cp）自然结束，避免干扰下一步
    echo "  kill 后 rc=$_rc（原命令 $*）"
}

echo "== 0. 前置 =="
[ -x "$CTL" ] || { echo "找不到 $CTL"; exit 1; }
mkdir -p "$BKROOT"
rm -rf /tmp/etc-config-safety
mkdir -p /tmp/etc-config-safety
cp -a /etc/config/. /tmp/etc-config-safety/ 2>/dev/null
echo "  配置兜底副本：$(ls /tmp/etc-config-safety | wc -l) 个文件"

echo "== 1. 造备份（含 ${DUMMY_MB}MB 大文件，用于拉宽写入窗口）=="
mkdir -p "$DIR/config"
cp -a /etc/config/. "$DIR/config/" || { bad "复制配置失败"; exit 1; }
printf 'v1\n' >"$DIR/config/zztestonly"
dd if=/dev/zero of="$DIR/config/zzdummy" bs=1M count=$DUMMY_MB 2>/dev/null
SZ=$(wc -c <"$DIR/config/zzdummy")
N0=$(ls /etc/config | wc -l)
echo "  备份 $ID：$(ls "$DIR/config" | wc -l) 个文件，dummy=${SZ}B，当前 /etc/config=$N0 个"

echo "== 2. 合并回滚：${KILL_AFTER}s 强杀 =="
run_kill "$KILL_AFTER" "$CTL" rollback --confirm "$ID"
if grep -q '^phase=rollback' "$ROOT/state.env" 2>/dev/null; then
    ok "中断后留下 phase=rollback 标记"
else
    bad "未留 rollback 标记（判定：没被打断或没进写入段）"
fi
if [ -f /etc/config/zzdummy ]; then
    DS=$(wc -c </etc/config/zzdummy)
    [ "$DS" = "$SZ" ] && ok "dummy 未被截断（$DS B）" || bad "dummy 被截断（$DS / $SZ）"
else
    ok "dummy 尚未落地（保持旧状态，符合原子替换）"
fi
if [ -n "$(ls -a /etc/config | grep 'fwu-tmp' 2>/dev/null)" ]; then
    echo "  注意：有 .fwu-tmp 残留（下次执行会清理）"
else
    ok "无 .fwu-tmp 残留"
fi
N1=$(ls /etc/config | wc -l)
[ "$N1" -ge $((N0 - 1)) ] && ok "配置文件数未异常减少（$N0 → $N1）" || bad "配置文件数异常（$N0 → $N1）"
uci -q get system.@system[0].hostname >/dev/null 2>&1 && ok "uci 仍可读配置" || bad "uci 读取失败"

echo "== 3. status 收口 =="
$CTL status 2>&1 | sed 's/^/  | /'
grep -q '^mixed_state=C1' "$ROOT/state.env" 2>/dev/null && ok "标记混合态 C1" || bad "未标 C1"
grep -q '^phase=idle' "$ROOT/state.env" 2>/dev/null && ok "phase 收口到 idle" || bad "phase 未收口"
grep -q '回滚未完成' "$ROOT/state.env" 2>/dev/null && ok "detail 说明回滚未完成" || bad "detail 未说明"

echo "== 4. 重跑同一备份（幂等） =="
_t0=$(date +%s)
$CTL rollback --confirm "$ID" >/tmp/rb2.out 2>&1
rc=$?
_t1=$(date +%s)
[ "$rc" = 0 ] && ok "重跑成功（完整回滚耗时 $((_t1 - _t0))s）" || bad "重跑失败 rc=$rc：$(tail -2 /tmp/rb2.out)"
if [ -f /etc/config/zzdummy ] && [ "$(wc -c </etc/config/zzdummy)" = "$SZ" ]; then
    ok "dummy 完整落地（$SZ B）"
else
    bad "dummy 不完整"
fi
[ "$(cat /etc/config/zztestonly 2>/dev/null)" = "v1" ] && ok "缺失文件已补回" || bad "新增文件未补回"
[ -z "$(ls -a /etc/config | grep 'fwu-tmp' 2>/dev/null)" ] && ok "无临时文件残留" || bad "仍有临时文件"

echo "== 5. replace 回滚：强杀在旁路构建段 =="
# 先把大文件从 live 配置里移走，让「回滚前快照」变快，把强杀点压到 .new 构建阶段
rm -f /etc/config/zzdummy
BEFORE=$(ls /etc/config | wc -l)
run_kill 3 "$CTL" rollback --confirm "$ID" --replace
if [ ! -d /etc/config ]; then
    PRE=$(ls -d /etc/config.pre-* 2>/dev/null | tail -1)
    if [ -n "$PRE" ]; then mv "$PRE" /etc/config; echo "  已从 $PRE 还原"; else cp -a /tmp/etc-config-safety /etc/config; echo "  已从兜底副本还原"; fi
    bad "极窄窗口内配置目录被移走（已还原）"
else
    AFTER=$(ls /etc/config | wc -l)
    [ "$AFTER" -ge $((BEFORE - 2)) ] && ok "replace 中断后配置目录完好（$BEFORE → $AFTER）" || bad "配置目录被删改（$BEFORE → $AFTER）"
    uci -q get system.@system[0].hostname >/dev/null 2>&1 && ok "uci 仍可读配置" || bad "uci 读取失败"
fi
grep -q '^phase=rollback' "$ROOT/state.env" 2>/dev/null && ok "replace 中断也留下 rollback 标记" || echo "  说明：未留标记，可能已跑完"
ls -d /etc/config.new-* >/dev/null 2>&1 && echo "  注意：残留 .new 旁路目录（下次执行清理）" || ok "无 .new 残留"

echo "== 6. 再跑一次 replace 收尾 =="
$CTL rollback --confirm "$ID" --replace >/tmp/rb4.out 2>&1
rc=$?
[ "$rc" = 0 ] && ok "replace 重跑成功" || bad "replace 重跑失败 rc=$rc：$(tail -2 /tmp/rb4.out)"
ls -d /etc/config.new-* >/dev/null 2>&1 && bad "残留 .new 目录" || ok ".new 残留已清理"
grep -q '^phase=idle' "$ROOT/state.env" 2>/dev/null && ok "phase=idle" || bad "phase 异常"
[ "$(ls /etc/config | wc -l)" -ge $((BEFORE - 1)) ] && ok "replace 后配置数量正常" || bad "replace 后配置数量异常"

echo "== 7. 清理 =="
rm -rf "$DIR"
rm -f /etc/config/zztestonly /etc/config/zzdummy /etc/config/.zzdummy.fwu-tmp
echo "  已删除测试备份与测试文件；当前 /etc/config=$(ls /etc/config | wc -l) 个文件"

echo "结果: fail=$fail"
[ "$fail" = 0 ] && exit 0 || exit 1
