#!/bin/sh
# 故障矩阵（第二批）：清单字段、备份失败、状态损坏、并发、未知版本
# 全部不写 boot、不重启；结束后恢复原配置。
set -u
CTL=/usr/libexec/fwupgrade/fwupgradectl
LIB=/usr/libexec/fwupgrade/lib.sh
BASE=/tmp/fi3
export FWU_ROOT=$BASE/root FWU_LOCK=$BASE/lock
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  ok   $1"; }
bad(){ FAIL=$((FAIL+1)); echo "  FAIL $1"; }
eq(){ [ "$2" = "$3" ] && ok "$1（rc=$3）" || bad "$1（期望 rc=$2，实际 $3）"; }

OP=$(uci -q get onecloud-upgrade.main.provider); OR=$(uci -q get onecloud-upgrade.main.repo)
OB=$(uci -q get onecloud-upgrade.main.base_url); OS=$(uci -q get onecloud-upgrade.main.require_signature)
restore(){
  uci -q set onecloud-upgrade.main.provider="$OP"; uci -q set onecloud-upgrade.main.repo="$OR"
  uci -q set onecloud-upgrade.main.base_url="$OB"; uci -q set onecloud-upgrade.main.require_signature="$OS"
  uci -q commit onecloud-upgrade; rm -rf "$BASE"
}
trap restore EXIT INT TERM

rm -rf "$BASE"; mkdir -p "$BASE/m/schema" "$BASE/m/badsha" "$BASE/m/zerosize" "$BASE/m/weird" "$BASE/root"
VER=$(cat /etc/oc-version)
SHA64=$(printf 'a%.0s' $(seq 1 64))
SHA63=$(printf 'a%.0s' $(seq 1 63))

mk(){ # dir schema version size sha
  cat >"$1/manifest.json" <<EOF
{"schema":$2,"channel":"stable","release":{"version":"$3","build_ts":0},"targets":[{"target":"amlogic/meson8b","boards":["onecloud"],"compatible":["thunder,onecloud"]}],"assets":[{"kind":"rootfs","url":"./rootfs.tar.gz","size":$4,"sha256":"$5"},{"kind":"boot","url":"./boot.tar.gz","size":5572520,"sha256":"$SHA64"}],"flasher":{"type":"dryrun","abi":1}}
EOF
}
mk "$BASE/m/schema" 99 "$VER" 165721125 "$SHA64"
mk "$BASE/m/badsha" 1 "$VER" 165721125 "$SHA63"
mk "$BASE/m/zerosize" 1 "$VER" 0 "$SHA64"
mk "$BASE/m/weird" 1 "weird-tag" 165721125 "$SHA64"

uci -q set onecloud-upgrade.main.provider='local-file'; uci -q set onecloud-upgrade.main.repo=''
uci -q set onecloud-upgrade.main.require_signature='0'; uci -q commit onecloud-upgrade

for c in schema badsha zerosize; do
  uci -q set onecloud-upgrade.main.base_url="$BASE/m/$c"; uci -q commit onecloud-upgrade
  $CTL check >/dev/null 2>&1; eq "清单 $c 被拒" 6 $?
done

uci -q set onecloud-upgrade.main.base_url="$BASE/m/weird"; uci -q commit onecloud-upgrade
_out=$($CTL check 2>&1); eq "未知版本不崩" 0 $?
printf '%s' "$_out" | grep -q '"comparison":"unknown"' && ok "标记为 unknown" || bad "未标记 unknown：$_out"

echo "== 备份目录不可写 =="
FWU_BACKUP_ROOT=/proc/nonexistent sh -c ". $LIB; backup_config /proc/nonexistent/x" >/dev/null 2>&1
eq "备份失败退出 8" 8 $?

echo "== 状态文件损坏 =="
uci -q set onecloud-upgrade.main.base_url="$BASE/m/weird"; uci -q commit onecloud-upgrade
printf 'garbage\nnot=kv\n' >"$BASE/root/state.env"
$CTL status --json >/dev/null 2>&1; eq "损坏状态仍可读" 0 $?

echo "== 并发 check =="
uci -q set onecloud-upgrade.main.base_url="$BASE/m/weird"; uci -q commit onecloud-upgrade
$CTL check >/dev/null 2>&1 & P1=$!
$CTL check >/dev/null 2>&1 & P2=$!
wait $P1; R1=$?; wait $P2; R2=$?
[ "$R1" = "0" ] && [ "$R2" = "0" ] && ok "两次并发均返回 0" || bad "并发返回 $R1/$R2"
grep -q '"schema":1' "$BASE/root/state.json" 2>/dev/null && ok "状态 JSON 仍合法" || bad "状态 JSON 损坏"

printf '故障矩阵第二批: pass=%d fail=%d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
