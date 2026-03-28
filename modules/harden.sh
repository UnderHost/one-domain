#!/usr/bin/env bash
# =============================================================================
#  modules/harden.sh — Security hardening (system-wide or domain-specific)
#
#  Usage:  install harden
#          install harden domain.com
#          install --harden-only
# =============================================================================

harden_apply_system() {
    section_banner "UnderHost: System Hardening"

    os_detect
    os_validate_support

    step "Applying system-level security hardening"

    _harden_sysctl
    _harden_ssh
    _harden_fail2ban_global
    _harden_nginx_global
    _harden_auto_updates

    ok "System hardening complete"
}

harden_apply_domain() {
    local domain="${1:-$DOMAIN}"
    [[ -z "$domain" ]] && die "Usage: install harden domain.com"
    _validate_domain "$domain"

    local site_root="/var/www/${domain}"
    [[ -d "$site_root" ]] || die "Document root not found: ${site_root}"

    section_banner "UnderHost: Domain Hardening — ${domain}"
    step "Applying domain-level security hardening"

    _harden_nginx_vhost "$domain"

    if [[ -f "${site_root}/wp-config.php" ]]; then
        _harden_wordpress "$site_root" "$domain"
    fi

    _harden_permissions "$site_root" "$domain"

    ok "Domain hardening complete for ${domain}"
}

# ---------------------------------------------------------------------------
_harden_sysctl() {
    step "Applying kernel sysctl hardening"

    local sysctl_file="/etc/sysctl.d/99-underhost-security.conf"
    cat > "$sysctl_file" <<'SYSCTL'
# UnderHost — security-focused kernel parameters
# Reference: CIS Benchmark / Mozilla Linux hardening guide

# Prevent IP spoofing
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Disable ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Disable source routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0

# Protect against SYN flood
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_max_syn_backlog = 2048

# Enable packet martian logging
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# Disable ping broadcast
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Disable IPv6 if not needed (comment out if you use IPv6)
# net.ipv6.conf.all.disable_ipv6 = 1

# Restrict dmesg to root
kernel.dmesg_restrict = 1

# Restrict ptrace to owned processes
kernel.yama.ptrace_scope = 1

# Prevent suid core dumps
fs.suid_dumpable = 0

# Address space layout randomization
kernel.randomize_va_space = 2
SYSCTL

    sysctl -p "$sysctl_file" &>/dev/null && ok "Kernel sysctl hardening applied" \
        || warn "sysctl apply had warnings — review ${sysctl_file}"
}

# ---------------------------------------------------------------------------
_harden_ssh() {
    step "Hardening SSH configuration"

    local sshd_config="/etc/ssh/sshd_config"
    [[ -f "$sshd_config" ]] || { warn "sshd_config not found — skipping SSH hardening"; return; }

    # Backup
    cp "$sshd_config" "${sshd_config}.bak.$(date +%s)" 2>/dev/null || true

    # Drop-in hardening (doesn't clobber main config)
    local drop_in="/etc/ssh/sshd_config.d/99-underhost.conf"
    mkdir -p "$(dirname "$drop_in")"
    cat > "$drop_in" <<'SSHHARD'
# UnderHost SSH hardening — applied by installer
Protocol 2
PermitRootLogin prohibit-password
PasswordAuthentication yes
PermitEmptyPasswords no
X11Forwarding no
MaxAuthTries 4
ClientAliveInterval 300
ClientAliveCountMax 2
AllowTcpForwarding no
LoginGraceTime 30
UsePAM yes
SSHHARD

    # Validate before restarting
    if sshd -t 2>/dev/null; then
        systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null || true
        ok "SSH hardening applied (drop-in: ${drop_in})"
    else
        rm -f "$drop_in"
        warn "SSH config validation failed — drop-in removed, original preserved"
    fi
}

# ---------------------------------------------------------------------------
_harden_fail2ban_global() {
    command -v fail2ban-server &>/dev/null || {
        step "Installing Fail2Ban"
        pkg_install fail2ban 2>/dev/null || { warn "Could not install Fail2Ban"; return; }
    }

    step "Configuring Fail2Ban jails"

    cat > /etc/fail2ban/jail.local <<'F2B'
# UnderHost — Fail2Ban global jail configuration

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

[nginx-noscript]
enabled  = true
port     = http,https
logpath  = /var/log/nginx/access.log

[nginx-badbots]
enabled  = true
port     = http,https
logpath  = /var/log/nginx/access.log
maxretry = 2
F2B

    systemctl enable --now fail2ban 2>/dev/null && ok "Fail2Ban enabled and configured" \
        || warn "Could not start Fail2Ban"
}

# ---------------------------------------------------------------------------
_harden_nginx_global() {
    step "Applying global Nginx security headers"

    local snippets_dir="/etc/nginx/snippets"
    mkdir -p "$snippets_dir"

    cat > "${snippets_dir}/underhost-security-headers.conf" <<'HDRS'
# UnderHost — Global security headers snippet
# Include in your server blocks: include snippets/underhost-security-headers.conf;
add_header X-Frame-Options          "SAMEORIGIN"                              always;
add_header X-Content-Type-Options   "nosniff"                                 always;
add_header X-XSS-Protection         "1; mode=block"                           always;
add_header Referrer-Policy          "strict-origin-when-cross-origin"         always;
add_header Permissions-Policy       "geolocation=(), microphone=(), camera=()" always;
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;

# Hide Nginx version
server_tokens off;
HDRS

    ok "Global Nginx security snippet saved: ${snippets_dir}/underhost-security-headers.conf"

    # Add server_tokens off to nginx.conf if not already there
    if ! grep -q "server_tokens off" /etc/nginx/nginx.conf 2>/dev/null; then
        sed -i '/http {/a \    server_tokens off;' /etc/nginx/nginx.conf 2>/dev/null || true
    fi

    nginx -t 2>/dev/null && systemctl reload nginx && ok "Nginx reloaded" || true
}

# ---------------------------------------------------------------------------
_harden_nginx_vhost() {
    local domain="$1"
    local vhost="/etc/nginx/conf.d/${domain}.conf"

    [[ -f "$vhost" ]] || { warn "Nginx vhost not found: ${vhost}"; return; }

    step "Hardening Nginx vhost: ${domain}"

    # Ensure sensitive file blocks are present
    local changed=false
    if ! grep -q "\.env" "$vhost" 2>/dev/null; then
        cat >> "$vhost" <<VHOSTBLOCK

    # Block sensitive files (added by harden)
    location ~* \.(env|log|ini|sql|bak|conf|htpasswd|git)$ {
        deny all;
        access_log off;
        log_not_found off;
    }
VHOSTBLOCK
        changed=true
    fi

    $changed && ok "Nginx vhost hardening additions applied" || ok "Nginx vhost already hardened"

    nginx -t 2>/dev/null && systemctl reload nginx || warn "Nginx reload failed — check config"
}

# ---------------------------------------------------------------------------
_harden_wordpress() {
    local site_root="$1"
    local domain="$2"

    step "Hardening WordPress: ${domain}"

    command -v wp &>/dev/null || { warn "WP-CLI not found — skipping WP hardening"; return; }

    local _wp_cmd="wp --path=${site_root} --allow-root"

    # Disable file editor
    $HOME=/root $(_wp_cmd) config set DISALLOW_FILE_EDIT true --raw 2>/dev/null && ok "DISALLOW_FILE_EDIT=true" || true

    # Disable file mods in production
    $HOME=/root $(_wp_cmd) config set DISALLOW_FILE_MODS true --raw 2>/dev/null || true

    # Force HTTPS admin
    $HOME=/root $(_wp_cmd) config set FORCE_SSL_ADMIN true --raw 2>/dev/null && ok "FORCE_SSL_ADMIN=true" || true

    # Disable xmlrpc
    $HOME=/root $(_wp_cmd) option update disable_xmlrpc 1 2>/dev/null || true

    # Remove readme/license
    for f in readme.html license.txt wp-config-sample.php; do
        rm -f "${site_root}/${f}" 2>/dev/null && ok "Removed: ${f}" || true
    done

    ok "WordPress hardening applied"
}

# ---------------------------------------------------------------------------
_harden_permissions() {
    local site_root="$1"
    local domain="$2"
    local site_user="${domain//./_}"
    site_user="${site_user:0:32}"
    local web_user
    web_user="$(os_web_user 2>/dev/null || echo www-data)"

    step "Locking down file permissions for ${domain}"
    chown -R "${site_user}:${web_user}" "$site_root"
    find "$site_root" -type d -exec chmod 755 {} \;
    find "$site_root" -type f -exec chmod 644 {} \;
    [[ -f "${site_root}/wp-config.php" ]] && chmod 640 "${site_root}/wp-config.php"
    local uploads="${site_root}/wp-content/uploads"
    [[ -d "$uploads" ]] && { chown -R "${web_user}:${web_user}" "$uploads"; chmod -R 755 "$uploads"; }
    ok "Permissions secured for ${site_root}"
}

# ---------------------------------------------------------------------------
_harden_auto_updates() {
    step "Enabling automatic security updates"
    case "${OS_ID:-}" in
        ubuntu|debian)
            command -v unattended-upgrade &>/dev/null || apt-get install -y unattended-upgrades &>/dev/null
            cat > /etc/apt/apt.conf.d/99-underhost-autoupdate <<'APT'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
APT
            ok "APT unattended-upgrades enabled"
            ;;
        almalinux|rhel|centos)
            command -v dnf-automatic &>/dev/null \
                || dnf install -y dnf-automatic &>/dev/null || true
            systemctl enable --now dnf-automatic.timer 2>/dev/null \
                && ok "dnf-automatic timer enabled" || warn "Could not enable dnf-automatic"
            ;;
        *) warn "Auto-updates: unsupported OS ${OS_ID:-}" ;;
    esac
}
