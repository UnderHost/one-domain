#!/usr/bin/env bash
# =============================================================================
#  UnderHost One-Domain — Info Module
#  modules/info.sh
# =============================================================================
# Command: install info
# Shows installer environment, server specs, and software versions.
# No domain required. Safe to run without root (degrades gracefully).
# =============================================================================

[[ -n "${_UH_INFO_LOADED:-}" ]] && return 0
_UH_INFO_LOADED=1

info_show() {
    echo
    printf '%b%s%b\n' "$_CLR_LCYAN" "$(printf '═%.0s' {1..60})" "$_CLR_RESET"
    printf '%b  UnderHost One-Domain Installer%b\n' "$_CLR_BOLD" "$_CLR_RESET"
    printf '%b  v%s  |  https://underhost.com%b\n' "$_CLR_DIM" "${UNDERHOST_VERSION}" "$_CLR_RESET"
    printf '%b%s%b\n' "$_CLR_LCYAN" "$(printf '═%.0s' {1..60})" "$_CLR_RESET"
    echo

    # --- Installer ---
    printf '%b  Installer%b\n' "$_CLR_BOLD" "$_CLR_RESET"
    _info_row "Version"      "${UNDERHOST_VERSION}"
    _info_row "Location"     "${SCRIPT_DIR}/install"
    _info_row "Config file"  "$(_info_config_file)"
    echo

    # --- OS ---
    printf '%b  Operating System%b\n' "$_CLR_BOLD" "$_CLR_RESET"
    os_detect 2>/dev/null || true
    _info_row "Distribution" "${OS_ID:-unknown} ${OS_VERSION:-}"
    _info_row "Codename"     "${OS_CODENAME:-n/a}"
    _info_row "Architecture" "$(uname -m)"
    _info_row "Kernel"       "$(uname -r)"
    _info_row "Uptime"       "$(uptime -p 2>/dev/null || uptime | awk -F'up ' '{print $2}' | cut -d',' -f1)"
    echo

    # --- Hardware ---
    printf '%b  Hardware%b\n' "$_CLR_BOLD" "$_CLR_RESET"
    _info_row "CPU cores"    "$(detect_cpu_count)"
    _info_row "RAM total"    "$(detect_ram_mb) MB"
    _info_row "RAM free"     "$(awk '/MemAvailable/ {printf "%d MB", $2/1024}' /proc/meminfo)"
    _info_row "Disk / free"  "$(df -h / | awk 'NR==2{print $4}') ($(df -h / | awk 'NR==2{print $5}') used)"
    local swap
    swap="$(swapon --show=SIZE --noheadings 2>/dev/null | head -1 | xargs)"
    _info_row "Swap"         "${swap:-none}"
    echo

    # --- Software ---
    printf '%b  Software Versions%b\n' "$_CLR_BOLD" "$_CLR_RESET"
    _info_ver "Nginx"        "$(nginx -v 2>&1 | grep -oP '[\d.]+' | head -1)"
    _info_ver "PHP"          "$(_info_php_versions)"
    _info_ver "MariaDB"      "$(mysql --version 2>/dev/null | grep -oP 'Distrib \K[\d.]+'  | head -1)"
    _info_ver "Certbot"      "$(certbot --version 2>/dev/null | grep -oP '[\d.]+' | head -1)"
    _info_ver "WP-CLI"       "$(wp cli version --allow-root 2>/dev/null | awk '{print $2}')"
    _info_ver "Redis"        "$(redis-server --version 2>/dev/null | grep -oP '[\d.]+' | head -1)"
    _info_ver "Fail2Ban"     "$(fail2ban-client --version 2>/dev/null | grep -oP '[\d.]+' | head -1)"
    _info_ver "rclone"       "$(rclone version 2>/dev/null | head -1 | grep -oP '[\d.]+')"
    echo

    # --- Services ---
    printf '%b  Service Status%b\n' "$_CLR_BOLD" "$_CLR_RESET"
    for svc in nginx mariadb fail2ban redis-server redis; do
        local state
        state="$(systemctl is-active "$svc" 2>/dev/null || echo "-")"
        [[ "$state" == "-" ]] && continue
        local col="$_CLR_LGREEN"
        [[ "$state" != "active" ]] && col="$_CLR_YELLOW"
        printf '    %b%-20s%b %b%s%b\n' "$_CLR_BOLD" "${svc}:" "$_CLR_RESET" "$col" "$state" "$_CLR_RESET"
    done
    echo

    # --- Connectivity check ---
    printf '%b  External Connectivity%b\n' "$_CLR_BOLD" "$_CLR_RESET"
    _info_reach "Let's Encrypt ACME" "acme-v02.api.letsencrypt.org"
    _info_reach "WordPress.org"      "wordpress.org"
    _info_reach "PHP repo (sury)"    "packages.sury.org"
    _info_reach "REMI repo"          "rpms.remirepo.net"
    _info_reach "GitHub"             "raw.githubusercontent.com"
    echo

    printf '%b%s%b\n' "$_CLR_DIM" "$(printf '─%.0s' {1..60})" "$_CLR_RESET"
}

_info_row() {
    printf '    %b%-20s%b %s\n' "$_CLR_BOLD" "${1}:" "$_CLR_RESET" "${2:-n/a}"
}

_info_ver() {
    local label="$1" ver="${2:-}"
    if [[ -n "$ver" ]]; then
        printf '    %b%-20s%b %s\n' "$_CLR_BOLD" "${label}:" "$_CLR_RESET" "$ver"
    else
        printf '    %b%-20s%b %b%s%b\n' "$_CLR_BOLD" "${label}:" "$_CLR_RESET" "$_CLR_DIM" "not installed" "$_CLR_RESET"
    fi
}

_info_reach() {
    local label="$1" host="$2"
    if curl -fsSL --max-time 4 --head "https://${host}" &>/dev/null; then
        printf '    %b✓%b  %s\n' "$_CLR_LGREEN" "$_CLR_RESET" "$label"
    else
        printf '    %b✗%b  %s %b(unreachable)%b\n' \
            "$_CLR_YELLOW" "$_CLR_RESET" "$label" "$_CLR_YELLOW" "$_CLR_RESET"
    fi
}

_info_php_versions() {
    local vers=()
    for v in 8.1 8.2 8.3 8.4; do
        command -v "php${v}" &>/dev/null && vers+=("${v}")
    done
    command -v php &>/dev/null && [[ "${#vers[@]}" -eq 0 ]] && vers+=("$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null)")
    [[ "${#vers[@]}" -eq 0 ]] && echo "not installed" || echo "${vers[*]}"
}

_info_config_file() {
    if [[ -f /etc/underhost/defaults.conf ]]; then
        echo "/etc/underhost/defaults.conf"
    elif [[ -f "${HOME}/.one-domain.conf" ]]; then
        echo "${HOME}/.one-domain.conf"
    else
        echo "none (using built-in defaults)"
    fi
}
