#!/bin/sh
# 并发 check 复测：两个进程同时跑，期望都返回 0 且状态 JSON 合法
set -u
CTL=/usr/libexec/fwupgrade/fwupgradectl
BASE=/tmp/fi4
export FWU_ROOT=$BASE/root FWU_LOCK=$BASE/lock
OP=$(uci -q get onecloud-upgrade.main.provider); OR=$(uci -q get onecloud-upgrade.main.repo)
OB=$(uci -q get onecloud-upgrade.main.base_url); OS=$(uci -q get onecloud-upgrade.main.require_signature)
restore(){
  uci -q set onecloud-upgrade.main.provider="$OP"; uci -q set onecloud-upgrade.main.repo="$OR"
  uci -q set onecloud-upgrade.main.base_url="$OB"; uci -q set onecloud-upgrade.main.require_signature="$OS"
  uci -q commit onecloud-upgrade; rm -rf "$BASE"
}
trap restore EXIT INT TERM

rm -rf "$BASE"; mkdir -p "$BASE/m" "$BASE/root"
SHA=$(printf 'a%.0s' $(seq 1 64)); VER=$(cat /etc/oc-version)
cat >"$BASE/m/manifest.json" <<EOF
{"schema":1,"channel":"stable","release":{"version":"$VER","build_ts":0},"targets":[{"target":"amlogic/meson8b"}],"assets":[{"kind":"rootfs","url":"./r","size":165721125,"sha256":"$SHA"},{"kind":"boot","url":"./b","size":5572520,"sha256":"$SHA"}],"flasher":{"type":"dryrun","abi":1}}
EOF
uci -q set onecloud-upgrade.main.provider='local-file'; uci -q set onecloud-upgrade.main.repo=''
uci -q set onecloud-upgrade.main.base_url="$BASE/m"; uci -q set onecloud-upgrade.main.require_signature='0'
uci -q commit onecloud-upgrade

$CTL check >/dev/null 2>&1 & P1=$!
$CTL check >/dev/null 2>&1 & P2=$!
wait $P1; R1=$?; wait $P2; R2=$?
echo "concurrent rc=$R1/$R2"
grep -q '"schema":1' "$BASE/root/state.json" 2>/dev/null && echo JSON_OK || echo JSON_BAD
[ "$R1" = "0" ] && [ "$R2" = "0" ]
