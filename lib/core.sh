#!/usr/bin/env bash
# =============================================================================
#  UnderHost One-Domain — Core Library
#  lib/core.sh
# =============================================================================
# Provides: colors, logging, prompts, validators, password generation, helpers
# Sourced by: install (entrypoint), and indirectly by all modules
# =============================================================================

# Guard against double-sourcing
[[ -n "${_UH_CORE_LOADED:-}" ]] && return 0
_UH_CORE_LOADED=1

# ---------------------------------------------------------------------------
# Terminal colors — disabled when stdout is not a tty
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
    _CLR_RESET='\033[0m'
    _CLR_BOLD='\033[1m'
    _CLR_DIM='\033[2m'
    _CLR_RED='\033[0;31m'
    _CLR_LRED='\033[1;31m'
    _CLR_GREEN='\033[0;32m'
    _CLR_LGREEN='\033[1;32m'
    _CLR_YELLOW='\033[1;33m'
    _CLR_BLUE='\033[0;34m'
    _CLR_CYAN='\033[0;36m'
    _CLR_LCYAN='\033[1;36m'
    _CLR_WHITE='\033[1;37m'
else
    _CLR_RESET=''
    _CLR_BOLD=''
    _CLR_DIM=''
    _CLR_RED=''
    _CLR_LRED=''
    _CLR_GREEN=''
    _CLR_LGREEN=''
    _CLR_YELLOW=''
    _CLR_BLUE=''
    _CLR_CYAN=''
    _CLR_LCYAN=''
    _CLR_WHITE=''
fi

# Convenience exports for use in heredocs / printf
RESET="$_CLR_RESET"
BOLD="$_CLR_BOLD"
DIM="$_CLR_DIM"

# color NAME text — emit text wrapped in the named color code
color() {
    local name="${1:-RESET}"
    shift || true
    local code
    case "${name^^}" in
        RESET)  code="$_CLR_RESET"  ;;
        BOLD)   code="$_CLR_BOLD"   ;;
        DIM)    code="$_CLR_DIM"    ;;
        RED)    code="$_CLR_RED"    ;;
        LRED)   code="$_CLR_LRED"   ;;
        GREEN)  code="$_CLR_GREEN"  ;;
        LGREEN) code="$_CLR_LGREEN" ;;
        YELLOW) code="$_CLR_YELLOW" ;;
        BLUE)   code="$_CLR_BLUE"   ;;
        CYAN)   code="$_CLR_CYAN"   ;;
        LCYAN)  code="$_CLR_LCYAN"  ;;
        WHITE)  code="$_CLR_WHITE"  ;;
        *)      code=""              ;;
    esac
    printf "%b%s%b" "$code" "$*" "$_CLR_RESET"
}

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
LOG_FILE="${LOG_FILE:-/var/log/underhost_install.log}"

_init_log() {
    local log_dir
    log_dir="$(dirname "$LOG_FILE")"
    if [[ ! -d "$log_dir" ]]; then
        mkdir -p "$log_dir" 2>/dev/null || {
            LOG_FILE="/tmp/underhost_install_$$.log"
            echo "[warn] Log directory not writable; using ${LOG_FILE}" >&2
        }
    fi
    if [[ ! -w "$log_dir" ]]; then
        LOG_FILE="/tmp/underhost_install_$$.log"
        echo "[warn] Log directory not writable; using ${LOG_FILE}" >&2
    fi
    touch "$LOG_FILE" 2>/dev/null || {
        LOG_FILE="/tmp/underhost_install_$$.log"
        echo "[warn] Cannot write to log; using ${LOG_FILE}" >&2
    }
    chmod 600 "$LOG_FILE" 2>/dev/null || true
}

log_msg() {
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    printf '[%s] %s\n' "$ts" "$*" >> "${LOG_FILE:-/dev/null}" 2>/dev/null || true
}

step() {
    local msg="$*"
    printf '\n%b==>%b %b%s%b\n' "$_CLR_LCYAN" "$_CLR_RESET" "$_CLR_BOLD" "$msg" "$_CLR_RESET"
    log_msg "STEP: ${msg}"
}

ok() {
    printf '  %b✓%b %s\n' "$_CLR_LGREEN" "$_CLR_RESET" "$*"
    log_msg "OK:   $*"
}

info() {
    printf '  %b→%b %s\n' "$_CLR_CYAN" "$_CLR_RESET" "$*"
    log_msg "INFO: $*"
}

warn() {
    printf '  %b⚠%b  %s\n' "$_CLR_YELLOW" "$_CLR_RESET" "$*" >&2
    log_msg "WARN: $*"
}

die() {
    printf '\n%b[ERROR]%b %s\n\n' "$_CLR_LRED" "$_CLR_RESET" "$*" >&2
    log_msg "ERROR: $*"
    exit 1
}

# ---------------------------------------------------------------------------
# Root check
# ---------------------------------------------------------------------------
_ensure_root() {
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        die "This installer must be run as root. Try: sudo ${0}"
    fi
}

# ---------------------------------------------------------------------------
# Domain validation
# ---------------------------------------------------------------------------
_validate_domain() {
    local domain="${1:-}"
    [[ -z "$domain" ]] && die "No domain specified. Usage: install <domain> php|wp"

    # Basic sanity: no spaces, no slashes, must contain at least one dot
    if [[ "$domain" =~ [[:space:]] ]] || [[ "$domain" =~ / ]]; then
        die "Invalid domain: '${domain}' (contains spaces or slashes)"
    fi

    # Must look like a FQDN: labels.tld — allow IDN and hyphenated labels
    if ! [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$ ]]; then
        die "Invalid domain format: '${domain}'"
    fi

    # Reject obviously dangerous values
    case "${domain,,}" in
        localhost|localhost.localdomain|*.local)
            die "Domain '${domain}' is a local/reserved name, not suitable for a public SSL deployment."
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Email validation
# ---------------------------------------------------------------------------
_validate_email() {
    local email="${1:-}"
    local ctx="${2:-email}"
    [[ -z "$email" ]] && die "${ctx}: email address is required"
    if ! [[ "$email" =~ ^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$ ]]; then
        die "${ctx}: '${email}' does not look like a valid email address"
    fi
}

# ---------------------------------------------------------------------------
# Password generation
# ---------------------------------------------------------------------------
# gen_pass [length]  — URL-safe alphanumeric password
gen_pass() {
    local len="${1:-20}"
    # Try openssl first; fall back to /dev/urandom if unavailable
    if command -v openssl &>/dev/null; then
        openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c "$len"
    else
        tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c "$len"
    fi
    echo  # newline
}

# gen_pass_db [length]  — alphanumeric only, safe for MariaDB identifiers
gen_pass_db() {
    local len="${1:-24}"
    if command -v openssl &>/dev/null; then
        openssl rand -base64 48 | tr -dc 'a-zA-Z0-9' | head -c "$len"
    else
        tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c "$len"
    fi
    echo
}

# ---------------------------------------------------------------------------
# Yes/no prompt  — prompt_yn "Question?" "y|n"
# Returns 0 for yes, 1 for no
# ---------------------------------------------------------------------------
prompt_yn() {
    local question="${1:-Continue?}"
    local default="${2:-y}"
    local hint
    if [[ "${default,,}" == "y" ]]; then
        hint="[Y/n]"
    else
        hint="[y/N]"
    fi

    while true; do
        printf '  %b?%b  %s %s ' "$_CLR_YELLOW" "$_CLR_RESET" "$question" "$hint"
        local answer
        read -r answer
        answer="${answer:-$default}"
        case "${answer,,}" in
            y|yes) return 0 ;;
            n|no)  return 1 ;;
            *) printf '      Please answer y or n.\n' ;;
        esac
    done
}

# prompt_input "Label" [default] — prints label, reads answer, echoes trimmed value
prompt_input() {
    local label="$1"
    local default="${2:-}"
    local hint=""
    [[ -n "$default" ]] && hint=" [${default}]"
    printf '  %b?%b  %s%s: ' "$_CLR_CYAN" "$_CLR_RESET" "$label" "$hint"
    local answer
    read -r answer
    answer="${answer:-$default}"
    echo "${answer}"
}

# prompt_select "Label" opt1 opt2 ... — select from numbered list
prompt_select() {
    local label="$1"; shift
    local options=("$@")
    local i
    printf '\n  %b?%b  %s\n' "$_CLR_CYAN" "$_CLR_RESET" "$label"
    for i in "${!options[@]}"; do
        printf '     %d) %s\n' "$((i+1))" "${options[$i]}"
    done
    while true; do
        printf '  Choice [1-%d]: ' "${#options[@]}"
        local choice
        read -r choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} )); then
            echo "${options[$((choice-1))]}"
            return 0
        fi
        printf '  Invalid choice. Enter a number between 1 and %d.\n' "${#options[@]}"
    done
}

# ---------------------------------------------------------------------------
# String helpers
# ---------------------------------------------------------------------------
# slug_from_domain domain.com → domain_com (max 32 chars, safe for DB names)
slug_from_domain() {
    echo "${1}" | tr '.' '_' | tr -cd 'a-zA-Z0-9_' | cut -c1-32
}

# human_bytes integer → "1.2 GB" etc.
human_bytes() {
    local bytes="$1"
    if   (( bytes >= 1073741824 )); then printf '%.1f GB\n' "$(echo "scale=1; $bytes/1073741824" | bc)"
    elif (( bytes >= 1048576 ));    then printf '%.1f MB\n' "$(echo "scale=1; $bytes/1048576"    | bc)"
    elif (( bytes >= 1024 ));       then printf '%.1f KB\n' "$(echo "scale=1; $bytes/1024"       | bc)"
    else printf '%d B\n' "$bytes"
    fi
}

# ---------------------------------------------------------------------------
# System detection helpers (used by multiple modules)
# ---------------------------------------------------------------------------
detect_ram_mb() {
    awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 512
}

detect_cpu_count() {
    nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 1
}

# ---------------------------------------------------------------------------
# Service helpers
# ---------------------------------------------------------------------------
svc_enable_start() {
    local svc="$1"
    systemctl enable  "$svc" 2>/dev/null && ok "Enabled  ${svc}" || warn "Could not enable ${svc}"
    systemctl start   "$svc" 2>/dev/null && ok "Started  ${svc}" || warn "Could not start  ${svc}"
}

svc_reload() {
    local svc="$1"
    systemctl reload  "$svc" 2>/dev/null \
        || systemctl restart "$svc" 2>/dev/null \
        || warn "Could not reload ${svc}"
}

# ---------------------------------------------------------------------------
# File write helper — atomic write to temp then rename
# ---------------------------------------------------------------------------
write_file() {
    local dest="$1"
    local content="$2"
    local mode="${3:-644}"
    local tmp
    tmp="$(mktemp "${dest}.XXXXXXXX")"
    printf '%s' "$content" > "$tmp"
    chmod "$mode" "$tmp"
    mv "$tmp" "$dest"
}
