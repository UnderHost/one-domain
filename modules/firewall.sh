#!/usr/bin/env bash
# =============================================================================
#  modules/firewall.sh — UFW / firewalld configuration
# =============================================================================

firewall_configure() {
    step "Configuring firewall"

    if command -v ufw &>/dev/null; then
        _fw_ufw
    elif command -v firewall-cmd &>/dev/null; then
        _fw_firewalld
    else
        warn "No supported firewall manager found (ufw / firewalld). Skipping."
        return
    fi
}

# ---------------------------------------------------------------------------
_fw_ufw() {
    ufw --force reset &>/dev/null

    # Essential services
    ufw allow 22/tcp    comment 'SSH'
    ufw allow 80/tcp    comment 'HTTP'
    ufw allow 443/tcp   comment 'HTTPS'

    # FTP passive range if needed
    if [[ "$FTP_MODE" == "ftp-tls" ]]; then
        ufw allow 21/tcp          comment 'FTP control'
        ufw allow 990/tcp         comment 'FTPS'
        ufw allow 40000:50000/tcp comment 'FTP passive'
    fi

    # Redis: only localhost, not public
    # (Redis binds 127.0.0.1 by default — no ufw rule needed)

    ufw default deny incoming
    ufw default allow outgoing
    echo "y" | ufw enable &>/dev/null

    ok "UFW firewall enabled"
    ufw status verbose
}

# ---------------------------------------------------------------------------
_fw_firewalld() {
    systemctl enable firewalld --now 2>/dev/null

    firewall-cmd --permanent --add-service=http   &>/dev/null
    firewall-cmd --permanent --add-service=https  &>/dev/null
    firewall-cmd --permanent --add-service=ssh    &>/dev/null

    if [[ "$FTP_MODE" == "ftp-tls" ]]; then
        firewall-cmd --permanent --add-service=ftp    &>/dev/null
        firewall-cmd --permanent --add-port=40000-50000/tcp &>/dev/null
    fi

    firewall-cmd --reload &>/dev/null
    ok "firewalld configured"
}
