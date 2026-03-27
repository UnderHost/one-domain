#!/usr/bin/env bash
# =============================================================================
#  modules/ftp.sh — FTP/SFTP access configuration
# =============================================================================

ftp_configure() {
    case "$FTP_MODE" in
        sftp)      _ftp_sftp_only ;;
        ftp-tls)   _ftp_vsftpd_tls ;;
        ftp-legacy)
            security_warning \
                "Legacy FTP (unencrypted) is being configured." \
                "Credentials will be sent in plaintext over the network." \
                "This is strongly discouraged in production environments."
            _ftp_vsftpd_legacy
            ;;
        none) return ;;
    esac
}

# ---------------------------------------------------------------------------
# SFTP only: create a dedicated system user with chroot
# ---------------------------------------------------------------------------
_ftp_sftp_only() {
    step "Configuring SFTP access for ${DOMAIN}"

    local ftp_user="${DOMAIN//./_}_sftp"
    ftp_user="${ftp_user:0:32}"
    local ftp_pass
    ftp_pass="$(gen_pass 20)"
    FTP_USER="$ftp_user"
    FTP_PASS="$ftp_pass"

    if ! id "$ftp_user" &>/dev/null; then
        useradd -m -d "/home/${ftp_user}" -s /usr/sbin/nologin \
            -c "SFTP user for ${DOMAIN}" "$ftp_user"
    fi
    echo "${ftp_user}:${ftp_pass}" | chpasswd

    # Bind-mount the site root into the user's home
    mkdir -p "/home/${ftp_user}/www"
    mount --bind "${SITE_ROOT}" "/home/${ftp_user}/www" 2>/dev/null \
        || ln -sfn "${SITE_ROOT}" "/home/${ftp_user}/www"

    # SSHD chroot group
    if ! grep -q "^Match Group sftponly" /etc/ssh/sshd_config; then
        cat >> /etc/ssh/sshd_config <<SSHCFG

# UnderHost SFTP-only configuration
Match Group sftponly
    ChrootDirectory %h
    ForceCommand internal-sftp -l INFO
    AllowTcpForwarding no
    X11Forwarding no
SSHCFG
    fi

    groupadd -f sftponly
    usermod -aG sftponly "$ftp_user"

    # Chroot requires root ownership on the home directory
    chown root:root "/home/${ftp_user}"
    chmod 755 "/home/${ftp_user}"
    chown "${ftp_user}:${ftp_user}" "/home/${ftp_user}/www" 2>/dev/null || true

    systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null || true
    ok "SFTP user '${ftp_user}' configured (chrooted to /home/${ftp_user})"
    info "Connect via: sftp ${ftp_user}@${DOMAIN}"
}

# ---------------------------------------------------------------------------
# vsftpd with TLS (FTPS)
# ---------------------------------------------------------------------------
_ftp_vsftpd_tls() {
    step "Installing vsftpd (FTP with TLS)"

    case "$PKG_MGR" in
        apt) DEBIAN_FRONTEND=noninteractive apt-get install -y -qq vsftpd ;;
        dnf) dnf -y -q install vsftpd ;;
    esac

    local ftp_user="${DOMAIN//./_}_ftp"
    ftp_user="${ftp_user:0:32}"
    local ftp_pass
    ftp_pass="$(gen_pass 20)"
    FTP_USER="$ftp_user"
    FTP_PASS="$ftp_pass"

    if ! id "$ftp_user" &>/dev/null; then
        useradd -m -d "${SITE_ROOT}" -s /bin/bash \
            -c "FTP user for ${DOMAIN}" "$ftp_user"
    fi
    echo "${ftp_user}:${ftp_pass}" | chpasswd
    chown -R "${ftp_user}:${ftp_user}" "${SITE_ROOT}"
    chmod 755 "${SITE_ROOT}"

    # Self-signed TLS cert for vsftpd (if no LE cert yet)
    local ssl_cert="/etc/ssl/certs/vsftpd-${DOMAIN}.pem"
    local ssl_key="/etc/ssl/private/vsftpd-${DOMAIN}.key"
    if [[ -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]]; then
        ssl_cert="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
        ssl_key="/etc/letsencrypt/live/${DOMAIN}/privkey.pem"
    else
        openssl req -x509 -nodes -days 3650 \
            -newkey rsa:2048 \
            -keyout "$ssl_key" \
            -out "$ssl_cert" \
            -subj "/CN=${DOMAIN}" &>/dev/null
    fi

    cat > /etc/vsftpd/vsftpd.conf <<VSFTPD
# UnderHost vsftpd — FTPS configuration for ${DOMAIN}
listen=YES
listen_ipv6=NO
local_enable=YES
write_enable=YES
local_umask=022
dirmessage_enable=YES
use_localtime=YES
xferlog_enable=YES
connect_from_port_20=YES

# Chroot / isolation
chroot_local_user=YES
allow_writeable_chroot=NO
secure_chroot_dir=/var/run/vsftpd/empty

# No anonymous access
anonymous_enable=NO
no_anon_password=YES

# TLS settings (FTPS)
ssl_enable=YES
ssl_tlsv1=NO
ssl_sslv2=NO
ssl_sslv3=NO
require_ssl_reuse=NO
ssl_ciphers=HIGH
rsa_cert_file=${ssl_cert}
rsa_private_key_file=${ssl_key}
force_local_data_ssl=YES
force_local_logins_ssl=YES

# Passive mode
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=50000

# PAM
pam_service_name=vsftpd

# User isolation
user_sub_token=\$USER
local_root=${SITE_ROOT}
VSFTPD

    mkdir -p /var/run/vsftpd/empty
    chmod 755 /var/run/vsftpd/empty

    systemctl enable vsftpd --now 2>/dev/null
    ok "vsftpd (FTPS) configured for user '${ftp_user}'"
    info "Connect via FTP client using explicit TLS to ${DOMAIN}:21"
}

# ---------------------------------------------------------------------------
# Legacy unencrypted FTP (strongly discouraged)
# ---------------------------------------------------------------------------
_ftp_vsftpd_legacy() {
    _ftp_vsftpd_tls
    # Flip off TLS requirement
    sed -i 's/^ssl_enable=YES/ssl_enable=NO/' /etc/vsftpd/vsftpd.conf
    sed -i 's/^force_local_data_ssl=YES/force_local_data_ssl=NO/' /etc/vsftpd/vsftpd.conf
    sed -i 's/^force_local_logins_ssl=YES/force_local_logins_ssl=NO/' /etc/vsftpd/vsftpd.conf
    systemctl restart vsftpd 2>/dev/null || true
    warn "Legacy unencrypted FTP is active. This is insecure. Use SFTP or FTPS in production."
}
