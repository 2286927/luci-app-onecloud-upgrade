#!/bin/sh
# 设备侧：验证 config_set 对「空值」与「未传字段」的区分
#
# 背景：曾经用 [ -n "$_v" ] || continue 过滤，导致用户清空「指定 tag」后被当成
#       「没传这个字段」而跳过，保存刷新后旧值又回来了。
#
# 用法：sh tests/device_config_set.sh
# 会临时改动 tag/repo，结束时恢复原值。
set -u
U="luci.onecloud-upgrade"
fail=0
ok() { printf '  ok   %s\n' "$1"; }
bad() { printf '  FAIL %s\n' "$1"; fail=$((fail+1)); }

TAG0=$(uci -q get onecloud-upgrade.main.tag)
REPO0=$(uci -q get onecloud-upgrade.main.repo)
restore() {
	uci -q set "onecloud-upgrade.main.tag=$TAG0"
	uci -q set "onecloud-upgrade.main.repo=$REPO0"
	uci -q commit onecloud-upgrade
}
trap 'restore' EXIT INT TERM

echo "== 前置 =="
echo "  原始 tag=[$TAG0] repo=[$REPO0]"

echo "== 1. 显式传空串：应能清空 =="
ubus -S call "$U" config_set '{"tag":""}' >/dev/null 2>&1
T=$(uci -q get onecloud-upgrade.main.tag)
[ -z "$T" ] && ok "tag 已被清空" || bad "tag 未被清空（[$T]），清空被当成「未传」跳过了"

echo "== 2. 不传该字段：应保持原值（此时为空） =="
ubus -S call "$U" config_set '{"repo":"'"$REPO0"'"}' >/dev/null 2>&1
T=$(uci -q get onecloud-upgrade.main.tag)
[ -z "$T" ] && ok "未传 tag 时保持为空" || bad "未传 tag 却被改写（[$T]）"

echo "== 3. 传具体值：应写入 =="
ubus -S call "$U" config_set '{"tag":"probe-tag"}' >/dev/null 2>&1
T=$(uci -q get onecloud-upgrade.main.tag)
[ "$T" = "probe-tag" ] && ok "tag 已写入" || bad "tag 未写入（[$T]）"

echo "== 4. 再清空一次：应再次生效 =="
ubus -S call "$U" config_set '{"tag":""}' >/dev/null 2>&1
T=$(uci -q get onecloud-upgrade.main.tag)
[ -z "$T" ] && ok "再次清空生效" || bad "再次清空失效（[$T]）"

echo "== 5. 非法枚举值不应写入 =="
C0=$(uci -q get onecloud-upgrade.main.channel)
ubus -S call "$U" config_set '{"channel":"nonsense"}' >/dev/null 2>&1
C=$(uci -q get onecloud-upgrade.main.channel)
[ "$C" = "$C0" ] && ok "非法 channel 被拒（保持 $C0）" || bad "非法 channel 被写入（$C）"

restore
trap - EXIT INT TERM
T=$(uci -q get onecloud-upgrade.main.tag)
[ "$T" = "$TAG0" ] && ok "配置已恢复原值" || bad "配置未恢复（[$T] vs [$TAG0]）"

echo "结果: fail=$fail"
[ "$fail" = 0 ] && exit 0 || exit 1
