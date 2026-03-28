#!/usr/bin/env bash
# =============================================================================
#  UnderHost One-Domain — FTP / SFTP Module
#  modules/ftp.sh
# =============================================================================

[[ -n "${_UH_FTP_LOADED:-}" ]] && return 0
_UH_FTP_LOADED=1

ftp_configure() {
    step "Configuring file access (mode: ${FTP_MODE})"
    case "${FTP_MODE:-none}" in
        ftp-tls)   _ftp_configure_vsftpd ;;
        sftp)      _ftp_configure_sftp   ;;
        none)      return 0 ;;
        *)         warn "Unknown FTP_MODE: ${FTP_MODE} — skipping" ;;
    esac
}

# ---------------------------------------------------------------------------
# vsftpd FTP with TLS (FTPS)
# ---------------------------------------------------------------------------
_ftp_configure_vsftpd() {
    pkg_install_vsftpd

    local sys_user="${FTP_USER}"
    local sys_pass="${FTP_PASS}"
    local site_root="${SITE_ROOT}/public"

    # Create dedicated FTP user if not exists
    if ! id "$sys_user" &>/dev/null; then
        useradd -s /usr/sbin/nologin -d "$site_root" "$sys_user" 2>/dev/null \
            || useradd -s /sbin/nologin -d "$site_root" "$sys_user"
        echo "${sys_user}:${sys_pass}" | chpasswd
        ok "FTP user created: ${sys_user}"
    fi

    # Use Let's Encrypt certs for FTP TLS
    local ssl_cert="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
    local ssl_key="/etc/letsencrypt/live/${DOMAIN}/privkey.pem"
    local use_ssl=NO
    if [[ -f "$ssl_cert" && -f "$ssl_key" ]]; then
        use_ssl=YES
        ok "FTP TLS: using Let's Encrypt cert for ${DOMAIN}"
    else
        warn "SSL cert not found — FTP TLS will be disabled (provision SSL first)"
    fi

    # Write vsftpd.conf
    cat > /etc/vsftpd.conf <<EOF
# UnderHost vsftpd configuration — generated $(date '+%Y-%m-%d')
listen=YES
listen_ipv6=NO
anonymous_enable=NO
local_enable=YES
write_enable=YES
local_umask=022
dirmessage_enable=YES
use_localtime=YES
xferlog_enable=YES
connect_from_port_20=YES
xferlog_file=/var/log/vsftpd.log
xferlog_std_format=YES
idle_session_timeout=600
data_connection_timeout=120
ftpd_banner=FTP Server Ready.
chroot_local_user=YES
allow_writeable_chroot=NO
secure_chroot_dir=/var/run/vsftpd/empty
pam_service_name=vsftpd
chroot_list_enable=NO
user_sub_token=\$USER
local_root=${site_root}

# Passive mode port range — match firewall rules
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=50000

# TLS/SSL
ssl_enable=${use_ssl}
$(if [[ "$use_ssl" == YES ]]; then
cat <<SSLEOF
force_local_data_ssl=YES
force_local_logins_ssl=YES
ssl_tlsv1=NO
ssl_sslv2=NO
ssl_sslv3=NO
require_ssl_reuse=NO
ssl_ciphers=ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-GCM-SHA256
rsa_cert_file=${ssl_cert}
rsa_private_key_file=${ssl_key}
SSLEOF
fi)
EOF

    # Ensure secure chroot dir exists
    mkdir -p /var/run/vsftpd/empty

    svc_enable_start vsftpd
    ok "vsftpd configured: user=${sys_user}"
    warn "⚠  FTP is active. Use SFTP (--with-sftp-only) in production unless FTP is required."
}

# ---------------------------------------------------------------------------
# SFTP via SSH (chrooted, no vsftpd needed)
# ---------------------------------------------------------------------------
_ftp_configure_sftp() {
    local sftp_user="${FTP_USER}"
    local sftp_pass="${FTP_PASS}"
    local site_root="${SITE_ROOT}"

    # Create user if not exists
    if ! id "$sftp_user" &>/dev/null; then
        useradd -s /usr/sbin/nologin -d "$site_root" "$sftp_user" 2>/dev/null \
            || useradd -s /sbin/nologin -d "$site_root" "$sftp_user"
        echo "${sftp_user}:${sftp_pass}" | chpasswd
        ok "SFTP user created: ${sftp_user}"
    fi

    # Chroot requires root:root ownership of the chroot dir
    chown root:root "$site_root"
    chmod 755 "$site_root"

    # Give the user a writable subdirectory
    local sftp_upload="${site_root}/public"
    mkdir -p "$sftp_upload"
    local sys_user
    sys_user="$(slug_from_domain "$DOMAIN" | cut -c1-16)_web"
    chown "${sys_user}:${sys_user}" "$sftp_upload"

    # Add SFTP chroot block to sshd_config
    local sshd_conf="/etc/ssh/sshd_config"
    local marker="# UH-SFTP-${DOMAIN}"

    if ! grep -q "$marker" "$sshd_conf"; then
        cat >> "$sshd_conf" <<EOF

${marker}
Match User ${sftp_user}
    ChrootDirectory ${site_root}
    ForceCommand internal-sftp
    AllowTcpForwarding no
    X11Forwarding no
    PasswordAuthentication yes
EOF

        if sshd -t 2>/dev/null; then
            systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null || true
            ok "SFTP chroot configured for user: ${sftp_user}"
        else
            warn "sshd config invalid after SFTP block — reverting"
            sed -i "/${marker}/,/PasswordAuthentication yes/d" "$sshd_conf"
        fi
    else
        ok "SFTP chroot block already present for ${DOMAIN}"
    fi
}
