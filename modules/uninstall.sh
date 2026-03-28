#!/usr/bin/env bash
# =============================================================================
#  UnderHost One-Domain — Uninstall Module
#  modules/uninstall.sh
# =============================================================================

[[ -n "${_UH_UNINSTALL_LOADED:-}" ]] && return 0
_UH_UNINSTALL_LOADED=1

uninstall_domain() {
    local dom="${1:-}"
    [[ -z "$dom" ]] && die "Usage: install uninstall domain.com"

    step "Uninstalling domain: ${dom}"

    warn "This will remove:"
    warn "  • Nginx vhost for ${dom}"
    warn "  • PHP-FPM pool for ${dom}"
    warn "  • SSL certificate for ${dom}"
    warn "  • Database: $(slug_from_domain "$dom")_db"
    warn "  • Site files: /var/www/${dom}/"
    warn "  • System user: $(slug_from_domain "$dom" | cut -c1-16)_web"
    warn ""
    warn "  This action is irreversible. Files will be deleted."
    echo

    if [[ "${SKIP_PROMPT:-false}" != true ]]; then
        prompt_yn "Type 'yes' to confirm uninstall of ${dom}" "n" || die "Uninstall cancelled."
        # Extra confirmation for destructive action
        printf '  Type the domain name to confirm: '
        local confirm_dom
        read -r confirm_dom
        [[ "$confirm_dom" != "$dom" ]] && die "Domain mismatch — uninstall cancelled."
    fi

    local conf_dir
    conf_dir="$(os_nginx_conf_dir 2>/dev/null || echo /etc/nginx/conf.d)"
    local pool_dir
    pool_dir="$(os_php_pool_dir 2>/dev/null || echo /etc/php-fpm.d)"
    local sys_user
    sys_user="$(slug_from_domain "$dom" | cut -c1-16)_web"

    # Remove Nginx vhost
    local vhost="${conf_dir}/${dom}.conf"
    if [[ -f "$vhost" ]]; then
        rm -f "$vhost"
        ok "Removed Nginx vhost: ${vhost}"
    fi

    # Remove staging vhost if present
    local stg_vhost="${conf_dir}/staging.${dom}.conf"
    [[ -f "$stg_vhost" ]] && rm -f "$stg_vhost" && ok "Removed staging vhost"

    # Remove PHP-FPM pool
    local pool="${pool_dir}/${dom}.conf"
    if [[ -f "$pool" ]]; then
        rm -f "$pool"
        ok "Removed PHP-FPM pool: ${pool}"
    fi

    # Revoke and delete SSL cert
    if [[ -d "/etc/letsencrypt/live/${dom}" ]]; then
        certbot delete --cert-name "$dom" --non-interactive 2>/dev/null \
            && ok "Deleted SSL certificate: ${dom}" \
            || warn "Could not delete SSL cert — clean up manually: certbot delete --cert-name ${dom}"
    fi

    # Drop database and user
    db_drop_domain "$dom" 2>/dev/null || true

    # Remove staging DB if present
    local slug
    slug="$(slug_from_domain "$dom")"
    mysql -e "DROP DATABASE IF EXISTS \`${slug}_stg_db\`;" 2>/dev/null || true
    mysql -e "DROP USER IF EXISTS '${slug}_stg_usr'@'localhost';" 2>/dev/null || true
    mysql -e "FLUSH PRIVILEGES;" 2>/dev/null || true

    # Remove site files (with one last warning)
    local site_root="/var/www/${dom}"
    if [[ -d "$site_root" ]]; then
        warn "Removing site files: ${site_root}"
        rm -rf "$site_root"
        ok "Removed site files: ${site_root}"
    fi

    # Remove system user
    if id "$sys_user" &>/dev/null; then
        userdel -r "$sys_user" 2>/dev/null \
            && ok "Removed system user: ${sys_user}" \
            || warn "Could not remove user ${sys_user} — remove manually: userdel -r ${sys_user}"
    fi

    # Remove FTP user (SFTP match block from sshd_config)
    local ftp_marker="# UH-SFTP-${dom}"
    if grep -q "$ftp_marker" /etc/ssh/sshd_config 2>/dev/null; then
        sed -i "/${ftp_marker}/,/PasswordAuthentication yes/d" /etc/ssh/sshd_config
        sshd -t 2>/dev/null && (systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null || true)
        ok "Removed SFTP config for ${dom}"
    fi

    # Remove log files
    rm -f "/var/log/nginx/${dom}.access.log" \
          "/var/log/nginx/${dom}.error.log" \
          "/var/log/php-fpm/${dom}.access.log" \
          "/var/log/php-fpm/${dom}.error.log" 2>/dev/null || true

    # Reload services
    nginx -t 2>/dev/null && svc_reload nginx || true
    svc_reload "$(os_php_fpm_service 2>/dev/null || echo php-fpm)" || true

    ok "Domain ${dom} uninstalled"
}
