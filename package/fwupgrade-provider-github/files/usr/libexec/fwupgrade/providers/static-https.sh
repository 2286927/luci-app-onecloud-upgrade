#!/bin/sh
# provider: static-https —— 固定目录布局 <base>/manifest.json
provider_resolve() {
    _work="$1"
    mkdir -p "$_work" || die "$EX_STATE" "无法创建 $_work"
    http_fetch "${C_BASE%/}/manifest.json" "$_work/manifest.json" ||
        die "$EX_DL" "取 ${C_BASE%/}/manifest.json 失败"
    printf '%s' "${C_BASE%/}" >"$_work/base"
    log "静态源清单已就绪"
}

case "${0##*/}" in
    static-https.sh)
        . "${FWU_LIBDIR:-/usr/libexec/fwupgrade}/lib.sh"
        case "${1:-}" in
            resolve) WORK="$2"; config_load; provider_resolve "$WORK" ;;
            *) echo "用法: static-https.sh resolve <workdir>" >&2; exit 2 ;;
        esac
        ;;
esac
