#!/usr/bin/env bash
# =============================================================================
#  modules/firewall.sh — Firewall configuration (UFW or firewalld)
# =============================================================================

firewall_configure() {
    step "Configuring firewall"

    if command -v ufw &>/dev/null; then
        _firewall_ufw
    elif command -v firewall-cmd &>/dev/null; then
        _firewall_firewalld
    else
        warn "No supported firewall found (ufw or firewalld) — skipping"
        warn "Install manually: apt install ufw  or  dnf install firewalld"
        return
    fi
}

# ---------------------------------------------------------------------------
_firewall_ufw() {
    # Reset to defaults without disabling SSH (safe)
    ufw --force reset &>/dev/null

    # Default policies
    ufw default deny incoming &>/dev/null
    ufw default allow outgoing &>/dev/null

    # Allow essential services
    ufw allow ssh    &>/dev/null   # port 22
    ufw allow 80/tcp &>/dev/null   # HTTP
    ufw allow 443/tcp &>/dev/null  # HTTPS

    # FTP (only if explicitly enabled)
    if [[ "${FTP_MODE:-none}" == "ftp-tls" ]]; then
        ufw allow 20/tcp &>/dev/null
        ufw allow 21/tcp &>/dev/null
        ufw allow 40000:50000/tcp &>/dev/null
        ok "UFW: FTP-TLS ports opened (20,21,40000-50000)"
    fi

    # Enable — non-interactive so it won't hang on SSH warning
    ufw --force enable &>/dev/null
    ok "UFW firewall enabled"
    ufw status verbose 2>/dev/null | grep -E "Status|To " | head -10 || true
}

# ---------------------------------------------------------------------------
_firewall_firewalld() {
    systemctl enable --now firewalld &>/dev/null || {
        warn "Could not start firewalld"; return
    }

    firewall-cmd --permanent --add-service=ssh   &>/dev/null
    firewall-cmd --permanent --add-service=http  &>/dev/null
    firewall-cmd --permanent --add-service=https &>/dev/null

    if [[ "${FTP_MODE:-none}" == "ftp-tls" ]]; then
        firewall-cmd --permanent --add-service=ftp &>/dev/null
        firewall-cmd --permanent --add-port=40000-50000/tcp &>/dev/null
        ok "firewalld: FTP ports opened"
    fi

    firewall-cmd --reload &>/dev/null
    ok "firewalld configured and reloaded"
}
