#!/bin/sh
# flasher: onecloud —— 委托现网 /usr/bin/upgrade，不自建写入逻辑。
# 这样做的理由：848 行脚本已吸收并发、混合态、爆盘三次真实事故，重写等于重踩。
# 本文件既可被 worker source，也可直接执行：sh onecloud.sh prepare

UP_BIN="${UP_BIN:-/usr/bin/upgrade}"
UP_LOG="${UP_LOG:-$FWU_ROOT/upgrade.log}"

flasher_caps() {
    printf '{"type":"onecloud-emmc","abi":1,"write_mode":"in-place","keep_policy":"exclude-list","rollback":"config-only","auto_reboot":true}'
}

flasher_preflight() {
    [ -x "$UP_BIN" ] || { log "预检失败：$UP_BIN 不存在或不可执行"; return 1; }
    [ -r /usr/lib/oc-upgrade.sh ] || { log "预检失败：/usr/lib/oc-upgrade.sh 缺失"; return 1; }

    # 身份（清单声明了才校验；兼容模式下跳过并留痕）
    if [ -n "$(mget TARGET_0_TARGET)" ]; then
        _local=$(sed -n "s/^DISTRIB_TARGET='\(.*\)'/\1/p" /etc/openwrt_release 2>/dev/null)
        [ "$(mget TARGET_0_TARGET)" = "$_local" ] || { log "预检失败：target 不符"; return 1; }
    fi

    _free=$(free_kb /opt)
    case "$_free" in ''|*[!0-9]*) log "预检失败：读不到 /opt 空间"; return 1 ;; esac
    [ "$_free" -ge $((220 * 1024)) ] || { log "预检失败：/opt 可用 $((_free / 1024)) MiB，低于 220 MiB"; return 1; }

    _sha=$(sha256sum /usr/lib/oc-upgrade.sh 2>/dev/null | awk '{print $1}')
    log "预检通过：script_sha=${_sha:-unknown} free=$((_free / 1024))MiB"
    return 0
}

# 预取：交给 upgrade --check（下载 + sha256 + 空间门槛都在脚本内）
flasher_prepare() {
    log "预取开始：$UP_BIN --check"
    "$UP_BIN" --check >>"$UP_LOG" 2>&1
    _rc=$?
    log "预取结束：rc=$_rc（日志 $UP_LOG）"
    return "$_rc"
}

# 写入：这一步会让设备重启，本进程随之中断
#
# 为什么要带 --url：设备脚本默认自己去 /releases/latest（或 /etc/oc-repo）找目标，
# 完全不看应用解析出的清单。于是会出现「应用说可升 26.11.21，脚本却按自己的仓库判定
# 已是最新、直接退出 0」的假象（2026-11-26 实测）。修法：
#   ① --url=<清单里的 rootfs 直链> —— 脚本从 URL 的 /download/<TAG>/ 派生目标版本；
#   ② OC_REPO=<应用配置的仓库>    —— 脚本去同一个仓库、同一个 TAG 取 sha256 校验。
# 两者都设，才是真正「按清单升级」。
flasher_apply() {
    _u=$(asset_url_by_role rootfs)
    [ -n "$_u" ] || { log "写入失败：清单里没有 rootfs 资产地址，拒绝调用设备脚本"; return 2; }
    if [ -n "${C_REPO:-}" ]; then
        OC_REPO="$C_REPO"; export OC_REPO
    fi
    if [ "${C_FORCE:-0}" = "1" ]; then
        log "写入开始：$UP_BIN --reboot --force --url=<rootfs>（OC_REPO=${C_REPO:-未设}，同版本强制重刷）"
        "$UP_BIN" --reboot --force --url="$_u" >>"$UP_LOG" 2>&1
    else
        log "写入开始：$UP_BIN --reboot --url=<rootfs>（OC_REPO=${C_REPO:-未设}）"
        "$UP_BIN" --reboot --url="$_u" >>"$UP_LOG" 2>&1
    fi
    return $?
}

# 直接执行入口（被 source 时 $0 是 worker.sh，不会走到这里）
case "${0##*/}" in
    onecloud.sh)
        . "${FWU_LIBDIR:-/usr/libexec/fwupgrade}/lib.sh"
        WORK="$FWU_ROOT/work"
        [ -s "$WORK/manifest.json" ] && manifest_load "$WORK/manifest.json"
        case "${1:-}" in
            preflight) flasher_preflight ;;
            prepare) flasher_prepare ;;
            apply) flasher_apply ;;
            caps) flasher_caps ;;
            *) echo "用法: onecloud.sh preflight|prepare|apply|caps" >&2; exit 2 ;;
        esac
        ;;
esac
