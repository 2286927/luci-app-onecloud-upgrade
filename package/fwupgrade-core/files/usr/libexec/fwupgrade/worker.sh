#!/bin/sh
# worker.sh —— 真正的执行者。由 CLI 用 setsid 拉起，不依赖发起它的会话。
# 互斥、状态迁移、失败处置都在这里；CLI 只负责校验参数与受理。
. "${FWU_LIBDIR:-/usr/libexec/fwupgrade}/lib.sh"

WORK="$FWU_ROOT/work"
CMD="${1:-}"
JOB="${2:-}"

usage() {
    echo "用法: worker.sh apply <job_id>" >&2
    exit "$EX_USAGE"
}

case "$CMD" in
    apply) ;;
    *) usage ;;
esac

lock_acquire
_rc=$?
if [ "$_rc" -eq 1 ]; then
    log "拒绝：已有任务在跑"
    exit "$EX_USAGE"
fi
if [ "$_rc" -eq 2 ]; then
    log "拒绝：上次已进入 writing_boot 且未确认重启"
    state_replace "phase=unknown" "last_result=failed" "code=$EX_STATE" \
        "mixed_state=H1" "detail=上次写入 boot 后未确认重启，请先核对再操作" "updated_at=$(iso_now)"
    exit "$EX_STATE"
fi
trap 'lock_release' EXIT INT TERM

config_load
[ -s "$WORK/manifest.json" ] || {
    state_replace "phase=idle" "last_result=failed" "code=$EX_STATE" "progress=0" "detail=缺少已检测的清单"
    exit "$EX_STATE"
}
manifest_load "$WORK/manifest.json"

FLASHER=$(flasher_name)
if [ "${C_DRY_RUN:-1}" = "1" ]; then
    log "演练模式开启（dry_run=1）：本次不会写盘"
    FLASHER="dryrun"
fi
FLASHER_PATH="$FWU_LIBDIR/flashers/$FLASHER.sh"
[ -x "$FLASHER_PATH" ] || [ -f "$FLASHER_PATH" ] || {
    state_replace "phase=idle" "last_result=failed" "code=$EX_NOIMPL" "detail=flasher 未安装：$FLASHER"
    exit "$EX_NOIMPL"
}

lock_update_phase applying
state_replace "phase=applying" "last_result=none" "job_id=$JOB" "progress=5" \
    "version=$M_VERSION" "target=$M_TARGET" "detail=执行预检" "updated_at=$(iso_now)"

# shellcheck disable=SC1090
. "$FLASHER_PATH"

if ! flasher_preflight; then
    state_replace "phase=idle" "last_result=failed" "code=$EX_STATE" "progress=0" "detail=预检未通过"
    exit "$EX_STATE"
fi

state_replace "phase=applying" "progress=40" "detail=预检通过，进入写入" "updated_at=$(iso_now)"

# L1 安全网：真实写入前先把 /etc/config 备份到可寻址目录；dry-run 不占空间
if [ "${C_DRY_RUN:-1}" != "1" ]; then
    backup_config "$FWU_ROOT/backup/$JOB" || {
        state_replace "phase=idle" "last_result=failed" "code=$EX_STATE" "progress=0" "detail=配置备份失败，已中止"
        exit "$EX_STATE"
    }
    state_replace "phase=applying" "progress=45" "detail=配置已备份到 backup/$JOB" "updated_at=$(iso_now)"
fi

# 从这一刻起不可逆：先落盘标记，再调用写入。写入成功后设备会重启，本进程随之中断。
lock_update_phase writing_boot
state_replace "phase=writing_boot" "progress=70" "detail=正在写入（boot 为最后一步）" "updated_at=$(iso_now)"

flasher_apply
_rc=$?

if [ "$_rc" -eq 0 ]; then
    if [ "$FLASHER" = "dryrun" ]; then
        # dry-run 不写盘、不重启，直接收尾；不能套用「写成功未重启」的判定
        state_replace "phase=idle" "last_result=ok" "code=0" "progress=100" \
            "detail=dry-run 完成（未写盘）" "updated_at=$(iso_now)"
        exit 0
    fi
    # rc=0 有两种含义，必须分开：写入完成并调度重启；或设备脚本判定「已是最新」直接退出。
    # 后者一个字节都没写，若记成 boot_written，要等 15 分钟无重启才判失败，还会误报「重启已调度」。
    # 设备脚本对这两种情况都会写 /opt/oc-upgrade.last，用记录类型 + 时间戳区分。
    _last=$(tail -n 1 "$FWU_LAST_FILE" 2>/dev/null)
    case "$_last" in
        *uptodate*)
            _lts=$(date -d "$(printf '%s' "$_last" | cut -d' ' -f1-2)" +%s 2>/dev/null)
            _st=$(state_get apply_started)
            case "$_lts" in ''|*[!0-9]*) _lts=0 ;; esac
            if [ "$_lts" -ge "${_st:-0}" ] 2>/dev/null; then
                state_replace "phase=idle" "last_result=failed" "code=$EX_STATE" "progress=0" "mixed_state=N" \
                    "detail=设备脚本判定已是最新、未写入（$_last）；请核对目标版本与 --url/OC_REPO 指向" \
                    "updated_at=$(iso_now)"
                exit "$EX_STATE"
            fi
            ;;
    esac

    # onecloud 的 upgrade --reboot 会把重启丢到 setsid 子进程并立即返回 0，
    # 所以 rc=0 只代表「写入完成、重启已调度」，不代表失败。
    # 真正的判定交给引导后的 recover（比对 /etc/oc-version）与 uptime。
    lock_update_phase boot_written
    state_replace "phase=boot_written" "last_result=none" "code=0" "mixed_state=N" \
        "detail=写入完成，重启已调度，等待引导后判定" "updated_at=$(iso_now)"
    exit 0
fi

state_replace "phase=idle" "last_result=failed" "code=$_rc" "progress=0" \
    "detail=写入失败（退出码 $_rc），系统可能处于混合态，请核对" "updated_at=$(iso_now)"
exit "$_rc"
