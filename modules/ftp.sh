#!/usr/bin/env bash
# =============================================================================
#  modules/ftp.sh — SFTP-only and FTP-TLS user configuration
# =============================================================================

ftp_configure() {
    step "Configuring file access: ${FTP_MODE}"

    case "$FTP_MODE" in
        sftp)     _ftp_sftp_only ;;
        ftp-tls)  _ftp_vsftpd_tls ;;
        none)     info "File access: none — skipped" ;;
        *)        warn "Unknown FTP mode: ${FTP_MODE}" ;;
    esac
}

# ---------------------------------------------------------------------------
_ftp_sftp_only() {
    local site_user="${DOMAIN//./_}"
    site_user="${site_user:0:32}"
    local sftp_user="${site_user}_sftp"
    local sftp_pass
    sftp_pass="$(gen_pass 20)"

    info "Creating SFTP user: ${sftp_user}"

    useradd -m -s /usr/sbin/nologin \
        -d "${SITE_ROOT}" \
        -c "SFTP user for ${DOMAIN}" \
        "$sftp_user" 2>/dev/null \
        || usermod -d "${SITE_ROOT}" "$sftp_user" 2>/dev/null || true

    echo "${sftp_user}:${sftp_pass}" | chpasswd

    # Chroot the SFTP user to the site root
    _ftp_add_sftp_chroot "$sftp_user"

    # Export for summary
    FTP_USER="$sftp_user"
    FTP_PASS="$sftp_pass"

    ok "SFTP user created: ${sftp_user}"
    info "  Connect: sftp ${sftp_user}@${DOMAIN}"
}

# ---------------------------------------------------------------------------
_ftp_add_sftp_chroot() {
    local sftp_user="$1"
    local sshd_config="/etc/ssh/sshd_config"

    # Check if Match block already exists
    if grep -q "Match User ${sftp_user}" "$sshd_config" 2>/dev/null; then
        ok "SSH SFTP chroot already configured for ${sftp_user}"
        return
    fi

    # Ensure ChrootDirectory parent is owned by root (SSH requirement)
    chown root:root "${SITE_ROOT}" 2>/dev/null || true
    chmod 755 "${SITE_ROOT}" 2>/dev/null || true

    # Append Match block
    cat >> "$sshd_config" <<SSHBLOCK

# UnderHost: SFTP chroot for ${sftp_user}
Match User ${sftp_user}
    ChrootDirectory ${SITE_ROOT}
    ForceCommand internal-sftp
    AllowTcpForwarding no
    X11Forwarding no
SSHBLOCK

    # Validate and reload
    if sshd -t 2>/dev/null; then
        systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null || true
        ok "SSH reloaded with SFTP chroot for ${sftp_user}"
    else
        warn "SSH config validation failed — check /etc/ssh/sshd_config"
    fi
}

# ---------------------------------------------------------------------------
_ftp_vsftpd_tls() {
    info "Installing vsftpd for FTP-TLS"

    case "$PKG_MGR" in
        apt) DEBIAN_FRONTEND=noninteractive apt-get install -y -q vsftpd &>/dev/null ;;
        dnf) dnf install -y vsftpd &>/dev/null ;;
    esac

    local site_user="${DOMAIN//./_}"
    site_user="${site_user:0:32}"
    local ftp_user="${site_user}_ftp"
    local ftp_pass
    ftp_pass="$(gen_pass 20)"

    useradd -m -s /usr/sbin/nologin \
        -d "${SITE_ROOT}" \
        -c "FTP user for ${DOMAIN}" \
        "$ftp_user" 2>/dev/null || true
    echo "${ftp_user}:${ftp_pass}" | chpasswd

    # Generate self-signed cert for vsftpd (Certbot cert will be better if available)
    local ssl_cert_path="/etc/ssl/certs/vsftpd.pem"
    local ssl_key_path="/etc/ssl/private/vsftpd.key"
    if [[ -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]]; then
        ssl_cert_path="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
        ssl_key_path="/etc/letsencrypt/live/${DOMAIN}/privkey.pem"
        info "Using Let's Encrypt certificate for FTP-TLS"
    else
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "$ssl_key_path" \
            -out "$ssl_cert_path" \
            -subj "/CN=${DOMAIN}" &>/dev/null
        info "Self-signed certificate generated for FTP-TLS"
    fi

    cat > /etc/vsftpd.conf <<VSFTPD
# UnderHost vsftpd config — FTP with TLS
listen=YES
listen_ipv6=NO
anonymous_enable=NO
local_enable=YES
write_enable=YES
local_umask=022
chroot_local_user=YES
allow_writeable_chroot=YES
pam_service_name=vsftpd
userlist_enable=YES
userlist_file=/etc/vsftpd.userlist
userlist_deny=NO
# TLS
ssl_enable=YES
allow_anon_ssl=NO
force_local_data_ssl=YES
force_local_logins_ssl=YES
ssl_tlsv1=YES
ssl_sslv2=NO
ssl_sslv3=NO
rsa_cert_file=${ssl_cert_path}
rsa_private_key_file=${ssl_key_path}
# Passive mode
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=50000
# Logging
xferlog_enable=YES
xferlog_file=/var/log/vsftpd.log
VSFTPD

    echo "$ftp_user" > /etc/vsftpd.userlist

    systemctl enable --now vsftpd 2>/dev/null \
        && ok "vsftpd (FTP-TLS) enabled" \
        || warn "Could not start vsftpd"

    FTP_USER="$ftp_user"
    FTP_PASS="$ftp_pass"

    ok "FTP-TLS user created: ${ftp_user}"
    info "  FTP host: ${DOMAIN}:21 (Explicit TLS required)"
}
