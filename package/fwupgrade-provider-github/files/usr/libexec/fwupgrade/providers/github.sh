#!/bin/sh
# provider: github-release —— 取最新 release，产出统一 manifest.json
# 两种模式：
#   1) release 里带 manifest.json 资产 -> 直接用它（权威，可声明 target/abi）
#   2) 没有 manifest -> 用配置的两个资产名合成（兼容模式，target 留空，身份校验降级）
# stable 走 /releases/latest；beta/dev 走 /releases 列表并取第一个非 draft（通常即 prerelease）。

API_BASE="${API_BASE:-https://api.github.com}"

provider_resolve() {
    _work="$1"
    mkdir -p "$_work" || die "$EX_STATE" "无法创建工作目录 $_work"
    # 先清掉上一轮可能留下的签名：本仓若不带签名，不能继承旧 .sig
    rm -f "$_work/manifest.json.sig"

    if [ -n "${C_TAG:-}" ]; then
        # 一仓多机型：每个机型一个 Release tag，latest 会指到别的机型，必须指定
        _url="$API_BASE/repos/$C_REPO/releases/tags/$C_TAG"
        log "按指定 tag 取 release：$_url"
    else
        case "${C_CHANNEL:-stable}" in
            beta|dev) _url="$API_BASE/repos/$C_REPO/releases?per_page=5" ;;
            *)        _url="$API_BASE/repos/$C_REPO/releases/latest" ;;
        esac
    fi
    log "取 release：$_url"
    if ! http_fetch "$_url" "$_work/release.json"; then
        if grep -qi "rate limit" "$_work/release.json" 2>/dev/null; then
            die "$EX_DL" "GitHub API 限流（匿名 60 次/小时/IP），请稍后重试或为私有源配置 token"
        fi
        die "$EX_DL" "取 release 失败（$C_REPO）"
    fi

    ucode "$FWU_LIBDIR/ghrelease.uc" <"$_work/release.json" >"$_work/release.env" 2>/dev/null ||
        die "$EX_VERIFY" "release JSON 解析失败"

    _tag=$(rget TAG)
    _pub=$(rget PUBLISHED_AT)
    [ -n "$_tag" ] || die "$EX_VERIFY" "release 缺 tag_name"

    # 发布时间 -> epoch：busybox date 对 ISO8601 的接受度因版本而异，逐个格式退
    _ts=$(date -d "$_pub" +%s 2>/dev/null)
    [ -n "$_ts" ] || _ts=$(date -D '%Y-%m-%dT%H:%M:%SZ' -d "$_pub" +%s 2>/dev/null)
    [ -n "$_ts" ] || _ts=$(date -d "${_pub%Z}" +%s 2>/dev/null)
    case "$_ts" in ''|*[!0-9]*) _ts=0 ;; esac

    # tag 可能带前缀（OneCloud_openwrt-25.12_26.11.18_16.27.30），抽出可比的版本段
    _ver=$(norm_version "$_tag")
    [ -n "$_ver" ] || _ver="$_tag"

    # 优先使用 release 自带的 manifest.json
    _murl=""; _surl=""
    _n=$(rget ASSET_COUNT)
    _i=0
    while [ "$_i" -lt "${_n:-0}" ]; do
        _an=$(rget "ASSET_${_i}_NAME")
        case "$_an" in
            manifest.json) _murl=$(rget "ASSET_${_i}_URL") ;;
            manifest.json.sig) _surl=$(rget "ASSET_${_i}_URL") ;;
        esac
        _i=$((_i + 1))
    done

    if [ -n "$_murl" ]; then
        log "使用 release 内的 manifest.json"
        if ! http_fetch_asset "$_murl" "$_work/manifest.json"; then
            # 常见根因：无 RTC 设备时钟停在构建日期，证书 not yet valid
            _probe=$(uclient-fetch -O /dev/null -T 8 https://github.com/ 2>&1)
            case "$_probe" in
                *certificate*|*"not yet valid"*)
                    die "$EX_NET" "设备时间不正确（$(date '+%F %T')），证书校验失败；请先校时再检测" ;;
            esac
            die "$EX_DL" "取 manifest.json 失败"
        fi
        if [ -n "$_surl" ]; then
            http_fetch_asset "$_surl" "$_work/manifest.json.sig" || die "$EX_DL" "取 manifest.json.sig 失败"
            log "清单签名已下载"
        fi
        dirname_url "$_murl" >"$_work/base"
        return 0
    fi

    log "release 内无 manifest.json，按配置资产名合成（兼容模式）"
    synthesize_manifest "$_work" "$_ver" "$_ts"
}

# 从 release.env 读字段
rget() {
    awk -F= -v k="$1" '$1==k{sub(/^[^=]*=/,"");print;exit}' "$_work/release.env" 2>/dev/null
}

dirname_url() {
    printf '%s' "$1" | sed 's#/[^/]*$##'
}

synthesize_manifest() {
    _work="$1"; _tag="$2"; _ts="$3"
    _entries=""
    for _role in rootfs boot; do
        if [ "$_role" = rootfs ]; then _want="$C_ASSET_ROOTFS"; else _want="$C_ASSET_BOOT"; fi
        _found=""
        _i=0
        while [ "$_i" -lt "${_n:-0}" ]; do
            _an=$(rget "ASSET_${_i}_NAME")
            if [ "$_an" = "$_want" ]; then
                _found="$_i"
                break
            fi
            _i=$((_i + 1))
        done
        [ -n "$_found" ] || die "$EX_VERIFY" "release 里找不到资产：$_want"

        _sz=$(rget "ASSET_${_found}_SIZE")
        _dg=$(rget "ASSET_${_found}_DIGEST")
        _u=$(rget "ASSET_${_found}_URL")
        _sha=${_dg#sha256:}
        case "$_sha" in ''|*[!0-9a-f]*) die "$EX_VERIFY" "资产 $_want 缺少 sha256 digest，拒绝继续" ;; esac
        _entries="$_entries{\"kind\":\"$_role\",\"url\":\"$_u\",\"size\":${_sz:-0},\"sha256\":\"$_sha\"},"
    done
    _entries=${_entries%,}

    cat >"$_work/manifest.json" <<EOF
{"schema":1,"channel":"stable","release":{"version":"$_tag","build_ts":${_ts:-0}},"targets":[],"assets":[${_entries}],"flasher":{"type":"onecloud-emmc","abi":1}}
EOF
    printf '%s' "https://github.com" >"$_work/base"
    log "已合成清单：version=$_tag assets=2（兼容模式，未声明 target）"
}

case "${0##*/}" in
    github.sh)
        . "${FWU_LIBDIR:-/usr/libexec/fwupgrade}/lib.sh"
        case "${1:-}" in
            resolve) WORK="$2"; config_load; provider_resolve "$WORK" ;;
            *) echo "用法: github.sh resolve <workdir>" >&2; exit 2 ;;
        esac
        ;;
esac
