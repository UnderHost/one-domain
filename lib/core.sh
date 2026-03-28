#!/usr/bin/env bash
# =============================================================================
#  lib/core.sh — Shared utilities: colors, logging, prompts, validation
# =============================================================================

# ---------------------------------------------------------------------------
# Color / formatting helpers
# ---------------------------------------------------------------------------
_uh_has_color() {
    [[ -t 1 ]] && command -v tput &>/dev/null && tput colors &>/dev/null && [[ "$(tput colors)" -ge 8 ]]
}

# Exported ANSI codes — used inline in heredocs and echo -e strings
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

color() {
    # color CODE "text"  — wrap text in ANSI color if terminal supports it
    if ! _uh_has_color; then echo "${*:2}"; return; fi
    local code=""
    case "${1^^}" in
        RED)    code="\033[0;31m" ;;
        GREEN)  code="\033[0;32m" ;;
        YELLOW) code="\033[1;33m" ;;
        BLUE)   code="\033[0;34m" ;;
        CYAN)   code="\033[0;36m" ;;
        BOLD)   code="\033[1m"    ;;
        DIM)    code="\033[2m"    ;;
        *)      code=""           ;;
    esac
    echo -e "${code}${*:2}\033[0m"
}

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
_init_log() {
    mkdir -p "$(dirname "${LOG_FILE}")" 2>/dev/null || true
    touch "${LOG_FILE}" 2>/dev/null || LOG_FILE="/tmp/underhost_install_$$.log"
    # Tee stdout+stderr to log file without buffering
    exec > >(tee -a "${LOG_FILE}") 2>&1
}

_ts() { date '+%Y-%m-%d %H:%M:%S'; }

step()   { echo -e "\n${BOLD}${BLUE}▶ $*${RESET}"; }
ok()     { echo -e "${GREEN}  ✔ $*${RESET}"; }
info()   { echo -e "${CYAN}  ℹ $*${RESET}"; }
warn()   { echo -e "${YELLOW}  ⚠ $*${RESET}"; }
danger() { echo -e "${RED}  ✖ $*${RESET}"; }
die()    { danger "FATAL: $*"; exit 1; }

# ---------------------------------------------------------------------------
# Root check
# ---------------------------------------------------------------------------
_ensure_root() {
    [[ "$EUID" -eq 0 ]] || die "This installer must be run as root (or via sudo)."
}

# ---------------------------------------------------------------------------
# Domain validation (RFC 1123 compatible)
# ---------------------------------------------------------------------------
_validate_domain() {
    local d="${1:-}"
    [[ -z "$d" ]] && die "Domain name is required."
    # Labels: 1-63 alphanumeric/hyphen chars, not starting/ending with hyphen
    # TLD: 2+ letters
    local re='^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'
    [[ "$d" =~ $re ]] || die "Invalid domain: '${d}'  (example: example.com or sub.example.com)"
}

# ---------------------------------------------------------------------------
# Email validation (basic format check)
# ---------------------------------------------------------------------------
_validate_email() {
    local e="${1:-}"
    [[ -z "$e" ]] && die "Email address is required."
    local re='^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$'
    [[ "$e" =~ $re ]] || die "Invalid email: '${e}'"
}

# ---------------------------------------------------------------------------
# Password generators
# ---------------------------------------------------------------------------

# General password: alphanumeric + shell-safe specials
gen_pass() {
    local len="${1:-20}"
    tr -dc 'A-Za-z0-9!@#%^&' < /dev/urandom | head -c "${len}"
    echo  # newline so callers using $() get clean output
}

# Alphanumeric only — safe for identifiers and filenames
gen_pass_alpha() {
    local len="${1:-20}"
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "${len}"
    echo
}

# Database passwords: alphanumeric only — safe inside SQL quoted strings
# Avoids ', ", \, $, !, * which break SQL heredocs or shell interpolation
gen_pass_db() {
    local len="${1:-24}"
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "${len}"
    echo
}

# ---------------------------------------------------------------------------
# Prompts
# ---------------------------------------------------------------------------

# prompt_yn "Question?" "y"  → returns 0 for yes, 1 for no
prompt_yn() {
    local question="$1"
    local default="${2:-n}"
    local hint
    [[ "$default" == "y" ]] && hint="[Y/n]" || hint="[y/N]"
    local answer
    read -r -p "$(echo -e "${CYAN}  ? ${question} ${hint} ${RESET}")" answer
    answer="${answer:-$default}"
    case "${answer,,}" in
        y|yes) return 0 ;;
        *)     return 1 ;;
    esac
}

# prompt_text "Label" "default"  → prints answer to stdout
prompt_text() {
    local label="$1"
    local default="${2:-}"
    local hint=""
    [[ -n "$default" ]] && hint=" (default: ${YELLOW}${default}${RESET})"
    local answer
    read -r -p "$(echo -e "${CYAN}  ? ${label}${hint}: ${RESET}")" answer
    echo "${answer:-$default}"
}

# prompt_pass "Label"  → prints password to stdout (no echo)
prompt_pass() {
    local label="${1:-Password}"
    local answer
    read -r -s -p "$(echo -e "${CYAN}  ? ${label}: ${RESET}")" answer
    echo >&2  # newline after hidden input
    echo "$answer"
}

# prompt_select "Question" "opt1" "opt2" ...  → prints selected option
prompt_select() {
    local question="$1"; shift
    local opts=("$@")
    echo -e "${CYAN}  ? ${question}${RESET}"
    local i=1
    for opt in "${opts[@]}"; do
        echo -e "    ${YELLOW}${i})${RESET} ${opt}"
        (( i++ ))
    done
    local choice
    while true; do
        read -r -p "$(echo -e "${CYAN}  Enter number [1-${#opts[@]}]: ${RESET}")" choice
        if [[ "$choice" =~ ^[0-9]+$ ]] \
        && (( choice >= 1 && choice <= ${#opts[@]} )); then
            echo "${opts[$((choice-1))]}"
            return
        fi
        echo -e "${RED}  Invalid choice — enter a number between 1 and ${#opts[@]}${RESET}"
    done
}

# ---------------------------------------------------------------------------
# UI helpers
# ---------------------------------------------------------------------------

section_banner() {
    local title="$1"
    local width=62
    local line
    line="$(printf '%*s' "$width" '' | tr ' ' '─')"
    echo -e "\n${BOLD}${BLUE}┌${line}┐${RESET}"
    printf "${BOLD}${BLUE}│${RESET}  %-60s${BOLD}${BLUE}│${RESET}\n" "$title"
    echo -e "${BOLD}${BLUE}└${line}┘${RESET}"
}

security_warning() {
    echo -e "\n${RED}┌─────────────────────── SECURITY WARNING ───────────────────────┐${RESET}"
    while IFS= read -r line; do
        printf "${RED}│${RESET}  %-63s${RED}│${RESET}\n" "$line"
    done <<< "$*"
    echo -e "${RED}└────────────────────────────────────────────────────────────────┘${RESET}\n"
}

# ---------------------------------------------------------------------------
# System info helpers
# ---------------------------------------------------------------------------
get_total_ram_mb() {
    awk '/MemTotal/ {printf "%.0f", $2/1024}' /proc/meminfo
}

get_cpu_cores() {
    nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo 1
}
