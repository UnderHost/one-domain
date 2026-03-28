#!/usr/bin/env bash
# =============================================================================
#  UnderHost One-Domain — Security Audit Module
#  modules/audit.sh
# =============================================================================
# Command: install audit [domain]
# Checks the installed state against the expected hardened baseline.
# Outputs a colour-coded pass/fail checklist. Non-destructive, read-only.
# =============================================================================

[[ -n "${_UH_AUDIT_LOADED:-}" ]] && return 0
_UH_AUDIT_LOADED=1

_AUDIT_PASS=0
_AUDIT_WARN=0
_AUDIT_FAIL=0

audit_run() {
    local dom="${1:-}"

    _AUDIT_PASS=0
    _AUDIT_WARN=0
    _AUDIT_FAIL=0

    step "Security baseline audit${dom:+ — ${dom}}"
    echo

    # --- System checks ---
    printf '%b  System%b\n' "$_CLR_BOLD" "$_CLR_RESET"
    _acheck "SSH: PermitRootLogin is prohibit-password or no" \
        "grep -qE '^PermitRootLogin (prohibit-password|no)' /etc/ssh/sshd_config"
    _acheck "SSH: MaxAuthTries ≤ 4" \
        "grep -qE '^MaxAuthTries [1-4]$' /etc/ssh/sshd_config"
    _acheck "SSH: X11Forwarding disabled" \
        "grep -qE '^X11Forwarding no' /etc/ssh/sshd_config"
    _acheck "Kernel: SYN cookies enabled" \
        "[[ \"\$(sysctl -n net.ipv4.tcp_syncookies 2>/dev/null)\" == '1' ]]"
    _acheck "Kernel: rp_filter enabled" \
        "[[ \"\$(sysctl -n net.ipv4.conf.all.rp_filter 2>/dev/null)\" == '1' ]]"
    _acheck "Kernel: ICMP broadcast ignored" \
        "[[ \"\$(sysctl -n net.ipv4.icmp_echo_ignore_broadcasts 2>/dev/null)\" == '1' ]]"
    _acheck "Kernel: dmesg restricted" \
        "[[ \"\$(sysctl -n kernel.dmesg_restrict 2>/dev/null)\" == '1' ]]"
    _acheck "Kernel: kptr_restrict set" \
        "[[ \"\$(sysctl -n kernel.kptr_restrict 2>/dev/null)\" -ge '1' ]]"
    _acheck "/dev/shm: noexec mounted" \
        "mount | grep -q '/dev/shm.*noexec'"
    _acheck "Fail2Ban: running" \
        "systemctl is-active fail2ban &>/dev/null"
    _acheck "Fail2Ban: SSH jail active" \
        "fail2ban-client status sshd &>/dev/null"
    _awarn  "Auto OS updates configured" \
        "systemctl is-active unattended-upgrades &>/dev/null || systemctl is-active dnf-automatic &>/dev/null"

    echo

    # --- Nginx ---
    printf '%b  Nginx%b\n' "$_CLR_BOLD" "$_CLR_RESET"
    _acheck "Nginx: running" \
        "systemctl is-active nginx &>/dev/null"
    _acheck "Nginx: server_tokens off" \
        "grep -r 'server_tokens off' /etc/nginx/ &>/dev/null"
    _acheck "Nginx: config test passes" \
        "nginx -t &>/dev/null"
    _acheck "Nginx: rate-limit zone defined" \
        "grep -r 'limit_req_zone' /etc/nginx/ &>/dev/null"

    echo

    # --- MariaDB ---
    printf '%b  MariaDB%b\n' "$_CLR_BOLD" "$_CLR_RESET"
    _acheck "MariaDB: running" \
        "systemctl is-active mariadb &>/dev/null"
    _acheck "MariaDB: no anonymous users" \
        "[[ \"\$(mysql -BNe \"SELECT COUNT(*) FROM mysql.user WHERE User=''\" 2>/dev/null)\" == '0' ]]"
    _acheck "MariaDB: no remote root login" \
        "[[ \"\$(mysql -BNe \"SELECT COUNT(*) FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost','127.0.0.1','::1')\" 2>/dev/null)\" == '0' ]]"
    _acheck "MariaDB: test database removed" \
        "[[ \"\$(mysql -BNe \"SHOW DATABASES LIKE 'test'\" 2>/dev/null)\" == '' ]]"
    _acheck "/root/.my.cnf exists (600)" \
        "[[ -f /root/.my.cnf ]] && [[ \"\$(stat -c %a /root/.my.cnf)\" == '600' ]]"

    echo

    # --- PHP ---
    printf '%b  PHP%b\n' "$_CLR_BOLD" "$_CLR_RESET"
    _acheck "PHP: expose_php off (pool config)" \
        "grep -r 'expose_php.*off' /etc/php* &>/dev/null"
    _acheck "PHP: display_errors off" \
        "grep -r 'display_errors.*off' /etc/php* &>/dev/null"
    _acheck "PHP: OPcache enabled" \
        "grep -r 'opcache.enable.*1' /etc/php* &>/dev/null"

    echo

    # --- Domain-specific ---
    if [[ -n "$dom" ]]; then
        printf '%b  Domain: %s%b\n' "$_CLR_BOLD" "$dom" "$_CLR_RESET"
        local site_root="/var/www/${dom}/public"
        local conf_dir
        conf_dir="$(os_nginx_conf_dir 2>/dev/null || echo /etc/nginx/conf.d)"
        local vhost="${conf_dir}/${dom}.conf"
        local cert="/etc/letsencrypt/live/${dom}/fullchain.pem"

        _acheck "Nginx vhost exists" "[[ -f '${vhost}' ]]"
        _acheck "SSL certificate present" "[[ -f '${cert}' ]]"

        if [[ -f "$cert" ]]; then
            local days
            days="$(( ( $(date -d "$(openssl x509 -noout -enddate -in "$cert" 2>/dev/null | cut -d= -f2)" +%s 2>/dev/null || echo 0) - $(date +%s) ) / 86400 ))"
            if (( days > 14 )); then
                _acheck "SSL: cert valid (${days} days remaining)" "true"
            elif (( days > 0 )); then
                _awarn "SSL: cert expiring soon (${days} days)" "false"
            else
                _afail "SSL: certificate EXPIRED"
            fi
        fi

        _acheck "Nginx: X-Frame-Options header" \
            "grep -q 'X-Frame-Options' '${vhost}' &>/dev/null"
        _acheck "Nginx: HSTS header" \
            "grep -q 'Strict-Transport-Security' '${vhost}' &>/dev/null"
        _acheck "Nginx: hidden files blocked" \
            "grep -q '\.well-known' '${vhost}' &>/dev/null"

        # WordPress-specific
        if [[ -f "${site_root}/wp-includes/version.php" ]]; then
            _acheck "WP: xmlrpc.php blocked in Nginx" \
                "grep -q 'xmlrpc' '${vhost}' &>/dev/null"
            _acheck "WP: wp-config.php permissions (600 or 640)" \
                "[[ \"\$(stat -c %a '${site_root}/wp-config.php' 2>/dev/null)\" =~ ^(600|640)$ ]]"
            _acheck "WP: DISALLOW_FILE_EDIT set" \
                "grep -q 'DISALLOW_FILE_EDIT' '${site_root}/wp-config.php' &>/dev/null"
            _acheck "WP: readme.html removed" \
                "[[ ! -f '${site_root}/readme.html' ]]"
            _acheck "WP: debug mode off" \
                "grep -qE \"define.*WP_DEBUG.*false\" '${site_root}/wp-config.php' &>/dev/null"
        fi

        # Isolated sys user
        local sys_user
        sys_user="$(slug_from_domain "$dom" | cut -c1-16)_web"
        _acheck "PHP-FPM: isolated system user (${sys_user})" \
            "id '${sys_user}' &>/dev/null"

        echo
    fi

    # --- Summary ---
    printf '%b  Audit Summary%b\n' "$_CLR_BOLD" "$_CLR_RESET"
    printf '  %b✓ Pass: %d%b  ' "$_CLR_LGREEN"  "$_AUDIT_PASS" "$_CLR_RESET"
    printf '%b⚠ Warn: %d%b  '  "$_CLR_YELLOW"  "$_AUDIT_WARN" "$_CLR_RESET"
    printf '%b✗ Fail: %d%b\n'  "$_CLR_LRED"    "$_AUDIT_FAIL" "$_CLR_RESET"
    echo

    if (( _AUDIT_FAIL > 0 )); then
        warn "Audit found ${_AUDIT_FAIL} failure(s). Review items marked ✗ above."
    elif (( _AUDIT_WARN > 0 )); then
        info "Audit passed with ${_AUDIT_WARN} warning(s). Review items marked ⚠ above."
    else
        ok "Audit passed all checks."
    fi
}

# ---------------------------------------------------------------------------
# Check helpers
# ---------------------------------------------------------------------------
_acheck() {
    local label="$1" test_cmd="$2"
    if eval "$test_cmd" 2>/dev/null; then
        printf '    %b✓%b  %s\n' "$_CLR_LGREEN" "$_CLR_RESET" "$label"
        _AUDIT_PASS=$(( _AUDIT_PASS + 1 ))
    else
        printf '    %b✗%b  %s\n' "$_CLR_LRED" "$_CLR_RESET" "$label"
        _AUDIT_FAIL=$(( _AUDIT_FAIL + 1 ))
    fi
}

_awarn() {
    local label="$1" test_cmd="$2"
    if eval "$test_cmd" 2>/dev/null; then
        printf '    %b✓%b  %s\n' "$_CLR_LGREEN" "$_CLR_RESET" "$label"
        _AUDIT_PASS=$(( _AUDIT_PASS + 1 ))
    else
        printf '    %b⚠%b  %s\n' "$_CLR_YELLOW" "$_CLR_RESET" "$label"
        _AUDIT_WARN=$(( _AUDIT_WARN + 1 ))
    fi
}

_afail() {
    local label="$1"
    printf '    %b✗%b  %s\n' "$_CLR_LRED" "$_CLR_RESET" "$label"
    _AUDIT_FAIL=$(( _AUDIT_FAIL + 1 ))
}
