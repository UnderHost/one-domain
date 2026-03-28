#!/usr/bin/env bash
# =============================================================================
#  UnderHost One-Domain — Security Hardening Module
#  modules/hardening.sh
# =============================================================================
# Unified hardening module — replaces the former split between hardening.sh
# and the orphaned harden.sh. All hardening logic lives here.
#
# Exported functions:
#   hardening_apply        — full system + domain hardening (called from main)
#   hardening_fail2ban     — install and configure Fail2Ban
#   harden_apply_system    — system-level only (SSH, kernel, MariaDB)
#   harden_apply_domain    — domain-level only (Nginx rules, PHP flags)
# =============================================================================

[[ -n "${_UH_HARDENING_LOADED:-}" ]] && return 0
_UH_HARDENING_LOADED=1

# ---------------------------------------------------------------------------
# Main entry called from install main()
# ---------------------------------------------------------------------------
hardening_apply() {
    step "Applying security hardening"
    harden_apply_system
    harden_apply_domain "${DOMAIN:-}"
    hardening_auto_updates
    ok "Security hardening complete"
}

# ---------------------------------------------------------------------------
# System-level hardening (SSH, kernel, MariaDB mysql_secure)
# ---------------------------------------------------------------------------
harden_apply_system() {
    _harden_ssh
    _harden_kernel
    _harden_shared_memory
}

# ---------------------------------------------------------------------------
# Domain-level hardening (Nginx, PHP flags)
# ---------------------------------------------------------------------------
harden_apply_domain() {
    local dom="${1:-}"
    [[ -z "$dom" ]] && return 0
    _harden_nginx_domain "$dom"
    ok "Domain hardening applied: ${dom}"
}

# ---------------------------------------------------------------------------
# SSH hardening — idempotent, backs up original config
# ---------------------------------------------------------------------------
_harden_ssh() {
    local sshd_conf="/etc/ssh/sshd_config"
    [[ ! -f "$sshd_conf" ]] && { warn "sshd_config not found — skipping SSH hardening"; return; }

    # Back up original once
    [[ ! -f "${sshd_conf}.uh_orig" ]] && cp "$sshd_conf" "${sshd_conf}.uh_orig"

    # Helper: set or replace a parameter
    _sshd_set() {
        local key="$1" val="$2"
        if grep -qE "^#?${key}\s" "$sshd_conf"; then
            sed -i -E "s|^#?${key}\s.*|${key} ${val}|" "$sshd_conf"
        else
            echo "${key} ${val}" >> "$sshd_conf"
        fi
    }

    _sshd_set "PermitRootLogin"           "prohibit-password"
    _sshd_set "PasswordAuthentication"    "yes"    # keep on — admin may not have keys yet
    _sshd_set "MaxAuthTries"              "4"
    _sshd_set "ClientAliveInterval"       "300"
    _sshd_set "ClientAliveCountMax"       "2"
    _sshd_set "X11Forwarding"             "no"
    _sshd_set "AllowTcpForwarding"        "no"
    _sshd_set "PrintLastLog"              "yes"
    _sshd_set "LogLevel"                  "VERBOSE"
    _sshd_set "UsePAM"                    "yes"

    # Validate before reload
    if sshd -t 2>/dev/null; then
        systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null || true
        ok "SSH hardened"
    else
        warn "sshd config validation failed — reverting to backup"
        cp "${sshd_conf}.uh_orig" "$sshd_conf"
    fi
}

# ---------------------------------------------------------------------------
# Kernel hardening via sysctl (network security parameters)
# ---------------------------------------------------------------------------
_harden_kernel() {
    local sysctl_file="/etc/sysctl.d/99-underhost-harden.conf"

    cat > "$sysctl_file" <<'EOF'
# UnderHost One-Domain — Kernel Security Hardening
# Applied by installer — do not edit manually

# IPv4 source address validation
net.ipv4.conf.all.rp_filter        = 1
net.ipv4.conf.default.rp_filter    = 1

# Ignore ICMP broadcast requests
net.ipv4.icmp_echo_ignore_broadcasts = 1

# Ignore bogus ICMP responses
net.ipv4.icmp_ignore_bogus_error_responses = 1

# SYN flood protection
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 5

# Disable source routing
net.ipv4.conf.all.accept_source_route    = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route    = 0

# Disable ICMP redirects
net.ipv4.conf.all.accept_redirects    = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects    = 0
net.ipv4.conf.all.send_redirects      = 0

# Enable IP forwarding only if needed (disabled by default)
net.ipv4.ip_forward = 0

# Log martian packets
net.ipv4.conf.all.log_martians    = 1
net.ipv4.conf.default.log_martians = 1

# Prevent time-wait assassination attacks
net.ipv4.tcp_rfc1337 = 1

# Disable IPv6 if not needed (comment out to keep IPv6)
# net.ipv6.conf.all.disable_ipv6 = 1

# Core dump restriction
fs.suid_dumpable = 0

# Restrict dmesg to root
kernel.dmesg_restrict = 1

# Restrict kernel pointers
kernel.kptr_restrict = 2

# Disable magic SysRq key
kernel.sysrq = 0
EOF

    sysctl -p "$sysctl_file" &>/dev/null || {
        # Some parameters may not exist on all kernels — apply what we can
        while IFS='=' read -r key val; do
            [[ "$key" =~ ^# || -z "${key// }" ]] && continue
            key="${key// /}"
            val="${val// /}"
            sysctl -w "${key}=${val}" &>/dev/null || true
        done < "$sysctl_file"
    }
    ok "Kernel security parameters applied"
}

# ---------------------------------------------------------------------------
# Lock /dev/shm (tmpfs shared memory — often used in privilege escalation)
# ---------------------------------------------------------------------------
_harden_shared_memory() {
    if ! grep -q '/dev/shm' /etc/fstab; then
        echo 'tmpfs /dev/shm tmpfs defaults,noexec,nosuid,nodev 0 0' >> /etc/fstab
        mount -o remount,noexec,nosuid,nodev /dev/shm 2>/dev/null \
            && ok "Hardened /dev/shm (noexec,nosuid,nodev)" \
            || warn "Could not remount /dev/shm — will apply on next reboot"
    fi
}

# ---------------------------------------------------------------------------
# Nginx domain hardening — adds security-specific location blocks
# ---------------------------------------------------------------------------
_harden_nginx_domain() {
    local dom="$1"
    local conf_dir
    conf_dir="$(os_nginx_conf_dir)"
    local vhost="${conf_dir}/${dom}.conf"

    [[ ! -f "$vhost" ]] && { warn "Nginx vhost not found for ${dom} — skipping Nginx hardening"; return; }

    # Only add hardening block once
    if grep -q 'UH-HARDENING' "$vhost"; then
        ok "Nginx hardening already applied for ${dom}"
        return
    fi

    # Append a hardening location block inside the server block
    # Uses sed to insert before the closing } of the first server block
    local hardening_block
    hardening_block=$(cat <<'EOF'

    # === UH-HARDENING ===
    # Block common exploit scanners
    if ($http_user_agent ~* (masscan|nikto|sqlmap|nmap|dirbuster|hydra|zgrab)) {
        return 444;
    }

    # Block requests with no host header
    if ($host = "") {
        return 444;
    }

    # Disable PHP execution in uploads (belt-and-suspenders)
    location ~* /(?:uploads|files|wp-content/uploads)/.*\.php$ {
        deny all;
        access_log off;
        log_not_found off;
    }

    # Block common vulnerability paths
    location ~* /(eval-stdin|phpinfo|php-info|info\.php|test\.php|shell\.php)$ {
        deny all;
        access_log off;
        log_not_found off;
    }
    # === /UH-HARDENING ===
EOF
)

    # Insert before last closing brace in the first server{} block
    # This is a best-effort sed approach; Nginx validate will catch errors.
    python3 - "$vhost" "$hardening_block" <<'PYEOF' 2>/dev/null || true
import sys, re
path = sys.argv[1]
block = sys.argv[2]
with open(path) as f:
    content = f.read()
# Insert before the last } in the first server block
idx = content.rfind('}')
if idx != -1:
    content = content[:idx] + block + '\n' + content[idx:]
with open(path, 'w') as f:
    f.write(content)
PYEOF

    # Always validate after modification
    if nginx -t 2>/dev/null; then
        ok "Nginx hardening block added: ${dom}"
    else
        warn "Nginx test failed after hardening block — check ${vhost}"
        nginx -t 2>&1 | while IFS= read -r line; do warn "  $line"; done
    fi
}

# ---------------------------------------------------------------------------
# Fail2Ban — install jails for SSH and Nginx
# ---------------------------------------------------------------------------
hardening_fail2ban() {
    step "Configuring Fail2Ban"

    # Install if not present (packages.sh installs it, but be defensive)
    if ! command -v fail2ban-client &>/dev/null; then
        case "$OS_PKG_MGR" in
            apt) apt-get -y -qq install --no-install-recommends fail2ban ;;
            dnf) dnf -q -y install fail2ban ;;
        esac
    fi

    # Write jail.local — never touch jail.conf (gets overwritten on updates)
    cat > /etc/fail2ban/jail.local <<EOF
# UnderHost One-Domain — Fail2Ban configuration
# Generated: $(date '+%Y-%m-%d')
# Edit this file; never edit jail.conf

[DEFAULT]
bantime      = 3600
findtime     = 600
maxretry     = 5
banaction    = iptables-multiport
backend      = systemd
ignoreip     = 127.0.0.1/8 ::1

[sshd]
enabled  = true
port     = ssh
filter   = sshd
maxretry = 4
bantime  = 7200

[nginx-http-auth]
enabled  = true
port     = http,https
filter   = nginx-http-auth
logpath  = /var/log/nginx/*.error.log

[nginx-botsearch]
enabled  = true
port     = http,https
filter   = nginx-botsearch
logpath  = /var/log/nginx/*.access.log
maxretry = 2

[nginx-limit-req]
enabled  = true
port     = http,https
filter   = nginx-limit-req
logpath  = /var/log/nginx/*.error.log
maxretry = 10
EOF

    # Nginx Fail2Ban filters — write if not present
    if [[ ! -f /etc/fail2ban/filter.d/nginx-botsearch.conf ]]; then
        cat > /etc/fail2ban/filter.d/nginx-botsearch.conf <<'EOF'
[Definition]
failregex = ^<HOST> -.*"(GET|POST|HEAD).*(?:\.php|\.asp|\.env|wp-login|xmlrpc)
ignoreregex =
EOF
    fi

    if [[ ! -f /etc/fail2ban/filter.d/nginx-limit-req.conf ]]; then
        cat > /etc/fail2ban/filter.d/nginx-limit-req.conf <<'EOF'
[Definition]
failregex = limiting requests, excess:.* by zone.*client: <HOST>
ignoreregex =
EOF
    fi

    svc_enable_start fail2ban
    ok "Fail2Ban configured with SSH + Nginx jails"
}

# ---------------------------------------------------------------------------
# Auto OS security updates — called from hardening_apply() in v4
# ---------------------------------------------------------------------------
hardening_auto_updates() {
    step "Configuring automatic OS security updates"
    case "$OS_PKG_MGR" in
        apt)  _harden_unattended_upgrades ;;
        dnf)  _harden_dnf_automatic       ;;
    esac
}

_harden_unattended_upgrades() {
    apt-get -y -qq install --no-install-recommends unattended-upgrades apt-listchanges

    cat > /etc/apt/apt.conf.d/50unattended-upgrades-underhost <<'EOF'
// UnderHost — Automatic security updates
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Mail "root";
EOF

    cat > /etc/apt/apt.conf.d/20auto-upgrades-underhost <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

    systemctl enable --now unattended-upgrades 2>/dev/null || true
    ok "unattended-upgrades configured (security only, no auto-reboot)"
}

_harden_dnf_automatic() {
    dnf -q -y install dnf-automatic

    local conf="/etc/dnf/automatic.conf"
    [[ -f "$conf" ]] && sed -i \
        -e 's/^apply_updates = .*/apply_updates = yes/' \
        -e 's/^upgrade_type = .*/upgrade_type = security/' \
        "$conf"

    systemctl enable --now dnf-automatic.timer 2>/dev/null || true
    ok "dnf-automatic configured (security updates only)"
}

# ---------------------------------------------------------------------------
# SSH key install helper — called from wizard in v4
# ---------------------------------------------------------------------------
hardening_install_ssh_key() {
    local pub_key="${1:-}"
    [[ -z "$pub_key" ]] && die "No SSH public key provided"

    # Validate it looks like an SSH public key
    if ! echo "$pub_key" | grep -qE '^(ssh-rsa|ssh-ed25519|ecdsa-sha2|sk-ssh)'; then
        die "Does not look like a valid SSH public key: ${pub_key:0:40}..."
    fi

    local auth_keys="/root/.ssh/authorized_keys"
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh

    # Add only if not already present
    if grep -qF "$pub_key" "$auth_keys" 2>/dev/null; then
        ok "SSH key already in authorized_keys — skipping"
        return
    fi

    echo "$pub_key" >> "$auth_keys"
    chmod 600 "$auth_keys"
    ok "SSH public key added to ${auth_keys}"

    # Offer to disable password auth now that a key exists
    if prompt_yn "Disable SSH password authentication now? (key-only login)" "n"; then
        _sshd_set "PasswordAuthentication" "no"
        if sshd -t 2>/dev/null; then
            systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null || true
            ok "SSH password authentication disabled"
            warn "Ensure your key works BEFORE closing this session."
        else
            warn "sshd config invalid — reverting PasswordAuthentication change"
            _sshd_set "PasswordAuthentication" "yes"
        fi
    fi
}
