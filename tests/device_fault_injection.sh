#!/bin/sh
# 设备侧关键故障注入：全部不写 boot、不重启。
# 用法（设备上）：sh /tmp/fault_injection.sh
set -u
CTL=/usr/libexec/fwupgrade/fwupgradectl
BASE=/tmp/fi
export FWU_ROOT=$BASE/root FWU_LOCK=$BASE/lock
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  ok   $1"; }
bad(){ FAIL=$((FAIL+1)); echo "  FAIL $1"; }
check_rc(){ # desc expected actual
    [ "$3" = "$2" ] && ok "$1（rc=$3）" || bad "$1（期望 rc=$2，实际 rc=$3）"
}
contains(){ printf '%s' "$2" | grep -q "$3" && ok "$1" || bad "$1（输出里没有“$3”：$2）"; }

# 备份当前配置
OLD_PROVIDER=$(uci -q get onecloud-upgrade.main.provider || echo github-release)
OLD_REPO=$(uci -q get onecloud-upgrade.main.repo || echo "")
OLD_BASE=$(uci -q get onecloud-upgrade.main.base_url || echo "")
OLD_DRY=$(uci -q get onecloud-upgrade.main.dry_run || echo 1)
OLD_FORCE=$(uci -q get onecloud-upgrade.main.force || echo 0)
restore(){
    uci -q set onecloud-upgrade.main.provider="$OLD_PROVIDER"
    uci -q set onecloud-upgrade.main.repo="$OLD_REPO"
    uci -q set onecloud-upgrade.main.base_url="$OLD_BASE"
    uci -q set onecloud-upgrade.main.dry_run="$OLD_DRY"
    uci -q set onecloud-upgrade.main.force="$OLD_FORCE"
    uci -q commit onecloud-upgrade
    umount /tmp/fi-small 2>/dev/null
    rm -rf /tmp/fi-small "$BASE"
}
trap restore EXIT INT TERM

rm -rf "$BASE"; mkdir -p "$BASE/manifests/good" "$BASE/manifests/bootmissing" "$BASE/manifests/badtarget" "$BASE/root"

VER=$(cat /etc/oc-version)
mkmanifest(){ # dir target boot?
    _d=$1; _t=$2; _boot=$3
    _assets="{\"kind\":\"rootfs\",\"url\":\"./rootfs.tar.gz\",\"size\":165721125,\"sha256\":\"$(printf 'a%.0s' $(seq 1 64))\"}"
    [ "$_boot" = "1" ] && _assets="$_assets,{\"kind\":\"boot\",\"url\":\"./boot.tar.gz\",\"size\":5572520,\"sha256\":\"$(printf 'b%.0s' $(seq 1 64))\"}"
    cat >"$_d/manifest.json" <<EOF
{"schema":1,"channel":"stable","release":{"version":"$VER","build_ts":0},"targets":[{"target":"$_t","boards":["onecloud"],"compatible":["thunder,onecloud"]}],"assets":[${_assets}],"flasher":{"type":"dryrun","abi":1}}
EOF
}
mkmanifest "$BASE/manifests/good" "amlogic/meson8b" 1
mkmanifest "$BASE/manifests/bootmissing" "amlogic/meson8b" 0
mkmanifest "$BASE/manifests/badtarget" "x86/64" 1

echo "== A 配置缺失（repo 为空）=="
uci -q set onecloud-upgrade.main.provider='github-release'; uci -q set onecloud-upgrade.main.repo=''
uci -q commit onecloud-upgrade
_out=$($CTL check 2>&1); _rc=$?
check_rc "缺 repo 拒绝" 2 $_rc
contains "错误指向具体字段" "$_out" "配置缺失"

echo "== B 清单缺 boot 资产 =="
uci -q set onecloud-upgrade.main.provider='local-file'; uci -q set onecloud-upgrade.main.base_url="$BASE/manifests/bootmissing"
uci -q commit onecloud-upgrade
_out=$($CTL check 2>&1); _rc=$?
check_rc "半套固件被拒" 6 $_rc
contains "说明缺 boot" "$_out" "boot"

echo "== C 目标平台不符 =="
uci -q set onecloud-upgrade.main.base_url="$BASE/manifests/badtarget"; uci -q commit onecloud-upgrade
_out=$($CTL check 2>&1); _rc=$?
check_rc "平台不符被拒" 3 $_rc
contains "说明平台不符" "$_out" "目标平台不符"

echo "== D 空间不足 =="
mkdir -p /tmp/fi-small
mount -t tmpfs -o size=8m tmpfs /tmp/fi-small 2>/dev/null || echo "  (tmpfs 挂载失败，跳过该条)"
if mountpoint -q /tmp/fi-small 2>/dev/null || grep -q ' /tmp/fi-small ' /proc/mounts; then
    uci -q set onecloud-upgrade.main.base_url="$BASE/manifests/good"; uci -q commit onecloud-upgrade
    _out=$(FWU_ROOT=/tmp/fi-small/root FWU_SPACE_PATH=/tmp/fi-small $CTL check 2>&1); _rc=$?
    check_rc "空间门槛拒绝" 4 $_rc
    contains "给出需要/可用" "$_out" "空间不足"
fi

echo "== E 重复 apply（dry_run=1，不写盘）=="
uci -q set onecloud-upgrade.main.base_url="$BASE/manifests/good"
uci -q set onecloud-upgrade.main.dry_run='1'; uci -q set onecloud-upgrade.main.force='1'
uci -q commit onecloud-upgrade
$CTL check >/dev/null 2>&1
_out1=$($CTL apply --confirm "$VER" 2>&1); _rc1=$?
_out2=$($CTL apply --confirm "$VER" 2>&1); _rc2=$?
check_rc "第一次受理" 0 $_rc1
contains "第二次被拒" "$_out2" "不可升级"
sleep 6

echo "== F 回滚不存在的备份 =="
_out=$($CTL rollback --confirm no-such-backup 2>&1); _rc=$?
check_rc "未知备份被拒" 2 $_rc
contains "说明找不到" "$_out" "找不到备份"

echo "== G 非法备份 ID（路径穿越）=="
_out=$($CTL forget --confirm ../etc 2>&1); _rc=$?
check_rc "穿越被拒" 2 $_rc
contains "说明 ID 非法" "$_out" "非法"

printf '故障注入: pass=%d fail=%d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
