#!/usr/bin/env bash
# =============================================================================
#  lib/core.sh — Shared utilities: colors, logging, prompts, validation
# =============================================================================

# ---------------------------------------------------------------------------
# Color / formatting helpers
# ---------------------------------------------------------------------------
_uh_has_color() { [[ -t 1 ]] && command -v tput &>/dev/null && tput colors &>/dev/null; }

color() {
    if ! _uh_has_color; then echo "${@:2}"; return; fi
    local code=""
    case "${1^^}" in
        RED)    code="\033[0;31m" ;;
        GREEN)  code="\033[0;32m" ;;
        YELLOW) code="\033[1;33m" ;;
        BLUE)   code="\033[0;34m" ;;
        CYAN)   code="\033[0;36m" ;;
        BOLD)   code="\033[1m"    ;;
        DIM)    code="\033[2m"    ;;
        *)      code=""            ;;
    esac
    echo -e "${code}${*:2}\033[0m"
}

# Exported format vars for inline use
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
_init_log() {
    mkdir -p "$(dirname "${LOG_FILE}")"
    touch "${LOG_FILE}" 2>/dev/null || LOG_FILE="/tmp/underhost_install_$$.log"
    exec > >(tee -a "${LOG_FILE}") 2>&1
}

_ts() { date '+%Y-%m-%d %H:%M:%S'; }

step()  { echo -e "\n${BOLD}${BLUE}▶ $*${RESET}"; }
ok()    { echo -e "${GREEN}  ✔ $*${RESET}"; }
info()  { echo -e "${CYAN}  ℹ $*${RESET}"; }
warn()  { echo -e "${YELLOW}  ⚠ $*${RESET}"; }
danger(){ echo -e "${RED}  ✖ $*${RESET}"; }
die()   { danger "FATAL: $*"; exit 1; }

# ---------------------------------------------------------------------------
# Root check
# ---------------------------------------------------------------------------
_ensure_root() {
    [[ "$EUID" -eq 0 ]] || die "This installer must be run as root (or via sudo)."
}

# ---------------------------------------------------------------------------
# Domain validation
# ---------------------------------------------------------------------------
_validate_domain() {
    local d="$1"
    local re='^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'
    [[ "$d" =~ $re ]] || die "Invalid domain: '$d'  (example: example.com)"
}

# ---------------------------------------------------------------------------
# Password generator
# ---------------------------------------------------------------------------
gen_pass() {
    # General-purpose password: alphanumeric + shell-safe specials (no quotes, backslash, or glob chars)
    local len="${1:-20}"
    tr -dc 'A-Za-z0-9!@#%^&' < /dev/urandom | head -c "${len}"
}

gen_pass_alpha() {
    # Alphanumeric only — safe for identifiers and filenames
    local len="${1:-20}"
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "${len}"
}

gen_pass_db() {
    # Database password: alphanumeric only — safe inside SQL single-quoted strings.
    # Avoids ', ", \, $, !, * which break SQL heredocs or shell interpolation.
    local len="${1:-24}"
    tr -dc 'A-Za-z0-9' < /dev/urandom | head -c "${len}"
}

# ---------------------------------------------------------------------------
# Simple y/n prompt
#   prompt_yn "Question?" "y"   → returns 0 for yes, 1 for no
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# Text input prompt with optional default
#   prompt_text "Label" "default_value" → prints answer to stdout
# ---------------------------------------------------------------------------
prompt_text() {
    local label="$1"
    local default="${2:-}"
    local hint=""
    [[ -n "$default" ]] && hint=" (default: ${YELLOW}${default}${RESET})"
    local answer
    read -r -p "$(echo -e "${CYAN}  ? ${label}${hint}: ${RESET}")" answer
    echo "${answer:-$default}"
}

# ---------------------------------------------------------------------------
# Password prompt (no echo)
# ---------------------------------------------------------------------------
prompt_pass() {
    local label="${1:-Password}"
    local answer
    read -r -s -p "$(echo -e "${CYAN}  ? ${label}: ${RESET}")" answer
    echo
    echo "$answer"
}

# ---------------------------------------------------------------------------
# Select from a list
#   prompt_select "Question" "opt1" "opt2" ...  → prints selected option
# ---------------------------------------------------------------------------
prompt_select() {
    local question="$1"; shift
    local opts=("$@")
    echo -e "${CYAN}  ? ${question}${RESET}"
    local i=1
    for opt in "${opts[@]}"; do
        echo -e "    ${YELLOW}${i})${RESET} ${opt}"
        ((i++))
    done
    local choice
    while true; do
        read -r -p "$(echo -e "${CYAN}  Enter number [1-${#opts[@]}]: ${RESET}")" choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#opts[@]} )); then
            echo "${opts[$((choice-1))]}"
            return
        fi
        echo -e "${RED}  Invalid choice, try again.${RESET}"
    done
}

# ---------------------------------------------------------------------------
# Section banner
# ---------------------------------------------------------------------------
section_banner() {
    local title="$1"
    local width=62
    local line
    line=$(printf '%*s' "$width" '' | tr ' ' '─')
    echo -e "\n${BOLD}${BLUE}┌${line}┐${RESET}"
    printf "${BOLD}${BLUE}│${RESET}  %-60s${BOLD}${BLUE}│${RESET}\n" "$title"
    echo -e "${BOLD}${BLUE}└${line}┘${RESET}"
}

# ---------------------------------------------------------------------------
# Security warning box
# ---------------------------------------------------------------------------
security_warning() {
    echo -e "\n${RED}┌─────────────────────── SECURITY WARNING ───────────────────────┐${RESET}"
    while IFS= read -r line; do
        printf "${RED}│${RESET}  %-63s${RED}│${RESET}\n" "$line"
    done <<< "$*"
    echo -e "${RED}└────────────────────────────────────────────────────────────────┘${RESET}\n"
}

# ---------------------------------------------------------------------------
# RAM info helpers
# ---------------------------------------------------------------------------
get_total_ram_mb() {
    awk '/MemTotal/ {printf "%.0f", $2/1024}' /proc/meminfo
}

get_cpu_cores() {
    nproc
}
