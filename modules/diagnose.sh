#!/usr/bin/env bash
# =============================================================================
#  UnderHost One-Domain — Diagnostic Module
#  modules/diagnose.sh
# =============================================================================

[[ -n "${_UH_DIAGNOSE_LOADED:-}" ]] && return 0
_UH_DIAGNOSE_LOADED=1

diagnose_domain() {
    local dom="${1:-}"
    [[ -z "$dom" ]] && die "Usage: install diagnose domain.com"

    step "Diagnostic report: ${dom}"

    echo
    printf '%bSystem%b\n' "$_CLR_BOLD" "$_CLR_RESET"
    printf '  OS:       %s %s\n' "${OS_ID:-unknown}" "${OS_VERSION:-}"
    printf '  Kernel:   %s\n'    "$(uname -r)"
    printf '  RAM:      %s MB\n' "$(detect_ram_mb)"
    printf '  CPU:      %s cores\n' "$(detect_cpu_count)"
    printf '  Uptime:   %s\n'    "$(uptime -p 2>/dev/null || uptime)"
    printf '  Disk /:   %s free\n' "$(df -h / | awk 'NR==2{print $4}')"

    echo
    printf '%bNginx%b\n' "$_CLR_BOLD" "$_CLR_RESET"
    nginx -v 2>&1 | sed 's/^/  /'
    nginx -t 2>&1 | sed 's/^/  /'

    echo
    printf '%bPHP%b\n' "$_CLR_BOLD" "$_CLR_RESET"
    local php_bin
    php_bin="$(os_php_bin 2>/dev/null || echo php)"
    "$php_bin" --version 2>/dev/null | head -1 | sed 's/^/  /'

    echo
    printf '%bMariaDB%b\n' "$_CLR_BOLD" "$_CLR_RESET"
    mysql --version 2>/dev/null | sed 's/^/  /'
    mysql -e "SHOW GLOBAL STATUS LIKE 'Uptime';" 2>/dev/null | sed 's/^/  /' || true

    echo
    printf '%bSSL — %s%b\n' "$_CLR_BOLD" "$dom" "$_CLR_RESET"
    local cert="/etc/letsencrypt/live/${dom}/fullchain.pem"
    if [[ -f "$cert" ]]; then
        openssl x509 -noout -subject -issuer -enddate -in "$cert" 2>/dev/null | sed 's/^/  /'
    else
        printf '  No certificate found at %s\n' "$cert"
    fi

    echo
    printf '%bNginx error log (last 20 lines) — %s%b\n' "$_CLR_BOLD" "$dom" "$_CLR_RESET"
    local errlog="/var/log/nginx/${dom}.error.log"
    if [[ -f "$errlog" ]]; then
        tail -20 "$errlog" | sed 's/^/  /'
    else
        printf '  Log not found: %s\n' "$errlog"
    fi

    echo
    printf '%bPHP-FPM error log (last 20 lines) — %s%b\n' "$_CLR_BOLD" "$dom" "$_CLR_RESET"
    local phplog="/var/log/php-fpm/${dom}.error.log"
    if [[ -f "$phplog" ]]; then
        tail -20 "$phplog" | sed 's/^/  /'
    else
        printf '  Log not found: %s\n' "$phplog"
    fi

    echo
    printf '%bFail2Ban jails%b\n' "$_CLR_BOLD" "$_CLR_RESET"
    fail2ban-client status 2>/dev/null | sed 's/^/  /' || printf '  fail2ban not running\n'

    echo
}
