#!/bin/sh
# 长尾故障（非破坏性）：时钟、缺 usign、缺公钥、签名损坏、404、连接拒绝
set -u
CTL=/usr/libexec/fwupgrade/fwupgradectl
BASE=/tmp/fi5
export FWU_ROOT=$BASE/root FWU_LOCK=$BASE/lock
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  ok   $1"; }
bad(){ FAIL=$((FAIL+1)); echo "  FAIL $1"; }
eq(){ [ "$2" = "$3" ] && ok "$1（rc=$3）" || bad "$1（期望 rc=$2，实际 $3）"; }
has(){ printf '%s' "$2" | grep -q "$3" && ok "$1" || bad "$1（缺少“$3”）"; }

OP=$(uci -q get onecloud-upgrade.main.provider); OR=$(uci -q get onecloud-upgrade.main.repo)
OB=$(uci -q get onecloud-upgrade.main.base_url); OS=$(uci -q get onecloud-upgrade.main.require_signature)
USIGN_MOVED=0; PUB_MOVED=0; SIG_BAK=0
restore(){
  [ "$USIGN_MOVED" = "1" ] && mv -f /usr/bin/usign.bak /usr/bin/usign
  [ "$PUB_MOVED" = "1" ] && mv -f /etc/fwupgrade/pubkey.oc-2026.bak /etc/fwupgrade/pubkey.oc-2026
  [ "$SIG_BAK" = "1" ] && mv -f "$BASE/signed/manifest.json.sig.bak" "$BASE/signed/manifest.json.sig"
  uci -q set onecloud-upgrade.main.provider="$OP"; uci -q set onecloud-upgrade.main.repo="$OR"
  uci -q set onecloud-upgrade.main.base_url="$OB"; uci -q set onecloud-upgrade.main.require_signature="$OS"
  uci -q commit onecloud-upgrade; rm -rf "$BASE"
}
trap restore EXIT INT TERM

rm -rf "$BASE"; mkdir -p "$BASE/m" "$BASE/signed" "$BASE/root"
SHA=$(printf 'a%.0s' $(seq 1 64)); VER=$(cat /etc/oc-version)
cat >"$BASE/m/manifest.json" <<EOF
{"schema":1,"channel":"stable","release":{"version":"$VER","build_ts":0},"targets":[{"target":"amlogic/meson8b"}],"assets":[{"kind":"rootfs","url":"./r","size":165721125,"sha256":"$SHA"},{"kind":"boot","url":"./b","size":5572520,"sha256":"$SHA"}],"flasher":{"type":"dryrun","abi":1}}
EOF
# 已签名的清单（上传到 /tmp/signed）
cp /tmp/signed-src/manifest.json "$BASE/signed/manifest.json" 2>/dev/null || true
cp /tmp/signed-src/manifest.json.sig "$BASE/signed/manifest.json.sig" 2>/dev/null || true

uci -q set onecloud-upgrade.main.provider='local-file'; uci -q set onecloud-upgrade.main.repo=''

echo "== A 设备时间不正确 =="
uci -q set onecloud-upgrade.main.base_url="$BASE/m"; uci -q set onecloud-upgrade.main.require_signature='0'; uci -q commit onecloud-upgrade
_out=$(FWU_NOW_OVERRIDE=1000000000 $CTL check 2>&1); eq "时钟预检拒绝" 3 $?
has "说明时间问题" "$_out" "设备时间不正确"

echo "== B 缺 usign（要求签名）=="
if [ -s "$BASE/signed/manifest.json" ] && [ -s "$BASE/signed/manifest.json.sig" ]; then
  uci -q set onecloud-upgrade.main.base_url="$BASE/signed"; uci -q set onecloud-upgrade.main.require_signature='1'; uci -q commit onecloud-upgrade
  mv /usr/bin/usign /usr/bin/usign.bak && USIGN_MOVED=1
  _out=$($CTL check 2>&1); eq "缺 usign 拒绝" 6 $?
  has "说明缺 usign" "$_out" "缺少 usign"
  mv -f /usr/bin/usign.bak /usr/bin/usign; USIGN_MOVED=0

  echo "== C 缺公钥 =="
  mv /etc/fwupgrade/pubkey.oc-2026 /etc/fwupgrade/pubkey.oc-2026.bak && PUB_MOVED=1
  _out=$($CTL check 2>&1); eq "缺公钥拒绝" 6 $?
  has "说明缺公钥" "$_out" "未找到公钥"
  mv -f /etc/fwupgrade/pubkey.oc-2026.bak /etc/fwupgrade/pubkey.oc-2026; PUB_MOVED=0

  echo "== D 签名损坏 =="
  cp "$BASE/signed/manifest.json.sig" "$BASE/signed/manifest.json.sig.bak"; SIG_BAK=1
  printf 'x' >>"$BASE/signed/manifest.json.sig"
  _out=$($CTL check 2>&1); eq "坏签名拒绝" 6 $?
  has "说明验签失败" "$_out" "签名校验失败"
  mv -f "$BASE/signed/manifest.json.sig.bak" "$BASE/signed/manifest.json.sig"; SIG_BAK=0
else
  echo "  (缺少已签名样例，跳过 B/C/D)"
fi

echo "== E 源 404 =="
uci -q set onecloud-upgrade.main.provider='static-https'; uci -q set onecloud-upgrade.main.base_url='http://127.0.0.1:8080/no-such-dir'; uci -q set onecloud-upgrade.main.require_signature='0'; uci -q commit onecloud-upgrade
_out=$($CTL check 2>&1); eq "404 拒绝" 5 $?
has "说明取清单失败" "$_out" "manifest.json"

echo "== F 连接拒绝 =="
uci -q set onecloud-upgrade.main.base_url='http://127.0.0.1:1'; uci -q commit onecloud-upgrade
_out=$($CTL check 2>&1); eq "拒绝连接" 5 $?

printf '长尾故障: pass=%d fail=%d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
