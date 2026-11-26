#!/bin/sh
# 设备侧：按页面按钮实际调用的 RPC 做一次功能验收
# 覆盖：保存 / 检测 / 升级(演练) / 导出诊断包 / 恢复 / 删除备份 / 日志
# 用法：sh device_ui_actions_test.sh
set -u
U="luci.onecloud-upgrade"
fail=0
ok() { printf '  ok   %s\n' "$1"; }
bad() { printf '  FAIL %s\n' "$1"; fail=$((fail+1)); }
rpc() { ubus -S call "$U" "$@"; }

echo "== 0. 前置快照 =="
rm -rf /tmp/cfg-safety; mkdir -p /tmp/cfg-safety
cp -a /etc/config/. /tmp/cfg-safety/
REPO0=$(uci -q get onecloud-upgrade.main.repo)
TAG0=$(uci -q get onecloud-upgrade.main.tag)
DRY0=$(uci -q get onecloud-upgrade.main.dry_run)
VER0=$(cat /etc/oc-version)
BID0=$(cat /proc/sys/kernel/random/boot_id)
echo "  repo=[$REPO0] tag=[$TAG0] dry_run=$DRY0 ver=$VER0"

echo "== 1. 保存按钮（config_set 全参数）=="
rpc config_set '{"provider":"github-release","repo":"2286927/onecloud-25.12-onlineFirmware","asset_rootfs":"immortalwrt-amlogic-meson8b-thunder-onecloud-rootfs.tar.gz","asset_boot":"onecloud-boot.tar.gz","channel":"stable","tag":"probe-abc","dry_run":"1","force":"0","require_signature":"0"}' >/dev/null
T=$(uci -q get onecloud-upgrade.main.tag)
[ "$T" = "probe-abc" ] && ok "写入 tag=probe-abc" || bad "tag 未写入（[$T]）"

echo "== 2. 清空 tag 再保存 =="
rpc config_set '{"tag":""}' >/dev/null
T=$(uci -q get onecloud-upgrade.main.tag)
[ -z "$T" ] && ok "清空生效" || bad "清空失效（[$T]）"

echo "== 3. 检测按钮（check）=="
U0=$(ubus -S call "$U" status | jsonfilter -e '@.updated_at')
T0=$(date +%s)
rpc check >/dev/null
P=""; ST=""
i=0
while [ $i -lt 150 ]; do
	sleep 1; i=$((i+1))
	ST=$(ubus -S call "$U" status)
	P=$(printf '%s' "$ST" | jsonfilter -e '@.phase')
	U1=$(printf '%s' "$ST" | jsonfilter -e '@.updated_at')
	[ "$U1" != "$U0" ] && case "$P" in ready|idle) break ;; esac
done
T1=$(date +%s)
DETAIL=$(printf '%s' "$ST" | jsonfilter -e '@.detail')
case "$P" in
	ready|idle) ok "检测收敛到 $P（$((T1-T0))s）：$DETAIL" ;;
	*) bad "检测未收敛（phase=$P）" ;;
esac

echo "== 4. 升级按钮（演练模式，不得写盘）=="
if [ "$P" = "ready" ]; then
	V=$(printf '%s' "$ST" | jsonfilter -e '@.version')
	rpc apply "{\"confirm\":\"$V\"}" >/dev/null
	for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
		sleep 2
		P2=$(ubus -S call "$U" status | jsonfilter -e '@.phase')
		case "$P2" in idle) break ;; esac
	done
	ST2=$(ubus -S call "$U" status)
	R=$(printf '%s' "$ST2" | jsonfilter -e '@.last_result')
	D=$(printf '%s' "$ST2" | jsonfilter -e '@.detail')
	[ "$R" = "ok" ] && ok "演练升级收尾 ok：$D" || bad "演练升级异常（$R / $D）"
	[ "$(cat /etc/oc-version)" = "$VER0" ] && ok "版本未变（未写盘）" || bad "演练却改了版本"
	[ "$(cat /proc/sys/kernel/random/boot_id)" = "$BID0" ] && ok "未重启" || bad "演练却重启了"
else
	echo "  跳过：当前无可升级版本（phase=$P）"
fi

echo "== 4b. 升级按钮（force=1 + dry_run=1，应完整走完但不写盘）=="
uci -q set onecloud-upgrade.main.force='1'; uci -q commit onecloud-upgrade
U0=$(ubus -S call "$U" status | jsonfilter -e '@.updated_at')
rpc check >/dev/null
i=0
while [ $i -lt 150 ]; do
	sleep 1; i=$((i+1))
	ST=$(ubus -S call "$U" status)
	P=$(printf '%s' "$ST" | jsonfilter -e '@.phase')
	U1=$(printf '%s' "$ST" | jsonfilter -e '@.updated_at')
	[ "$U1" != "$U0" ] && [ "$P" = "ready" ] && break
done
if [ "$P" = "ready" ]; then
	V=$(printf '%s' "$ST" | jsonfilter -e '@.version')
	ok "force 模式下 ready（目标 $V）"
	rpc apply "{\"confirm\":\"$V\"}" >/dev/null
	P2=""
	i=0
	while [ $i -lt 30 ]; do
		sleep 2; i=$((i+1))
		ST2=$(ubus -S call "$U" status)
		P2=$(printf '%s' "$ST2" | jsonfilter -e '@.phase')
		case "$P2" in idle) break ;; esac
	done
	R=$(printf '%s' "$ST2" | jsonfilter -e '@.last_result')
	D=$(printf '%s' "$ST2" | jsonfilter -e '@.detail')
	[ "$R" = "ok" ] && ok "升级链路收尾 ok：$D" || bad "升级链路异常（$R / $D）"
	[ "$(cat /etc/oc-version)" = "$VER0" ] && ok "版本未变（演练未写盘）" || bad "演练却改了版本"
	[ "$(cat /proc/sys/kernel/random/boot_id)" = "$BID0" ] && ok "未重启" || bad "演练却重启了"
else
	bad "force 模式未进入 ready（phase=$P）"
fi
uci -q set onecloud-upgrade.main.force='0'; uci -q commit onecloud-upgrade

echo "== 5. 导出诊断包按钮（diag）=="
OUT=$(rpc diag)
PTH=$(printf '%s' "$OUT" | jsonfilter -e '@.path')
[ -f "$PTH" ] && ok "诊断包已生成：$PTH" || bad "诊断包未生成（$OUT）"
if [ -f "$PTH" ]; then
	N=$(tar -tzf "$PTH" 2>/dev/null | grep -vc '/$')
	[ "$N" = "6" ] && ok "含 6 个条目" || bad "条目数异常：$N"
	tar -xzOf "$PTH" journal-tail.txt 2>/dev/null | grep -q 'token=' && bad "日志未脱敏（含 token=）" || ok "日志已脱敏"
	tar -tzf "$PTH" 2>/dev/null | grep -q '^config/' && bad "诊断包含 /etc/config 内容" || ok "不含配置文件内容"
fi

echo "== 6. 恢复按钮（rollback merge）=="
BL=$(ubus -S call "$U" backups | jsonfilter -e '@.backups[*].id' 2>/dev/null | tr '\n' ' ')
FIRST=$(echo $BL | awk '{print $1}')
if [ -n "$FIRST" ]; then
	N0=$(ls /etc/config | wc -l)
	rpc rollback "{\"id\":\"$FIRST\",\"mode\":\"merge\"}" >/dev/null; RC=$?
	N1=$(ls /etc/config | wc -l)
	[ "$N1" -ge $((N0 - 1)) ] && ok "merge 恢复后配置仍在（$N0→$N1）" || bad "配置数量异常（$N0→$N1）"
	uci -q get system.@system[0].hostname >/dev/null 2>&1 && ok "uci 仍可读" || bad "uci 读取失败"
else
	echo "  跳过：没有可用备份"
fi

echo "== 7. 删除按钮（forget）=="
# 「最新一份」按 mtime 判定（与 forget 的判定一致），跨本应用与现网脚本两类备份
NEWDIR=$(ls -dt /opt/fwupgrade/backup/* /opt/upgrade-backup-* 2>/dev/null | head -n 1)
NEWID=$(basename "$NEWDIR")
echo "  最新（受保护）：$NEWID"
OUT=$(rpc forget "{\"id\":\"$NEWID\"}")
printf '%s' "$OUT" | grep -q '"ok":false' && ok "最新备份被拒删" || bad "最新备份未被拒（$OUT）"
[ -d "$NEWDIR" ] && ok "受保护备份仍在" || bad "受保护备份被删了"

OTHER=$(ubus -S call "$U" backups | jsonfilter -e '@.backups[*].id' 2>/dev/null | grep -vx "$NEWID" | head -n 1)
if [ -n "$OTHER" ]; then
	rpc forget "{\"id\":\"$OTHER\"}" >/dev/null
	ubus -S call "$U" backups | jsonfilter -e '@.backups[*].id' | grep -qx "$OTHER" && bad "普通备份未删除（$OTHER）" || ok "普通备份已删除（$OTHER）"
else
	echo "  跳过：没有第二份备份可删"
fi

echo "== 8. 日志按钮（log_tail）=="
L=$(rpc log_tail '{"lines":5}' | jsonfilter -e '@.lines')
[ -n "$L" ] && ok "日志有内容（$(printf '%s' "$L" | grep -c .) 行）" || bad "日志为空"

echo "== 9. 还原配置 =="
uci -q set "onecloud-upgrade.main.repo=$REPO0"
uci -q set "onecloud-upgrade.main.tag=$TAG0"
uci -q set "onecloud-upgrade.main.dry_run=$DRY0"
uci -q commit onecloud-upgrade
[ "$(uci -q get onecloud-upgrade.main.repo)" = "$REPO0" ] && ok "repo 已还原" || bad "repo 未还原"
[ "$(uci -q get onecloud-upgrade.main.dry_run)" = "$DRY0" ] && ok "dry_run 已还原" || bad "dry_run 未还原"

echo "结果: fail=$fail"
[ "$fail" = 0 ] && exit 0 || exit 1
