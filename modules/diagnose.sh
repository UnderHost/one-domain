#!/usr/bin/env bash
# =============================================================================
#  modules/diagnose.sh — Advanced diagnostic / troubleshooting report
#
#  Usage:  install diagnose domain.com
#          install --diagnose domain.com
# =============================================================================

diagnose_domain() {
    local domain="${1:-$DOMAIN}"
    [[ -z "$domain" ]] && die "Usage: install diagnose domain.com"
    _validate_domain "$domain"

    os_detect 2>/dev/null || true

    section_banner "UnderHost Diagnostic Report: ${domain}"
    echo -e "  Generated: $(date)\n"

    _diag_section "SYSTEM"
    _diag_os
    _diag_resources

    _diag_section "NETWORK & PORTS"
    _diag_ports
    _diag_dns "$domain"

    _diag_section "SERVICES"
    _diag_services

    _diag_section "SSL"
    _diag_ssl "$domain"

    _diag_section "NGINX"
    _diag_nginx "$domain"

    _diag_section "PHP-FPM"
    _diag_php "$domain"

    _diag_section "DATABASE"
    _diag_db

    _diag_section "REDIS"
    _diag_redis

    _diag_section "DISK & LOGS"
    _diag_disk "$domain"

    echo -e "\n${GREEN}  Diagnostic complete.${RESET}"
    echo -e "  If you see ${RED}✖ FAIL${RESET} items above, run: ${CYAN}install repair ${domain}${RESET}\n"
}

# ---------------------------------------------------------------------------
_diag_section() {
    echo -e "\n${BOLD}${BLUE}── $1 ─────────────────────────────────────────${RESET}"
}

_diag_pass() { echo -e "  ${GREEN}✔ PASS${RESET}  $*"; }
_diag_fail() { echo -e "  ${RED}✖ FAIL${RESET}  $*"; }
_diag_warn() { echo -e "  ${YELLOW}⚠ WARN${RESET}  $*"; }
_diag_info() { echo -e "  ${CYAN}ℹ INFO${RESET}  $*"; }

# ---------------------------------------------------------------------------
_diag_os() {
    _diag_info "OS: ${OS_ID:-unknown} ${OS_VERSION:-} ($(uname -r))"

    local supported=false
    case "${OS_ID:-}" in
        ubuntu)   [[ "${OS_VERSION:-}" =~ ^(24|25) ]] && supported=true ;;
        debian)   [[ "${OS_VERSION:-}" =~ ^(12|13) ]] && supported=true ;;
        almalinux)[[ "${OS_VERSION:-}" =~ ^(9|10)  ]] && supported=true ;;
    esac
    $supported && _diag_pass "OS is supported" \
               || _diag_warn "OS may not be fully supported by UnderHost"
}

# ---------------------------------------------------------------------------
_diag_resources() {
    local ram_mb cpu_cores disk_free
    ram_mb="$(awk '/MemTotal/{printf "%.0f",$2/1024}' /proc/meminfo 2>/dev/null || echo 0)"
    cpu_cores="$(nproc 2>/dev/null || echo 1)"
    disk_free="$(df -BM / 2>/dev/null | awk 'NR==2{print $4}' | tr -d 'M')"

    _diag_info "RAM: ${ram_mb} MB  |  CPU cores: ${cpu_cores}  |  / free: ${disk_free:-?} MB"

    (( ram_mb  >=  512 )) && _diag_pass "RAM ≥ 512 MB"  || _diag_warn "Low RAM (${ram_mb} MB) — performance may suffer"
    (( ${disk_free:-0} >= 2048 )) && _diag_pass "Disk free ≥ 2 GB" \
        || _diag_warn "Low disk space (${disk_free:-?} MB free)"

    # Swap
    local swap_mb
    swap_mb="$(awk '/SwapTotal/{printf "%.0f",$2/1024}' /proc/meminfo 2>/dev/null || echo 0)"
    (( swap_mb > 0 )) && _diag_pass "Swap enabled (${swap_mb} MB)" \
                      || _diag_warn "No swap configured — consider enabling it"
}

# ---------------------------------------------------------------------------
_diag_ports() {
    local port svc
    declare -A port_map=([80]="HTTP" [443]="HTTPS" [3306]="MariaDB" [6379]="Redis" [22]="SSH")
    for port in 80 443 22 3306 6379; do
        svc="${port_map[$port]}"
        if ss -tlnp 2>/dev/null | grep -q ":${port}\b" \
        || netstat -tlnp 2>/dev/null | grep -q ":${port} "; then
            _diag_pass "Port ${port} (${svc}) is listening"
        else
            case "$port" in
                80|443) _diag_fail "Port ${port} (${svc}) not listening — Nginx may be down" ;;
                22)     _diag_warn "Port 22 (SSH) not detected on standard port" ;;
                3306)   _diag_info "Port 3306 (MariaDB) not exposed — expected if socket-only" ;;
                6379)   _diag_info "Port 6379 (Redis) not listening — may be disabled or socket-only" ;;
            esac
        fi
    done
}

# ---------------------------------------------------------------------------
_diag_dns() {
    local domain="$1"
    local server_ip
    server_ip="$(curl -sf --max-time 5 https://api.ipify.org 2>/dev/null \
              || hostname -I 2>/dev/null | awk '{print $1}' \
              || echo "unknown")"

    _diag_info "Server IP: ${server_ip}"

    local resolved_ip
    resolved_ip="$(dig +short "${domain}" A 2>/dev/null | tail -1 \
               || host "${domain}" 2>/dev/null | awk '/has address/{print $NF}' | head -1 \
               || echo "")"

    if [[ -z "$resolved_ip" ]]; then
        _diag_warn "DNS for ${domain} not resolving — check your DNS records"
    elif [[ "$resolved_ip" == "$server_ip" ]]; then
        _diag_pass "DNS for ${domain} → ${resolved_ip} (matches this server)"
    else
        _diag_warn "DNS for ${domain} → ${resolved_ip} (server IP: ${server_ip}) — may be CDN/proxy"
    fi

    # www check
    local www_ip
    www_ip="$(dig +short "www.${domain}" A 2>/dev/null | tail -1 || echo "")"
    [[ -n "$www_ip" ]] \
        && _diag_pass "www.${domain} resolves to ${www_ip}" \
        || _diag_warn "www.${domain} has no DNS record"
}

# ---------------------------------------------------------------------------
_diag_services() {
    local svc state
    declare -A svcs=(
        [nginx]="Nginx web server"
        [mariadb]="MariaDB database"
        [fail2ban]="Fail2Ban intrusion prevention"
        [redis]="Redis cache"
        [cron]="Cron daemon"
        [ssh]="SSH daemon"
        [sshd]="SSH daemon"
    )
    local checked_ssh=false
    for svc in nginx mariadb fail2ban redis cron; do
        state="$(systemctl is-active "$svc" 2>/dev/null || echo "not-found")"
        case "$state" in
            active)   _diag_pass "${svcs[$svc]:-$svc} is active" ;;
            inactive) _diag_warn "${svcs[$svc]:-$svc} is inactive — run: systemctl start $svc" ;;
            not-found) [[ "$svc" == "redis" || "$svc" == "fail2ban" ]] \
                && _diag_info "${svcs[$svc]:-$svc} not installed" \
                || _diag_fail "${svcs[$svc]:-$svc} not found" ;;
            *) _diag_warn "${svcs[$svc]:-$svc}: ${state}" ;;
        esac
    done
    # SSH
    for svc in ssh sshd; do
        if systemctl is-active "$svc" &>/dev/null; then
            _diag_pass "SSH daemon is active ($svc)"
            checked_ssh=true
            break
        fi
    done
    $checked_ssh || _diag_warn "SSH daemon not detected"
}

# ---------------------------------------------------------------------------
_diag_ssl() {
    local domain="$1"
    local cert="/etc/letsencrypt/live/${domain}/cert.pem"

    if [[ ! -f "$cert" ]]; then
        _diag_warn "No SSL certificate found for ${domain}"
        return
    fi

    local expiry days_left
    expiry="$(openssl x509 -enddate -noout -in "$cert" 2>/dev/null | sed 's/notAfter=//')"
    days_left="$(( ( $(date -d "$expiry" +%s 2>/dev/null || date -jf "%b %d %T %Y %Z" "$expiry" +%s 2>/dev/null || echo 0) - $(date +%s) ) / 86400 ))"

    _diag_pass "SSL certificate exists for ${domain}"
    _diag_info "Expires: ${expiry} (${days_left} days)"

    (( days_left > 30 )) && _diag_pass "Certificate valid for ${days_left} days" \
    || (( days_left > 0 )) && _diag_warn "Certificate expires in ${days_left} days — renew soon" \
    || _diag_fail "Certificate EXPIRED — run: certbot renew --force-renewal -d ${domain}"

    # Certbot timer
    if systemctl is-active certbot.timer &>/dev/null \
    || systemctl is-active certbot-renew.timer &>/dev/null; then
        _diag_pass "Certbot auto-renewal timer is active"
    else
        _diag_warn "Certbot renewal timer not detected — SSL may not renew automatically"
    fi
}

# ---------------------------------------------------------------------------
_diag_nginx() {
    local domain="$1"
    local vhost="/etc/nginx/conf.d/${domain}.conf"

    command -v nginx &>/dev/null || { _diag_fail "Nginx not installed"; return; }
    _diag_pass "Nginx binary found: $(nginx -v 2>&1 | head -1)"

    if nginx -t 2>/dev/null; then
        _diag_pass "Nginx config test passed"
    else
        _diag_fail "Nginx config test FAILED — run: nginx -t"
    fi

    [[ -f "$vhost" ]] && _diag_pass "vhost config exists: ${vhost}" \
                      || _diag_fail "vhost config missing: ${vhost}"
}

# ---------------------------------------------------------------------------
_diag_php() {
    local domain="$1"
    local pool_dir
    pool_dir="$(os_php_fpm_pool_dir 2>/dev/null || echo /etc/php-fpm.d)"
    local pool_file="${pool_dir}/${domain}.conf"

    command -v php &>/dev/null && _diag_pass "PHP found: $(php -v 2>/dev/null | head -1)" \
                               || _diag_warn "PHP CLI not in PATH"

    [[ -f "$pool_file" ]] && _diag_pass "PHP-FPM pool exists: ${pool_file}" \
                          || _diag_fail "PHP-FPM pool missing: ${pool_file}"

    # Socket check
    if [[ -f "$pool_file" ]]; then
        local sock
        sock="$(grep -E '^listen\s*=' "$pool_file" 2>/dev/null | awk -F= '{print $2}' | tr -d ' ')"
        if [[ -n "$sock" && -S "$sock" ]]; then
            _diag_pass "PHP-FPM socket exists: ${sock}"
        elif [[ -n "$sock" ]]; then
            _diag_fail "PHP-FPM socket missing: ${sock} — PHP-FPM may not be running"
        fi
    fi
}

# ---------------------------------------------------------------------------
_diag_db() {
    command -v mysql &>/dev/null || { _diag_fail "MySQL/MariaDB client not installed"; return; }
    _diag_pass "MySQL client found"

    if mysql -u root --connect-timeout=3 -e "SELECT VERSION();" 2>/dev/null | grep -q "[0-9]"; then
        local ver
        ver="$(mysql -u root --connect-timeout=3 -e "SELECT VERSION();" 2>/dev/null | tail -1)"
        _diag_pass "MariaDB connected via unix socket (${ver})"
    else
        _diag_warn "Could not connect to MariaDB as root via unix socket"
        _diag_info "Provide root password with: mysql -u root -p"
    fi
}

# ---------------------------------------------------------------------------
_diag_redis() {
    command -v redis-cli &>/dev/null || { _diag_info "Redis not installed"; return; }

    if redis-cli ping 2>/dev/null | grep -q "PONG"; then
        _diag_pass "Redis ping OK"
        local mem
        mem="$(redis-cli info memory 2>/dev/null | grep used_memory_human | cut -d: -f2 | tr -d '\r')"
        _diag_info "Redis memory used: ${mem:-unknown}"
    else
        _diag_fail "Redis not responding — run: systemctl start redis"
    fi
}

# ---------------------------------------------------------------------------
_diag_disk() {
    local domain="$1"
    local site_root="/var/www/${domain}"

    # Overall disk
    _diag_info "Disk usage:"
    df -h / /var/www /var/log 2>/dev/null | awk 'NR==1 || /^\// {printf "    %s\n",$0}' || true

    # Site root size
    if [[ -d "$site_root" ]]; then
        local sz
        sz="$(du -sh "$site_root" 2>/dev/null | cut -f1)"
        _diag_info "Site root ${site_root}: ${sz}"
    fi

    # Log size
    local log_sz
    log_sz="$(du -sh /var/log/nginx 2>/dev/null | cut -f1 || echo 0)"
    _diag_info "Nginx logs: ${log_sz}"

    # Check for large logs
    local big_log
    big_log="$(find /var/log/nginx -name "${domain}*" -size +100M 2>/dev/null | head -3)"
    [[ -n "$big_log" ]] && _diag_warn "Large log file(s) detected:\n${big_log}" \
                        || _diag_pass "No oversized log files for ${domain}"
}
