#!/usr/bin/env bash
# =============================================================================
#  modules/status.sh — Quick domain health status
#
#  Usage:  install status domain.com
#          install --status domain.com
# =============================================================================

status_domain() {
    local domain="${1:-$DOMAIN}"
    [[ -z "$domain" ]] && die "Usage: install status domain.com"
    _validate_domain "$domain"

    os_detect 2>/dev/null || true

    local site_root="/var/www/${domain}"
    local vhost_file="/etc/nginx/conf.d/${domain}.conf"
    local pool_dir
    pool_dir="$(os_php_fpm_pool_dir 2>/dev/null || echo /etc/php-fpm.d)"
    local pool_file="${pool_dir}/${domain}.conf"
    local ssl_cert="/etc/letsencrypt/live/${domain}/cert.pem"
    local staging_domain="staging.${domain}"

    # ---- Detect PHP version from pool ----
    local php_ver="unknown"
    if [[ -f "$pool_file" ]]; then
        php_ver="$(grep -oP 'php\K[\d.]+' <<< "$pool_file" 2>/dev/null || echo "detected")"
        # Try extracting from socket path inside pool
        local sock_line
        sock_line="$(grep '^listen\s*=' "$pool_file" 2>/dev/null | head -1)"
        if [[ "$sock_line" =~ php([0-9.]+) ]]; then
            php_ver="${BASH_REMATCH[1]}"
        fi
    fi

    # ---- SSL expiry ----
    local ssl_status="✖ Not installed"
    local ssl_expiry=""
    if [[ -f "$ssl_cert" ]]; then
        ssl_expiry="$(openssl x509 -enddate -noout -in "$ssl_cert" 2>/dev/null \
            | sed 's/notAfter=//' || echo "unknown")"
        ssl_status="✔ Installed (expires: ${ssl_expiry})"
    fi

    # ---- Service states ----
    local nginx_st mariadb_st php_st redis_st f2b_st
    nginx_st="$(  systemctl is-active nginx    2>/dev/null || echo "inactive")"
    mariadb_st="$(systemctl is-active mariadb  2>/dev/null || echo "inactive")"
    redis_st="$(  systemctl is-active redis    2>/dev/null || echo "not installed")"
    f2b_st="$(    systemctl is-active fail2ban 2>/dev/null || echo "not installed")"

    # PHP-FPM — try versioned then generic
    php_st="inactive"
    for svc in "php${php_ver}-fpm" php8.3-fpm php8.2-fpm php-fpm; do
        if systemctl is-active "$svc" &>/dev/null; then
            php_st="active ($svc)"
            break
        fi
    done

    # ---- Firewall ----
    local fw_st="not installed"
    if command -v ufw &>/dev/null; then
        fw_st="$(ufw status 2>/dev/null | head -1 | awk '{print $2}')"
        [[ -z "$fw_st" ]] && fw_st="inactive"
        fw_st="ufw: ${fw_st}"
    elif command -v firewall-cmd &>/dev/null; then
        fw_st="firewalld: $(firewall-cmd --state 2>/dev/null || echo unknown)"
    fi

    # ---- DB connection check ----
    local db_st="✖ Cannot verify (no root pass)"
    # Try unix socket auth (works on fresh installs)
    if mysql -u root --connect-timeout=3 -e "SELECT 1;" &>/dev/null 2>&1; then
        db_st="✔ Connected (unix socket)"
    fi

    # ---- WordPress detection ----
    local wp_st="Not detected"
    local wp_ver=""
    if [[ -f "${site_root}/wp-config.php" ]]; then
        wp_ver="$(grep -oP "wp_version = '\K[^']+" \
            "${site_root}/wp-includes/version.php" 2>/dev/null || echo "unknown")"
        wp_st="✔ WordPress ${wp_ver}"
    fi

    # ---- Disk usage ----
    local disk_usage="N/A"
    [[ -d "$site_root" ]] && disk_usage="$(du -sh "$site_root" 2>/dev/null | cut -f1)"

    # ---- Render ----
    local _c_ok _c_warn _c_dim _c_reset _c_bold _c_head
    _c_ok="\033[0;32m"
    _c_warn="\033[1;33m"
    _c_dim="\033[2m"
    _c_reset="\033[0m"
    _c_bold="\033[1m"
    _c_head="\033[0;36m"

    echo -e "\n${_c_bold}${_c_head}╔══════════════════════════════════════════════════════════╗${_c_reset}"
    printf   "${_c_bold}${_c_head}║${_c_reset}  %-56s${_c_bold}${_c_head}║${_c_reset}\n" "UnderHost Status: ${domain}"
    echo -e "${_c_bold}${_c_head}╚══════════════════════════════════════════════════════════╝${_c_reset}"

    echo -e "\n${_c_bold}  SITE${_c_reset}"
    _status_row "Domain"      "$domain"
    _status_row "Doc root"    "${site_root}$( [[ -d $site_root ]] && echo '' || echo ' (missing)')"
    _status_row "Disk usage"  "$disk_usage"
    _status_row "PHP version" "$php_ver"
    _status_row "SSL"         "$ssl_status"
    _status_row "WordPress"   "$wp_st"

    echo -e "\n${_c_bold}  SERVICES${_c_reset}"
    _status_svc "Nginx"       "$nginx_st"
    _status_svc "MariaDB"     "$mariadb_st"
    _status_svc "PHP-FPM"     "$php_st"
    _status_svc "Redis"       "$redis_st"
    _status_svc "Fail2Ban"    "$f2b_st"
    _status_row  "Firewall"   "$fw_st"
    _status_row  "Database"   "$db_st"

    echo -e "\n${_c_bold}  CONFIGS${_c_reset}"
    _status_file "Nginx vhost"  "$vhost_file"
    _status_file "PHP-FPM pool" "$pool_file"
    _status_file "SSL cert"     "$ssl_cert"
    _status_file "Staging vhost" "/etc/nginx/conf.d/${staging_domain}.conf"

    echo
}

_status_row() {
    printf "  %-16s : %s\n" "$1" "$2"
}

_status_svc() {
    local label="$1" state="$2"
    local icon color
    case "$state" in
        active*)   icon="✔" ; color="\033[0;32m" ;;
        inactive*) icon="✖" ; color="\033[0;31m" ;;
        *)         icon="?" ; color="\033[1;33m" ;;
    esac
    printf "  %-16s : ${color}%s %s\033[0m\n" "$label" "$icon" "$state"
}

_status_file() {
    local label="$1" path="$2"
    if [[ -f "$path" ]]; then
        printf "  %-16s : \033[0;32m✔\033[0m %s\n" "$label" "$path"
    else
        printf "  %-16s : \033[2m✖ not found\033[0m\n" "$label"
    fi
}
