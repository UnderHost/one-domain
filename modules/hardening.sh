#!/usr/bin/env bash
# =============================================================================
#  modules/hardening.sh — Post-install security hardening (called from pipeline)
#
#  For the standalone --harden-only command, see modules/harden.sh
# =============================================================================

hardening_apply() {
    step "Applying security hardening"

    _hardening_sysctl_basic
    _hardening_nginx_server_tokens
    _hardening_php_disable_dangerous
    _hardening_logrotate

    ok "Security hardening applied"
}

# ---------------------------------------------------------------------------
hardening_fail2ban() {
    step "Configuring Fail2Ban"

    command -v fail2ban-server &>/dev/null || {
        case "$PKG_MGR" in
            apt) DEBIAN_FRONTEND=noninteractive apt-get install -y -q fail2ban &>/dev/null ;;
            dnf) dnf install -y fail2ban &>/dev/null ;;
        esac
    }

    # Only write jail.local if it doesn't already exist
    if [[ ! -f /etc/fail2ban/jail.local ]]; then
        cat > /etc/fail2ban/jail.local <<'F2B'
# UnderHost — Fail2Ban configuration

[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5
backend  = systemd
ignoreip = 127.0.0.1/8 ::1

[sshd]
enabled  = true
port     = ssh
logpath  = %(sshd_log)s

[nginx-http-auth]
enabled  = true
port     = http,https
logpath  = /var/log/nginx/error.log

[nginx-botsearch]
enabled  = true
port     = http,https
logpath  = /var/log/nginx/error.log
maxretry = 2

[nginx-badbots]
enabled  = true
port     = http,https
logpath  = /var/log/nginx/access.log
maxretry = 2
F2B
        ok "Fail2Ban jail.local written"
    else
        ok "Fail2Ban jail.local already exists — not overwritten"
    fi

    systemctl enable --now fail2ban 2>/dev/null \
        && ok "Fail2Ban enabled" \
        || warn "Could not start Fail2Ban"
}

# ---------------------------------------------------------------------------
_hardening_sysctl_basic() {
    local conf="/etc/sysctl.d/99-underhost-security.conf"
    [[ -f "$conf" ]] && return  # Already applied by harden module

    cat > "$conf" <<'SYSCTL'
# UnderHost — basic kernel hardening
net.ipv4.conf.all.rp_filter          = 1
net.ipv4.conf.default.rp_filter      = 1
net.ipv4.conf.all.accept_redirects   = 0
net.ipv4.conf.all.send_redirects     = 0
net.ipv4.tcp_syncookies              = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
kernel.dmesg_restrict                = 1
fs.suid_dumpable                     = 0
kernel.randomize_va_space            = 2
SYSCTL
    sysctl -p "$conf" &>/dev/null && ok "Kernel sysctl hardening applied" || true
}

# ---------------------------------------------------------------------------
_hardening_nginx_server_tokens() {
    local nginx_conf="/etc/nginx/nginx.conf"
    if [[ -f "$nginx_conf" ]] && ! grep -q "server_tokens off" "$nginx_conf"; then
        sed -i '/http {/a \    server_tokens off;' "$nginx_conf" 2>/dev/null \
            && ok "Nginx server_tokens off" || true
    fi
}

# ---------------------------------------------------------------------------
_hardening_php_disable_dangerous() {
    # Find php.ini locations
    local ini_dirs=()
    while IFS= read -r -d '' dir; do
        ini_dirs+=("$dir")
    done < <(find /etc/php -maxdepth 3 -name "fpm" -type d -print0 2>/dev/null)
    [[ -d /etc/php.d ]] && ini_dirs+=("/etc/php.d")

    for dir in "${ini_dirs[@]}"; do
        local conf="${dir}/underhost-security.ini"
        cat > "$conf" <<'PHPINI'
; UnderHost — PHP security settings
; Disable dangerous functions (adjust if needed)
disable_functions = exec,passthru,shell_exec,system,proc_open,popen,curl_exec,curl_multi_exec,parse_ini_file,show_source,phpinfo
expose_php = Off
display_errors = Off
log_errors = On
PHPINI
        ok "PHP security ini written: ${conf}"
    done
}

# ---------------------------------------------------------------------------
_hardening_logrotate() {
    local logrotate_file="/etc/logrotate.d/underhost-${DOMAIN//\./-}"
    # Only create if not already done by database module
    [[ -f "$logrotate_file" ]] && return

    cat > "$logrotate_file" <<LOGROTATE
/var/log/nginx/${DOMAIN}*.log
/var/log/php-fpm/${DOMAIN}*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    sharedscripts
    postrotate
        nginx -s reopen 2>/dev/null || true
    endscript
}
LOGROTATE
    ok "Log rotation configured for ${DOMAIN}"
}
