#!/bin/sh
# flasher: dryrun —— 全链路跑通但永不写盘。用于 CI 与新设备接入验证。
DRY_DIR="${DRY_DIR:-$FWU_ROOT/dryrun}"

flasher_caps() {
    printf '{"type":"dryrun","abi":1,"write_mode":"none","keep_policy":"none","rollback":"none","auto_reboot":false}'
}

flasher_preflight() {
    mkdir -p "$DRY_DIR" 2>/dev/null || { log "dryrun：无法创建 $DRY_DIR"; return 1; }
    log "dryrun 预检通过（不会写盘）"
    return 0
}

flasher_prepare() {
    log "dryrun 预取：只记录清单，不下载"
    cp -f "$WORK/manifest.json" "$DRY_DIR/manifest.json" 2>/dev/null || true
    return 0
}

flasher_apply() {
    log "dryrun 写入：模拟阶段迁移，不触碰任何块设备"
    for _p in writing_rootfs resizing writing_boot; do
        sleep 1
        log "dryrun 阶段：$_p"
    done
    printf '{"simulated":true,"at":"%s"}\n' "$(iso_now)" >"$DRY_DIR/boot-report.json"
    return 0
}

case "${0##*/}" in
    dryrun.sh)
        . "${FWU_LIBDIR:-/usr/libexec/fwupgrade}/lib.sh"
        WORK="$FWU_ROOT/work"
        [ -s "$WORK/manifest.json" ] && manifest_load "$WORK/manifest.json"
        case "${1:-}" in
            preflight) flasher_preflight ;;
            prepare) flasher_prepare ;;
            apply) flasher_apply ;;
            caps) flasher_caps ;;
            *) echo "用法: dryrun.sh preflight|prepare|apply|caps" >&2; exit 2 ;;
        esac
        ;;
esac
