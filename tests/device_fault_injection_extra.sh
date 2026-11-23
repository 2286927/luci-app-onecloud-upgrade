#!/bin/sh
# 补充故障注入：坏 JSON / 缺 rootfs / 未知 provider
set -u
CTL=/usr/libexec/fwupgrade/fwupgradectl
BASE=/tmp/fi2
export FWU_ROOT=$BASE/root FWU_LOCK=$BASE/lock
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  ok   $1"; }
bad(){ FAIL=$((FAIL+1)); echo "  FAIL $1"; }
eq(){ [ "$2" = "$3" ] && ok "$1（rc=$3）" || bad "$1（期望 rc=$2，实际 $3）"; }

OP=$(uci -q get onecloud-upgrade.main.provider || echo github-release)
OR=$(uci -q get onecloud-upgrade.main.repo || echo "")
OB=$(uci -q get onecloud-upgrade.main.base_url || echo "")
restore(){
    uci -q set onecloud-upgrade.main.provider="$OP"
    uci -q set onecloud-upgrade.main.repo="$OR"
    uci -q set onecloud-upgrade.main.base_url="$OB"
    uci -q commit onecloud-upgrade
    rm -rf "$BASE"
}
trap restore EXIT INT TERM

rm -rf "$BASE"; mkdir -p "$BASE/m/badjson" "$BASE/m/bootonly" "$BASE/root"
printf '{not json' >"$BASE/m/badjson/manifest.json"
VER=$(cat /etc/oc-version)
SHA=$(printf 'b%.0s' $(seq 1 64))
cat >"$BASE/m/bootonly/manifest.json" <<EOF
{"schema":1,"channel":"stable","release":{"version":"$VER","build_ts":0},"targets":[{"target":"amlogic/meson8b"}],"assets":[{"kind":"boot","url":"./boot.tar.gz","size":5572520,"sha256":"$SHA"}],"flasher":{"type":"dryrun","abi":1}}
EOF

uci -q set onecloud-upgrade.main.provider='local-file'; uci -q set onecloud-upgrade.main.repo=''
uci -q set onecloud-upgrade.main.base_url="$BASE/m/badjson"; uci -q commit onecloud-upgrade
$CTL check >/dev/null 2>&1; eq "坏 JSON 被拒" 6 $?

uci -q set onecloud-upgrade.main.base_url="$BASE/m/bootonly"; uci -q commit onecloud-upgrade
$CTL check >/dev/null 2>&1; eq "缺 rootfs 被拒" 6 $?

uci -q set onecloud-upgrade.main.provider='bogus'; uci -q commit onecloud-upgrade
$CTL check >/dev/null 2>&1; eq "未知 provider 被拒" 2 $?

printf '补充故障注入: pass=%d fail=%d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
