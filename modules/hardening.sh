#!/usr/bin/env bash
# =============================================================================
#  modules/hardening.sh — System security hardening
# =============================================================================

hardening_apply() {
    step "Applying system hardening"
    _hardening_ssh
    _hardening_kernel
    _hardening_logrotate
    ok "Hardening applied"
}

# ---------------------------------------------------------------------------
hardening_fail2ban() {
    step "Configuring Fail2Ban"

    cat > /etc/fail2ban/jail.local <<F2B
# UnderHost Fail2Ban configuration — $(date)

[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 5
banaction = iptables-multiport
destemail = ${ADMIN_EMAIL}
sender    = fail2ban@${DOMAIN}
mta       = sendmail
action    = %(action_)s

[sshd]
enabled  = true
port     = ssh
filter   = sshd
logpath  = %(sshd_log)s
maxretry = 3

[nginx-http-auth]
enabled  = true
filter   = nginx-http-auth
port     = http,https
logpath  = /var/log/nginx/*.error.log

[nginx-limit-req]
enabled  = true
filter   = nginx-limit-req
port     = http,https
logpath  = /var/log/nginx/*.error.log
maxretry = 10

[nginx-botsearch]
enabled  = true
filter   = nginx-botsearch
port     = http,https
logpath  = /var/log/nginx/*.access.log
maxretry = 2
F2B

    systemctl enable fail2ban --now 2>/dev/null
    ok "Fail2Ban configured"
}

# ---------------------------------------------------------------------------
_hardening_ssh() {
    local sshd_cfg="/etc/ssh/sshd_config"
    [[ -f "$sshd_cfg" ]] || return

    # Only modify defaults that are insecure; don't change port
    local changes=(
        "s/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/"
        "s/^#*PasswordAuthentication yes/PasswordAuthentication yes/"
        "s/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/"
        "s/^#*X11Forwarding yes/X11Forwarding no/"
        "s/^#*MaxAuthTries.*/MaxAuthTries 4/"
        "s/^#*ClientAliveInterval.*/ClientAliveInterval 300/"
        "s/^#*ClientAliveCountMax.*/ClientAliveCountMax 2/"
    )

    for change in "${changes[@]}"; do
        sed -i "$change" "$sshd_cfg"
    done

    systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null || true
    ok "SSH hardened (root login restricted, timeouts set)"
}

# ---------------------------------------------------------------------------
_hardening_kernel() {
    # Write a sysctl hardening file
    cat > /etc/sysctl.d/99-underhost.conf <<SYSCTL
# UnderHost kernel hardening
net.ipv4.tcp_syncookies          = 1
net.ipv4.conf.all.rp_filter      = 1
net.ipv4.conf.default.rp_filter  = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects   = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_redirects  = 0
kernel.randomize_va_space = 2
fs.protected_hardlinks = 1
fs.protected_symlinks  = 1
SYSCTL
    sysctl -p /etc/sysctl.d/99-underhost.conf &>/dev/null
    ok "Kernel hardening applied"
}

# ---------------------------------------------------------------------------
_hardening_logrotate() {
    cat > /etc/logrotate.d/underhost-${DOMAIN//\./-} <<LOGROTATE
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
        [ -f /var/run/nginx.pid ] && kill -USR1 \$(cat /var/run/nginx.pid) 2>/dev/null || true
    endscript
}
LOGROTATE
    ok "Log rotation configured for ${DOMAIN}"
}
