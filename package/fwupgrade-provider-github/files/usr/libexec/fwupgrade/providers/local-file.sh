#!/bin/sh
# provider: local-file —— 从本地目录/文件取 manifest（离线包、U 盘、开发测试）
provider_resolve() {
    _work="$1"
    mkdir -p "$_work" || die "$EX_STATE" "无法创建 $_work"
    if [ -d "$C_BASE" ]; then
        [ -s "$C_BASE/manifest.json" ] || die "$EX_VERIFY" "$C_BASE/manifest.json 不存在"
        cp -f "$C_BASE/manifest.json" "$_work/manifest.json" || die "$EX_STATE" "复制清单失败"
        printf '%s' "$C_BASE" >"$_work/base"
    elif [ -f "$C_BASE" ]; then
        cp -f "$C_BASE" "$_work/manifest.json" || die "$EX_STATE" "复制清单失败"
        dirname "$C_BASE" >"$_work/base"
    else
        die "$EX_USAGE" "base_url 既不是目录也不是文件：$C_BASE"
    fi
    log "本地清单已就绪：$_work/manifest.json"
}

case "${0##*/}" in
    local-file.sh)
        . "${FWU_LIBDIR:-/usr/libexec/fwupgrade}/lib.sh"
        case "${1:-}" in
            resolve) WORK="$2"; config_load; provider_resolve "$WORK" ;;
            *) echo "用法: local-file.sh resolve <workdir>" >&2; exit 2 ;;
        esac
        ;;
esac
