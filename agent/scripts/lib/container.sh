#!/usr/bin/env bash
# Runtime execution layer for Parrot/Kali host tools.

CONTAINER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$CONTAINER_LIB_DIR/processes.sh"
# shellcheck source=/dev/null
. "$CONTAINER_LIB_DIR/noise.sh"

MITMPROXY_BIN="${MITMPROXY_BIN:-mitmdump}"
KATANA_LOCAL_BIN="${KATANA_LOCAL_BIN:-katana}"
KATANA_CHROME_BIN="${KATANA_CHROME_BIN:-/usr/bin/chromium}"
KATANA_HEADLESS_OPTIONS="${KATANA_HEADLESS_OPTIONS:---no-sandbox,--disable-dev-shm-usage,--disable-gpu}"
KATANA_CRAWL_DEPTH="${KATANA_CRAWL_DEPTH:-8}"
KATANA_CRAWL_DURATION="${KATANA_CRAWL_DURATION:-15m}"
KATANA_TIMEOUT_SECONDS="${KATANA_TIMEOUT_SECONDS:-20}"
KATANA_TIME_STABLE_SECONDS="${KATANA_TIME_STABLE_SECONDS:-5}"
KATANA_RETRY_COUNT="${KATANA_RETRY_COUNT:-3}"
KATANA_MAX_FAILURE_COUNT="${KATANA_MAX_FAILURE_COUNT:-20}"
KATANA_CONCURRENCY="${KATANA_CONCURRENCY:-15}"
KATANA_PARALLELISM="${KATANA_PARALLELISM:-4}"
KATANA_RATE_LIMIT="${KATANA_RATE_LIMIT:-60}"
KATANA_STRATEGY="${KATANA_STRATEGY:-breadth-first}"
KATANA_ENABLE_JSLUICE="${KATANA_ENABLE_JSLUICE:-0}"
KATANA_ENABLE_PATH_CLIMB="${KATANA_ENABLE_PATH_CLIMB:-0}"
KATANA_ENABLE_HYBRID="${KATANA_ENABLE_HYBRID:-1}"
KATANA_ENABLE_XHR="${KATANA_ENABLE_XHR:-1}"
KATANA_ENABLE_HEADLESS="${KATANA_ENABLE_HEADLESS:-1}"

runtime_mode() {
    echo "local"
}

_resolve_engagement_dir() {
    if [[ -z "${ENGAGEMENT_DIR:-}" ]]; then
        echo "ERROR: ENGAGEMENT_DIR not set" >&2
        return 1
    fi
    if [[ "$ENGAGEMENT_DIR" = /* ]]; then
        ENGAGEMENT_DIR_ABS="$ENGAGEMENT_DIR"
    else
        ENGAGEMENT_DIR_ABS="$(cd "$ENGAGEMENT_DIR" 2>/dev/null && pwd || echo "$(pwd)/$ENGAGEMENT_DIR")"
    fi
}

_engagement_env_file() {
    _resolve_engagement_dir || return 1
    if [[ -f "${ENGAGEMENT_DIR_ABS}/.env" ]]; then
        echo "${ENGAGEMENT_DIR_ABS}/.env"
    elif [[ -f "$(pwd)/.env" ]]; then
        echo "$(pwd)/.env"
    fi
}

_load_engagement_env() {
    local env_file
    env_file="$(_engagement_env_file)"
    if [[ -n "$env_file" && -f "$env_file" ]]; then
        set -a
        # shellcheck disable=SC1090
        source "$env_file"
        set +a
    fi
}

_engagement_pid_dir() {
    _resolve_engagement_dir || return 1
    mkdir -p "${ENGAGEMENT_DIR_ABS}/pids"
    echo "${ENGAGEMENT_DIR_ABS}/pids"
}

_start_local_process() {
    local name="$1"; shift
    local pid_dir env_file expected_command
    pid_dir="$(_engagement_pid_dir)" || return 1
    env_file="$(_engagement_env_file)"
    expected_command="$(basename "$1")"
    start_managed_process "$pid_dir" "$name" "$expected_command" env \
        ENGAGEMENT_DIR_ABS="$ENGAGEMENT_DIR_ABS" \
        ENGAGEMENT_DIR="$ENGAGEMENT_DIR_ABS" \
        GREENAPPLE_ENV_FILE="$env_file" \
        bash -lc '
        cd "$ENGAGEMENT_DIR_ABS"
        if [[ -n "${GREENAPPLE_ENV_FILE:-}" && -f "$GREENAPPLE_ENV_FILE" ]]; then
            set -a
            . "$GREENAPPLE_ENV_FILE"
            set +a
        fi
        "$@"
    ' bash "$@"
}

_stop_local_process() {
    local name="$1"
    local expected_command="${2:-}"
    local pid_dir
    pid_dir="$(_engagement_pid_dir)" || return 1
    stop_managed_process "$pid_dir" "$name" "$expected_command"
}

_auth_header_args() {
    _resolve_engagement_dir || return 1
    local auth_file="${ENGAGEMENT_DIR_ABS}/auth.json"
    [[ -f "$auth_file" ]] || return 0

    jq -r '
      [
        (if (.cookies | type) == "object" and ((.cookies | keys | length) > 0)
         then "Cookie: " + (.cookies | to_entries | map(.key + "=" + .value) | join("; "))
         else empty end),
        (if (.headers | type) == "object"
         then (.headers | to_entries[] | .key + ": " + .value)
         else empty end)
      ] | .[]
    ' "$auth_file" 2>/dev/null | while IFS= read -r header; do
        [[ -n "$header" ]] || continue
        printf '%s\0%s\0' "-H" "$header"
    done
}

_auth_header_array() {
    local args=()
    while IFS= read -r -d '' item; do
        args+=("$item")
    done < <(_auth_header_args)
    if [[ ${#args[@]} -gt 0 ]]; then
        printf '%s\n' "${args[@]}"
    fi
}

_regex_escape() {
    printf '%s' "$1" | sed -e 's/[.[\*^$()+?{}|\/]/\\&/g'
}

_katana_scope_args() {
    _resolve_engagement_dir || return 1
    local scope_file="${ENGAGEMENT_DIR_ABS}/scope.json"
    local patterns=()
    local entry host escaped

    [[ -f "$scope_file" ]] || return 0

    while IFS= read -r entry; do
        [[ -n "$entry" ]] || continue
        if [[ "$entry" == \*.* ]]; then
            host="${entry#*.}"
            escaped="$(_regex_escape "$host")"
            patterns+=("^https?://([^.]+\\.)*${escaped}([/:?#]|$)")
        else
            escaped="$(_regex_escape "$entry")"
            patterns+=("^https?://${escaped}([/:?#]|$)")
        fi
    done < <(jq -r '[.hostname // empty, (.scope // [] | .[])] | map(select(type == "string" and length > 0)) | unique[]' "$scope_file" 2>/dev/null)

    for pattern in "${patterns[@]}"; do
        printf '%s\0%s\0' "-cs" "$pattern"
    done
}

_katana_scope_array() {
    local args=()
    while IFS= read -r -d '' item; do
        args+=("$item")
    done < <(_katana_scope_args)
    if [[ ${#args[@]} -gt 0 ]]; then
        printf '%s\n' "${args[@]}"
    fi
}

_sudo_or_die() {
    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
        return 0
    fi
    if ! command -v sudo >/dev/null 2>&1; then
        echo "FATAL: sudo is required for GreenAppleAgent HTB operations." >&2
        echo "Install sudo and configure passwordless access: sudo visudo -f /etc/sudoers.d/greenapple" >&2
        return 1
    fi
    if ! sudo -n true >/dev/null 2>&1; then
        echo "FATAL: sudo requires interactive password. Run sudo -v before launching OpenCode." >&2
        echo "Or configure passwordless sudo for the VM user." >&2
        return 1
    fi
}

run_tool() {
    local tool="$1"; shift
    _resolve_engagement_dir || return 1
    _sudo_or_die || return 1
    (
        cd "$ENGAGEMENT_DIR_ABS"
        export ENGAGEMENT_DIR="$ENGAGEMENT_DIR_ABS"
        _load_engagement_env
        if [[ "$tool" == "curl" && -x "${ENGAGEMENT_DIR_ABS}/tools/rtcurl" ]]; then
            sudo -n -E "${ENGAGEMENT_DIR_ABS}/tools/rtcurl" "$@"
        else
            sudo -n -E "$tool" "$@"
        fi
    )
}

run_privileged() {
    _resolve_engagement_dir || return 1
    _sudo_or_die || return 1
    (
        cd "$ENGAGEMENT_DIR_ABS"
        export ENGAGEMENT_DIR="$ENGAGEMENT_DIR_ABS"
        _load_engagement_env
        if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
            "$@"
        else
            sudo -n -E "$@"
        fi
    )
}

start_proxy() {
    _resolve_engagement_dir || return 1
    mkdir -p "${ENGAGEMENT_DIR_ABS}/scans"
    _start_local_process proxy "$MITMPROXY_BIN" --set engagement_dir="$ENGAGEMENT_DIR_ABS" "$@"
    echo "[proxy] Started on port ${MITMPROXY_PORT:-8080}"
}

stop_proxy() {
    _stop_local_process proxy "$MITMPROXY_BIN"
}

start_katana() {
    local target="$1"; shift
    _resolve_engagement_dir || return 1
    if [[ -z "$target" ]]; then
        echo "ERROR: target URL required" >&2
        return 1
    fi

    local katana_args=(
        -u "$target"
        -kf all
        -iqp
        -fsu
        -ns
        -s "$KATANA_STRATEGY"
        -d "$KATANA_CRAWL_DEPTH"
        -ct "$KATANA_CRAWL_DURATION"
        -timeout "$KATANA_TIMEOUT_SECONDS"
        -time-stable "$KATANA_TIME_STABLE_SECONDS"
        -retry "$KATANA_RETRY_COUNT"
        -mfc "$KATANA_MAX_FAILURE_COUNT"
        -c "$KATANA_CONCURRENCY"
        -p "$KATANA_PARALLELISM"
        -rl "$KATANA_RATE_LIMIT"
        -mrs 16777216
        -omit-raw
        -omit-body
        -jsonl
        -silent
    )
    if [[ "$KATANA_ENABLE_HYBRID" == "1" ]]; then
        katana_args+=(-hh -jc -fx -td -tlsi -duc)
    fi
    if [[ "$KATANA_ENABLE_XHR" == "1" ]]; then
        katana_args+=(-xhr -xhr-extraction)
    fi
    if [[ "$KATANA_ENABLE_HEADLESS" == "1" ]]; then
        [[ "$KATANA_ENABLE_HYBRID" == "1" ]] || katana_args+=(-hl)
        katana_args+=(-system-chrome -system-chrome-path "$KATANA_CHROME_BIN" -headless-options "$KATANA_HEADLESS_OPTIONS")
    fi
    [[ "$KATANA_ENABLE_JSLUICE" == "1" ]] && katana_args+=(-jsl)
    [[ "$KATANA_ENABLE_PATH_CLIMB" == "1" ]] && katana_args+=(-pc)
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        katana_args+=(-cos "$line")
    done < <(katana_emit_out_of_scope_regexes)

    local auth_args=() scope_args=()
    while IFS= read -r line; do [[ -n "$line" ]] && auth_args+=("$line"); done < <(_auth_header_array)
    while IFS= read -r line; do [[ -n "$line" ]] && scope_args+=("$line"); done < <(_katana_scope_array)

    mkdir -p "${ENGAGEMENT_DIR_ABS}/scans" "${ENGAGEMENT_DIR_ABS}/pids"
    local katana_output_path="${KATANA_OUTPUT_PATH:-${ENGAGEMENT_DIR_ABS}/scans/katana_output.jsonl}"
    _start_local_process katana "$KATANA_LOCAL_BIN" "${katana_args[@]}" "${scope_args[@]+"${scope_args[@]}"}" "${auth_args[@]+"${auth_args[@]}"}" -elog "${ENGAGEMENT_DIR_ABS}/scans/katana_error.log" -o "$katana_output_path" "$@"
    echo "[katana] Started crawling $target"
}

stop_katana() {
    _stop_local_process katana "$KATANA_LOCAL_BIN"
}

stop_all_containers() {
    stop_proxy || true
    stop_katana || true
    echo "[runtime] Current engagement background processes stopped"
}

check_images() {
    echo "[OK] local Parrot/Kali runtime mode active"
}

check_docker() {
    echo "[OK] Docker not required for this runtime"
}
