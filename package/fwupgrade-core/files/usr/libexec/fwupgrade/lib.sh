#!/bin/sh
# fwupgrade core library —— POSIX sh / BusyBox ash，不依赖 bash 与 GNU 工具
# 约定：本文件只被 source，不直接执行。

FWU_ROOT="${FWU_ROOT:-/opt/fwupgrade}"
FWU_STATE_ENV="$FWU_ROOT/state.env"
FWU_STATE_JSON="$FWU_ROOT/state.json"
FWU_JOURNAL="$FWU_ROOT/journal.log"
FWU_QUEUE="$FWU_ROOT/queue"
FWU_CONF="${FWU_CONF:-/etc/config/onecloud-upgrade}"
FWU_LOCK="${FWU_LOCK:-/var/run/fwupgrade.lock}"
FWU_LIBDIR="${FWU_LIBDIR:-/usr/libexec/fwupgrade}"
FWU_LOG_MAX="${FWU_LOG_MAX:-524288}"

# 退出码：与现网 upgrade 的 0/2/3/4/5/6 对齐，新增码从 7 起
EX_OK=0
EX_USAGE=2
EX_NET=3
EX_SPACE=4
EX_DL=5
EX_VERIFY=6
EX_NOIMPL=7
EX_STATE=8

iso_now() { date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%S; }

boot_id() {
    _bid=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null | tr -d '-')
    [ -n "$_bid" ] || _bid=unknown
    printf '%s' "$_bid"
}

# 结构化日志：stdout 之外一律进 journal；超过上限就地截断（不做轮转目录，省 inode）
log() {
    _line="$(iso_now) $*"
    printf '%s\n' "$_line" >&2
    mkdir -p "$FWU_ROOT" 2>/dev/null
    printf '%s\n' "$_line" >>"$FWU_JOURNAL" 2>/dev/null
    _sz=$(wc -c <"$FWU_JOURNAL" 2>/dev/null || echo 0)
    if [ "${_sz:-0}" -gt "$FWU_LOG_MAX" ]; then
        tail -c $((FWU_LOG_MAX / 2)) "$FWU_JOURNAL" >"$FWU_JOURNAL.tmp" 2>/dev/null &&
            mv -f "$FWU_JOURNAL.tmp" "$FWU_JOURNAL"
    fi
}

die() {
    _code="$1"; shift
    log "ERROR(${_code}) $*"
    printf '{"ok":false,"code":%s,"message":"%s"}\n' "$_code" "$(jesc "$*")"
    exit "$_code"
}

# JSON 字符串转义：只处理引号、反斜杠与控制字符
jesc() {
    printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr -d '\000-\010\013\014\016-\037'
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "$EX_USAGE" "缺少命令：$1"
}

conf_get() {
    _v=$(uci -q get "onecloud-upgrade.main.$1" 2>/dev/null)
    [ -n "$_v" ] && { printf '%s' "$_v"; return 0; }
    return 1
}

free_kb() {
    df -k "$1" 2>/dev/null | awk 'END{print $4}'
}

# 单次取件（不重试），用于镜像回退时快速切换
http_fetch_once() {
    _url="$1"; _out="$2"
    if command -v uclient-fetch >/dev/null 2>&1; then
        uclient-fetch -q -T 25 -O "$_out" "$_url" 2>/dev/null && return 0
    elif command -v curl >/dev/null 2>&1; then
        curl -fsSL --max-time 25 -o "$_out" "$_url" 2>/dev/null && return 0
    elif command -v wget >/dev/null 2>&1; then
        wget -q -T 25 -O "$_out" "$_url" 2>/dev/null && return 0
    fi
    return 1
}

# 带镜像回退的资产取件：直连失败后依次尝试镜像前缀
http_fetch_asset() {
    _url="$1"; _out="$2"
    http_fetch_once "$_url" "$_out" && return 0
    log "直连失败，尝试镜像：$_url"
    for _m in ${C_MIRROR:-} https://gh-proxy.org https://gh-proxy.com; do
        [ -n "$_m" ] || continue
        http_fetch_once "${_m%/}/$_url" "$_out" && { log "镜像命中：$_m"; return 0; }
    done
    return "$EX_DL"
}

# 统一 HTTP 取件：优先 uclient-fetch（OpenWrt 自带），退 curl / wget；4xx 不重试
http_fetch() {
    _url="$1"; _out="$2"; _tries=0
    while [ "$_tries" -lt 3 ]; do
        _tries=$((_tries + 1))
        if command -v uclient-fetch >/dev/null 2>&1; then
            uclient-fetch -q -T 30 -O "$_out" "$_url" 2>/dev/null && return 0
        elif command -v curl >/dev/null 2>&1; then
            curl -fsSL --max-time 30 -o "$_out" "$_url" 2>/dev/null && return 0
        elif command -v wget >/dev/null 2>&1; then
            wget -q -T 30 -O "$_out" "$_url" 2>/dev/null && return 0
        else
            die "$EX_USAGE" "缺少下载工具（uclient-fetch/curl/wget）"
        fi
        log "取件失败（第 $_tries 次）：$_url"
        sleep $((_tries * 2))
    done
    return "$EX_DL"
}

# ---------- 备份 ----------
# 只备份 /etc/config（L1 范围）；FWU_ETC_CONFIG 可在测试时指向临时目录。
FWU_ETC_CONFIG="${FWU_ETC_CONFIG:-/etc/config}"
FWU_BACKUP_ROOT="${FWU_BACKUP_ROOT:-$FWU_ROOT/backup}"

backup_config() {
    _dest="$1"
    mkdir -p "$_dest" || die "$EX_STATE" "无法创建备份目录 $_dest"
    _parent=$(dirname "$FWU_ETC_CONFIG")
    _base=$(basename "$FWU_ETC_CONFIG")
    tar -czf "$_dest/etc-config.tar.gz" -C "$_parent" "$_base" 2>/dev/null ||
        die "$EX_STATE" "打包 $_base 失败"
    _sha=$(sha256sum "$_dest/etc-config.tar.gz" 2>/dev/null | awk '{print $1}')
    _cnt=$(ls "$FWU_ETC_CONFIG" 2>/dev/null | wc -l)
    {
        printf 'created_at=%s\n' "$(iso_now)"
        printf 'sha256=%s\n' "$_sha"
        printf 'files=%s\n' "$_cnt"
        printf 'source=%s\n' "$FWU_ETC_CONFIG"
    } >"$_dest/MANIFEST"
    log "配置已备份：$_dest（${_cnt} 个文件，sha256=${_sha:-unknown}）"
}

# 白名单校验收到的备份 id：只允许这些字符，且必须是单段路径
valid_backup_id() {
    case "$1" in
        ''|*[!A-Za-z0-9._-]*) return 1 ;;
        *..*) return 1 ;;
    esac
    return 0
}

uptime_s() { awk '{print int($1)}' /proc/uptime 2>/dev/null || echo 0; }

FWU_LAST_FILE="${FWU_LAST_FILE:-/opt/oc-upgrade.last}"

# 升级结局判定（纯函数，便于单测）
# 参数：boot_pre boot_now elapsed apply_started last_ts last_ver target now_ver
# 输出：ok / pending / no_reboot / version_mismatch / no_record / stale_record / record_ver_mismatch
recover_decide() {
    _bp="$1"; _bn="$2"; _el="$3"; _st="$4"; _lts="$5"; _lver="$6"; _tv="$7"; _nv="$8"
    case "$_el" in ''|*[!0-9]*) _el=0 ;; esac
    if [ -z "$_bp" ]; then
        [ -n "$_tv" ] && [ "$_nv" = "$_tv" ] && { printf 'ok'; return 0; }
        printf 'version_mismatch'; return 0
    fi
    if [ "$_bp" = "$_bn" ]; then
        [ "$_el" -lt 900 ] && { printf 'pending'; return 0; }
        printf 'no_reboot'; return 0
    fi
    [ "$_nv" = "$_tv" ] || { printf 'version_mismatch'; return 0; }
    case "$_lts" in ''|*[!0-9]*) printf 'no_record'; return 0 ;; esac
    case "$_st" in ''|*[!0-9]*) printf 'no_record'; return 0 ;; esac
    [ "$_lts" -ge "$_st" ] || { printf 'stale_record'; return 0; }
    [ "$_lver" = "$_tv" ] || { printf 'record_ver_mismatch'; return 0; }
    printf 'ok'
}

# ---------- 状态 ----------

# 内部状态用 KEY=VALUE（ash 读取简单、原子写简单），外向状态由 state.uc 渲染成 JSON。
state_get() {
    awk -F= -v k="$1" '$1==k{sub(/^[^=]*=/,"");print;exit}' "$FWU_STATE_ENV" 2>/dev/null
}

# state_commit key=value...：只更新给定键，其余保留；原子替换后重渲染 JSON
state_commit() {
    mkdir -p "$FWU_ROOT" || die "$EX_STATE" "无法创建 $FWU_ROOT"
    [ -f "$FWU_STATE_ENV" ] || : >"$FWU_STATE_ENV"
    for _kv in "$@"; do
        _k=${_kv%%=*}
        _v=${_kv#*=}
        grep -v "^${_k}=" "$FWU_STATE_ENV" >"$FWU_STATE_ENV.tmp" 2>/dev/null
        printf '%s=%s\n' "$_k" "$_v" >>"$FWU_STATE_ENV.tmp"
        mv -f "$FWU_STATE_ENV.tmp" "$FWU_STATE_ENV" || die "$EX_STATE" "状态写入失败"
    done
    state_commit_core
}

# 合并写入多个键（保留未提及的键）；先写临时文件再 rename，掉电不会留半截
state_replace() {
    mkdir -p "$FWU_ROOT" || die "$EX_STATE" "无法创建 $FWU_ROOT"
    if [ -f "$FWU_STATE_ENV" ]; then
        cp "$FWU_STATE_ENV" "$FWU_STATE_ENV.tmp.$$" || die "$EX_STATE" "状态读取失败"
    else
        : >"$FWU_STATE_ENV.tmp.$$"
    fi
    for _kv in "$@"; do
        _k=${_kv%%=*}
        _v=${_kv#*=}
        grep -v "^${_k}=" "$FWU_STATE_ENV.tmp.$$" >"$FWU_STATE_ENV.tmp2.$$" 2>/dev/null
        printf '%s=%s\n' "$_k" "$_v" >>"$FWU_STATE_ENV.tmp2.$$"
        mv -f "$FWU_STATE_ENV.tmp2.$$" "$FWU_STATE_ENV.tmp.$$"
    done
    sync
    mv -f "$FWU_STATE_ENV.tmp.$$" "$FWU_STATE_ENV" || die "$EX_STATE" "状态写入失败"
    state_commit_core
}

state_commit_core() {
    # 用 shell 生成 JSON（字段全是受控值），避免依赖 ucode 的序列化行为
    _phase=$(state_get phase); _res=$(state_get last_result); _mix=$(state_get mixed_state)
    _job=$(state_get job_id); _ver=$(state_get version); _tgt=$(state_get target)
    _detail=$(state_get detail); _code=$(state_get code); _prog=$(state_get progress)
    _upd=$(state_get updated_at); _cur=$(state_get current)
    case "$_code" in ''|*[!0-9]*) _code=0 ;; esac
    case "$_prog" in ''|*[!0-9]*) _prog=0 ;; esac
    cat >"$FWU_STATE_JSON.tmp.$$" <<EOF
{"schema":1,"phase":"$(jesc "${_phase:-idle}")","last_result":"$(jesc "${_res:-none}")","mixed_state":"$(jesc "${_mix:-N}")","job_id":"$(jesc "$_job")","current":"$(jesc "$_cur")","version":"$(jesc "$_ver")","target":"$(jesc "$_tgt")","detail":"$(jesc "$_detail")","code":$_code,"progress":$_prog,"updated_at":"$(jesc "${_upd:-$(iso_now)}")"}
EOF
    sync
    mv -f "$FWU_STATE_JSON.tmp.$$" "$FWU_STATE_JSON" || rm -f "$FWU_STATE_JSON.tmp.$$"
}

# ---------- 锁 ----------
# 锁内容：pid boot_id phase。三种情况必须区分：
#   1) 同 boot + pid 活          -> busy
#   2) 同 boot + pid 死          -> stale，可清
#   3) 不同 boot（重启过）        -> 不是 stale，说明升级被重启打断，需 recovery 判定

lock_owner() {
    [ -f "$FWU_LOCK" ] || return 1
    _pid=$(awk '{print $1}' "$FWU_LOCK" 2>/dev/null)
    _boot=$(awk '{print $2}' "$FWU_LOCK" 2>/dev/null)
    _phase=$(awk '{print $3}' "$FWU_LOCK" 2>/dev/null)
    printf '%s %s %s' "${_pid:-0}" "${_boot:-unknown}" "${_phase:-unknown}"
}

lock_acquire() {
    mkdir -p "$(dirname "$FWU_LOCK")" 2>/dev/null
    _bid=$(boot_id)
    if [ -f "$FWU_LOCK" ]; then
        _old=$(lock_owner)
        _opid=${_old%% *}
        _rest=${_old#* }
        _oboot=${_rest%% *}
        _ophase=${_rest#* }
        if [ "$_oboot" != "$_bid" ]; then
            log "上次升级在 $_ophase 阶段被重启打断（boot_id 变化），进入恢复判定"
            printf '%s %s recovery\n' "$$" "$_bid" >"$FWU_LOCK"
            return 0
        fi
        if [ "$_opid" = "$$" ]; then
            log "本进程已持有锁（phase=$_ophase）"
            return 1
        fi
        # 先看阶段，再看进程是否活着：writing_boot 之后即使 pid 已消失，
        # 也可能是「写完 boot 但没重启」，不能当陈旧锁清掉。
        if [ "$_ophase" = "writing_boot" ]; then
            log "上次已进入 writing_boot，未确认重启，拒绝自动继续"
            return 2
        fi
        if kill -0 "$_opid" 2>/dev/null; then
            log "已有任务在跑（pid=$_opid phase=$_ophase）"
            return 1
        fi
        log "清理陈旧锁（pid=$_opid 已不存在）"
    fi
    printf '%s %s %s\n' "$$" "$_bid" "$(state_get phase)" >"$FWU_LOCK"
    return 0
}

lock_update_phase() {
    printf '%s %s %s\n' "$$" "$(boot_id)" "$1" >"$FWU_LOCK"
}

lock_release() {
    _old=$(lock_owner 2>/dev/null)
    [ "${_old%% *}" = "$$" ] && rm -f "$FWU_LOCK"
    return 0
}

# ---------- 清单（JSON -> KEY=VALUE）----------

# manifest_load <file>：解析到全局 M_* 变量，并把原始键值存进 $FWU_ROOT/manifest.env
manifest_load() {
    _f="$1"
    [ -s "$_f" ] || die "$EX_VERIFY" "清单为空或不存在：$_f"
    need_cmd ucode
    ucode "$FWU_LIBDIR/manifest.uc" <"$_f" >"$FWU_ROOT/manifest.env" 2>"$FWU_ROOT/manifest.err" ||
        die "$EX_VERIFY" "清单解析失败：$(head -c 200 "$FWU_ROOT/manifest.err" 2>/dev/null)"
    M_SCHEMA=$(mget SCHEMA)
    M_CHANNEL=$(mget CHANNEL)
    M_VERSION=$(mget VERSION)
    M_BUILD_TS=$(mget BUILD_TS)
    M_TARGET=$(mget TARGET_0_TARGET)
    M_COMPAT=$(mget TARGET_0_COMPAT)
    M_MIN_FROM=$(mget MIN_FROM)
    M_ASSET_COUNT=$(mget ASSET_COUNT)
    M_FLASHER_TYPE=$(mget FLASHER_TYPE)
    M_FLASHER_ABI=$(mget FLASHER_ABI)
    M_KEEP=$(mget FLASHER_KEEP)
    M_ROLLBACK=$(mget FLASHER_ROLLBACK)
    M_SIG_ALG=$(mget SIGNATURE_ALG)
    # target 允许为空（兼容模式：release 里没有 manifest，无法声明机型），
    # 但 schema 与 version 必须有，否则说明清单本身不成立。
    [ -n "$M_SCHEMA" ] && [ -n "$M_VERSION" ] ||
        die "$EX_VERIFY" "清单缺必填字段（schema/version）"
}

mget() {
    awk -F= -v k="$1" '$1==k{sub(/^[^=]*=/,"");print;exit}' "$FWU_ROOT/manifest.env" 2>/dev/null
}

# 清单里的 flasher 类型 -> 实现文件名（onecloud-emmc 与 onecloud 等价）
flasher_name() {
    _f=$(mget FLASHER_TYPE)
    case "$_f" in
        ''|onecloud|onecloud-emmc) printf 'onecloud' ;;
        dryrun) printf 'dryrun' ;;
        *) printf '%s' "$_f" ;;
    esac
}

# asset_get <index> <field>
asset_get() {
    mget "ASSET_$1_$(printf '%s' "$2" | tr 'a-z' 'A-Z')"
}

# ---------- 签名 ----------
# 规则：有 .sig 就必须验；require_signature=1 时没有 .sig 直接拒绝。
verify_manifest_sig() {
    _m="$1"; _sig="$2"
    if [ ! -s "$_sig" ]; then
        if [ "${C_REQUIRE_SIG:-0}" = "1" ]; then
            die "$EX_VERIFY" "本通道要求签名，但清单缺少 manifest.json.sig"
        fi
        log "清单未签名（require_signature=0，继续）"
        return 0
    fi
    command -v usign >/dev/null 2>&1 || die "$EX_VERIFY" "缺少 usign，无法校验清单签名"
    _key=$(ls /etc/fwupgrade/pubkey.* 2>/dev/null | head -n 1)
    [ -n "$_key" ] || die "$EX_VERIFY" "未找到公钥 /etc/fwupgrade/pubkey.*"
    usign -V -p "$_key" -x "$_sig" -m "$_m" 2>/dev/null ||
        die "$EX_VERIFY" "清单签名校验失败（公钥 $(basename "$_key")）"
    log "清单签名校验通过：$(basename "$_key")"
}

# ---------- 版本 ----------
# 本机版本 26.11.18_16.27.30（YY.MM.DD_HH.MM.SS，零填充，可直接字符串比较）
local_version() {
    cat /etc/oc-version 2>/dev/null | tr -d ' \r\n'
}

# ver_gt A B -> 0 表示 A 比 B 新
ver_gt() {
    awk -v a="$1" -v b="$2" 'BEGIN{ if (a=="" || b=="") exit 1; exit !(a>b) }'
}

# 清单版本 -> 本机同格式；兼容 "OneCloud_openwrt-25.12_26.11.18_16.27.30" 这类 tag
norm_version() {
    _nv=$(printf '%s' "$1" | sed -n 's/^\([0-9][0-9]\)\.\([0-9][0-9]\)\.\([0-9][0-9]\)[_-]\([0-9][0-9]\)\.\([0-9][0-9]\)\.\([0-9][0-9]\)$/\1.\2.\3_\4.\5.\6/p')
    if [ -n "$_nv" ]; then
        printf '%s' "$_nv"
        return 0
    fi
    printf '%s' "$1" | sed -n 's/.*\([0-9][0-9]\.[0-9][0-9]\.[0-9][0-9]_[0-9][0-9]\.[0-9][0-9]\.[0-9][0-9]\).*/\1/p'
}

# ---------- 配置 ----------

# 配置里的 provider 名 -> 实现文件名
provider_file() {
    case "$1" in
        github-release) printf 'github' ;;
        *) printf '%s' "$1" ;;
    esac
}

# 读取并校验配置；缺项以 EX_USAGE + 明确字段名退出，不发任何网络请求
config_load() {
    C_PROVIDER=$(conf_get provider) || C_PROVIDER="github-release"
    C_REPO=$(conf_get repo) || C_REPO=""
    C_BASE=$(conf_get base_url) || C_BASE=""
    C_ASSET_ROOTFS=$(conf_get asset_rootfs) || C_ASSET_ROOTFS=""
    C_ASSET_BOOT=$(conf_get asset_boot) || C_ASSET_BOOT=""
    C_CHANNEL=$(conf_get channel) || C_CHANNEL="stable"
    C_TOKEN_FILE=$(conf_get token_file) || C_TOKEN_FILE=""
    C_MIRROR=$(conf_get mirror) || C_MIRROR=""
    C_DRY_RUN=$(conf_get dry_run) || C_DRY_RUN="1"
    C_FORCE=$(conf_get force) || C_FORCE="0"
    [ -n "$C_FORCE" ] || C_FORCE="0"
    C_REQUIRE_SIG=$(conf_get require_signature) || C_REQUIRE_SIG="0"
    [ -n "$C_REQUIRE_SIG" ] || C_REQUIRE_SIG="0"
    [ -n "$C_DRY_RUN" ] || C_DRY_RUN="1"

    case "$C_PROVIDER" in
        github-release)
            [ -n "$C_REPO" ] || die "$EX_USAGE" "配置缺失：repo（owner/name）"
            ;;
        static-https|local-file)
            [ -n "$C_BASE" ] || die "$EX_USAGE" "配置缺失：base_url"
            ;;
        *)
            die "$EX_USAGE" "未知 provider：$C_PROVIDER"
            ;;
    esac
    [ -n "$C_ASSET_ROOTFS" ] || die "$EX_USAGE" "配置缺失：asset_rootfs"
    [ -n "$C_ASSET_BOOT" ] || die "$EX_USAGE" "配置缺失：asset_boot"
}
