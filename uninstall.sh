#!/usr/bin/env bash
# =============================================================================
#  modules/uninstall.sh — Remove a domain deployment created by the installer
#
#  Usage:  install --uninstall domain.com
#
#  Removes:
#    - Nginx vhost config
#    - PHP-FPM pool config
#    - Document root (with confirmation)
#    - MariaDB database and user
#    - System user
#    - SSL certificate
#    - Fail2Ban / logrotate / cron entries
#    - Staging environment (if present)
#    - FTP/SFTP user (if present)
#
#  Does NOT remove:
#    - System packages (Nginx, PHP, MariaDB, etc.)
#    - Global Nginx config
#    - Other domains on the same server
# =============================================================================

uninstall_domain() {
    local domain="${1:-$DOMAIN}"
    [[ -z "$domain" ]] && die "Usage: install --uninstall domain.com"
    _validate_domain "$domain"

    os_detect
    os_validate_support

    section_banner "Uninstall: ${domain}"
    warn "This will remove the deployment for ${BOLD}${domain}${RESET}."
    warn "Packages (Nginx, PHP, MariaDB) will NOT be removed."
    echo

    # Collect what exists before asking
    local site_user="${domain//./_}"
    site_user="${site_user:0:32}"
    local site_root="/var/www/${domain}"
    local vhost_file="/etc/nginx/conf.d/${domain}.conf"
    local pool_dir
    pool_dir="$(os_php_fpm_pool_dir 2>/dev/null || echo /etc/php-fpm.d)"
    local pool_file="${pool_dir}/${domain}.conf"
    local staging_domain="staging.${domain}"
    local staging_vhost="/etc/nginx/conf.d/${staging_domain}.conf"
    local cron_file="/etc/cron.d/wp-${site_user}"
    local logrotate_file
    logrotate_file="/etc/logrotate.d/underhost-${domain//\./-}"

    # Summary of what will be removed
    echo -e "  The following will be removed:"
    [[ -f "$vhost_file" ]]      && echo -e "    ${RED}✖${RESET} Nginx vhost:      $vhost_file"
    [[ -f "$pool_file" ]]       && echo -e "    ${RED}✖${RESET} PHP-FPM pool:     $pool_file"
    [[ -d "$site_root" ]]       && echo -e "    ${RED}✖${RESET} Document root:    $site_root"
    id "$site_user" &>/dev/null && echo -e "    ${RED}✖${RESET} System user:      $site_user"
    [[ -f "$staging_vhost" ]]   && echo -e "    ${RED}✖${RESET} Staging vhost:    $staging_vhost"
    [[ -d "/var/www/${staging_domain}" ]] \
                                && echo -e "    ${RED}✖${RESET} Staging root:     /var/www/${staging_domain}"
    [[ -f "$cron_file" ]]       && echo -e "    ${RED}✖${RESET} Cron job:         $cron_file"
    [[ -f "$logrotate_file" ]]  && echo -e "    ${RED}✖${RESET} Log rotation:     $logrotate_file"
    echo -e "    ${RED}✖${RESET} MariaDB DB + user (you will be prompted for root password)"
    echo -e "    ${RED}✖${RESET} Let's Encrypt certificate for ${domain}"
    echo

    prompt_yn "Proceed with uninstall?" "n" \
        || { info "Uninstall cancelled."; exit 0; }

    # Confirm document root deletion separately — it's destructive and irreversible
    local remove_webroot=false
    if [[ -d "$site_root" ]]; then
        echo
        warn "Document root ${BOLD}${site_root}${RESET} contains your website files."
        warn "This cannot be undone. Make sure you have a backup."
        prompt_yn "Delete document root ${site_root}?" "n" \
            && remove_webroot=true \
            || info "Skipping document root deletion — files preserved at ${site_root}"
    fi

    echo
    step "Removing deployment for ${domain}"

    _uninstall_nginx "$domain" "$vhost_file" "$staging_vhost"
    _uninstall_php_pool "$pool_file"
    _uninstall_ssl "$domain" "$staging_domain"
    _uninstall_database "$domain"
    _uninstall_cron "$cron_file"
    _uninstall_logrotate "$logrotate_file"
    _uninstall_auth_files "$domain" "$staging_domain"
    _uninstall_ftp_user "$site_user"
    _uninstall_system_user "$site_user"
    [[ "$remove_webroot" == true ]] && _uninstall_webroot "$site_root" "$staging_domain"

    echo
    ok "Deployment for ${domain} has been removed."
    [[ "$remove_webroot" == false && -d "$site_root" ]] \
        && info "Website files preserved at: ${site_root}"
    info "System packages (Nginx, PHP, MariaDB) were not touched."
}

# ---------------------------------------------------------------------------
_uninstall_nginx() {
    local domain="$1" vhost="$2" staging_vhost="$3"

    for conf in "$vhost" "$staging_vhost"; do
        if [[ -f "$conf" ]]; then
            rm -f "$conf"
            ok "Removed Nginx config: $conf"
        fi
    done

    # Test and reload if Nginx is running
    if systemctl is-active nginx &>/dev/null; then
        if nginx -t 2>/dev/null; then
            systemctl reload nginx
            ok "Nginx reloaded"
        else
            warn "Nginx config test failed after removal — check /etc/nginx/conf.d/"
        fi
    fi
}

# ---------------------------------------------------------------------------
_uninstall_php_pool() {
    local pool_file="$1"
    if [[ -f "$pool_file" ]]; then
        rm -f "$pool_file"
        ok "Removed PHP-FPM pool: $pool_file"

        # Restart PHP-FPM to drop the socket
        local php_fpm_svc
        php_fpm_svc="$(os_php_fpm_service 2>/dev/null || echo php-fpm)"
        systemctl restart "$php_fpm_svc" 2>/dev/null \
            && ok "PHP-FPM restarted" \
            || warn "Could not restart PHP-FPM"
    fi
}

# ---------------------------------------------------------------------------
_uninstall_ssl() {
    local domain="$1" staging_domain="$2"

    if command -v certbot &>/dev/null; then
        for d in "$domain" "www.${domain}" "$staging_domain"; do
            if [[ -d "/etc/letsencrypt/live/${d}" ]]; then
                certbot delete --cert-name "$d" --non-interactive 2>/dev/null \
                    && ok "SSL certificate removed: $d" \
                    || warn "Could not remove certificate for $d"
            fi
        done
        # Also try the main domain cert which may cover www as SAN
        certbot delete --cert-name "$domain" --non-interactive 2>/dev/null || true
    else
        warn "certbot not found — SSL certificates not removed"
    fi
}

# ---------------------------------------------------------------------------
_uninstall_database() {
    local domain="$1"
    local slug="${domain//./_}"
    slug="${slug:0:32}"

    # Ask for root password to connect
    local db_root_pass
    db_root_pass="$(prompt_pass "MariaDB root password (leave blank to skip DB removal)")"
    [[ -z "$db_root_pass" ]] && { warn "Skipping database removal"; return; }

    # Test connection
    if ! mysql -u root -p"${db_root_pass}" -e "SELECT 1;" &>/dev/null; then
        warn "Could not connect to MariaDB — skipping database removal"
        return
    fi

    # Guess db/user names matching installer convention (may differ if customised)
    local db_name="${slug}_db"
    local db_user="${slug}_usr"
    local staging_db="${slug}_db_stg"
    local staging_user="${slug}_usr_stg"

    # Allow override if user knows exact names
    echo
    info "Default DB name: ${db_name}  (press Enter to accept or type a different name)"
    local input_db_name
    input_db_name="$(prompt_text "Database name to drop" "${db_name}")"
    local input_db_user
    input_db_user="$(prompt_text "Database user to drop" "${db_user}")"

    mysql -u root -p"${db_root_pass}" <<SQL 2>/dev/null
DROP DATABASE IF EXISTS \`${input_db_name}\`;
DROP DATABASE IF EXISTS \`${staging_db}\`;
DROP USER IF EXISTS '${input_db_user}'@'localhost';
DROP USER IF EXISTS '${staging_user}'@'localhost';
FLUSH PRIVILEGES;
SQL
    ok "Database '${input_db_name}' and user '${input_db_user}' removed"
    ok "Staging database '${staging_db}' and user '${staging_user}' removed (if existed)"
}

# ---------------------------------------------------------------------------
_uninstall_cron() {
    local cron_file="$1"
    if [[ -f "$cron_file" ]]; then
        rm -f "$cron_file"
        ok "Removed cron job: $cron_file"
    fi
    # Also remove WP cron log
    local domain_slug="${cron_file##*/wp-}"
    rm -f "/var/log/wp-cron-${domain_slug}.log" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
_uninstall_logrotate() {
    local logrotate_file="$1"
    if [[ -f "$logrotate_file" ]]; then
        rm -f "$logrotate_file"
        ok "Removed logrotate config: $logrotate_file"
    fi
}

# ---------------------------------------------------------------------------
_uninstall_auth_files() {
    local domain="$1" staging_domain="$2"
    local auth_dir="/etc/nginx/auth"

    for pattern in "${domain}" "${staging_domain}" "${domain}-staging"; do
        local htpasswd="${auth_dir}/${pattern}.htpasswd"
        if [[ -f "$htpasswd" ]]; then
            rm -f "$htpasswd"
            ok "Removed htpasswd file: $htpasswd"
        fi
    done

    # Remove session directory
    local session_dir="/var/lib/php/sessions/${domain}"
    if [[ -d "$session_dir" ]]; then
        rm -rf "$session_dir"
        ok "Removed PHP session directory: $session_dir"
    fi
}

# ---------------------------------------------------------------------------
_uninstall_ftp_user() {
    local site_user="$1"
    local ftp_user="${site_user}_ftp"
    local sftp_user="${site_user}_sftp"

    for u in "$ftp_user" "$sftp_user"; do
        if id "$u" &>/dev/null; then
            userdel -r "$u" 2>/dev/null || userdel "$u" 2>/dev/null || true
            ok "Removed FTP/SFTP user: $u"
        fi
    done
}

# ---------------------------------------------------------------------------
_uninstall_system_user() {
    local site_user="$1"
    if id "$site_user" &>/dev/null; then
        # Don't delete if user owns processes (safety check)
        local procs
        procs="$(pgrep -u "$site_user" 2>/dev/null | wc -l)"
        if (( procs > 0 )); then
            warn "User '${site_user}' has ${procs} running process(es) — not removed"
            warn "Kill processes first, then run: userdel -r ${site_user}"
            return
        fi
        userdel -r "$site_user" 2>/dev/null \
            || userdel "$site_user" 2>/dev/null \
            || warn "Could not fully remove user '${site_user}'"
        ok "Removed system user: ${site_user}"
    fi
}

# ---------------------------------------------------------------------------
_uninstall_webroot() {
    local site_root="$1"
    local staging_domain="$2"

    if [[ -d "$site_root" ]]; then
        rm -rf "$site_root"
        ok "Removed document root: $site_root"
    fi

    local staging_root="/var/www/${staging_domain}"
    if [[ -d "$staging_root" ]]; then
        rm -rf "$staging_root"
        ok "Removed staging root: $staging_root"
    fi
}
