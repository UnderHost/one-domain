#!/usr/bin/env bash
# =============================================================================
#  UnderHost One-Domain — Firewall Module
#  modules/firewall.sh
# =============================================================================

[[ -n "${_UH_FIREWALL_LOADED:-}" ]] && return 0
_UH_FIREWALL_LOADED=1

firewall_configure() {
    step "Configuring firewall"
    case "$OS_FAMILY" in
        debian) _firewall_ufw  ;;
        rhel)   _firewall_firewalld ;;
        *)      warn "Unknown OS family — skipping firewall configuration" ;;
    esac
}

# ---------------------------------------------------------------------------
# UFW (Ubuntu / Debian)
# ---------------------------------------------------------------------------
_firewall_ufw() {
    if ! command -v ufw &>/dev/null; then
        apt-get -y -qq install --no-install-recommends ufw
    fi

    # Reset to defaults — but only if it hasn't been configured by us
    if ! ufw status | grep -q 'Status: active'; then
        ufw --force reset &>/dev/null || true
    fi

    # Allow necessary services
    ufw allow OpenSSH          &>/dev/null || true
    ufw allow 'Nginx Full'     &>/dev/null || true   # 80 + 443

    # FTP ports if enabled
    if [[ "${FTP_MODE:-none}" == "ftp-tls" ]]; then
        ufw allow 21/tcp        &>/dev/null || true
        ufw allow 40000:50000/tcp &>/dev/null || true
        ok "UFW: FTP ports opened (21, 40000-50000)"
    fi

    # Enable — non-interactive
    ufw --force enable &>/dev/null
    ok "UFW enabled"
    ufw status verbose 2>/dev/null | grep -E 'Status|ALLOW' | while IFS= read -r line; do
        info "  ${line}"
    done
}

# ---------------------------------------------------------------------------
# firewalld (AlmaLinux)
# ---------------------------------------------------------------------------
_firewall_firewalld() {
    if ! command -v firewall-cmd &>/dev/null; then
        dnf -q -y install firewalld
    fi

    svc_enable_start firewalld

    # Idempotent: only add if not already present
    _fwd_add() {
        local svc="$1"
        firewall-cmd --zone=public --query-service="$svc" --permanent &>/dev/null \
            || firewall-cmd --zone=public --add-service="$svc" --permanent &>/dev/null
    }

    _fwd_add ssh
    _fwd_add http
    _fwd_add https

    if [[ "${FTP_MODE:-none}" == "ftp-tls" ]]; then
        _fwd_add ftp
        firewall-cmd --zone=public --query-port=40000-50000/tcp --permanent &>/dev/null \
            || firewall-cmd --zone=public --add-port=40000-50000/tcp --permanent &>/dev/null
        ok "firewalld: FTP ports opened (21, 40000-50000)"
    fi

    firewall-cmd --reload &>/dev/null
    ok "firewalld configured"
    firewall-cmd --zone=public --list-services 2>/dev/null \
        | while IFS= read -r line; do info "  Services: ${line}"; done
}
