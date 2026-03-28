#!/usr/bin/env bash
# =============================================================================
#  modules/repair.sh — Repair an existing domain deployment
#
#  Usage:  install repair domain.com
#          install --repair domain.com
#
#  Can rebuild:
#    - Nginx vhost
#    - PHP-FPM pool
#    - file permissions
#    - SSL certificate
#    - database user
#    - service restart
# =============================================================================

repair_domain() {
    local domain="${1:-$DOMAIN}"
    [[ -z "$domain" ]] && die "Usage: install repair domain.com"
    _validate_domain "$domain"

    os_detect
    os_validate_support

    section_banner "UnderHost Repair: ${domain}"

    # Detect what's installed
    local site_root="/var/www/${domain}"
    local vhost_file="/etc/nginx/conf.d/${domain}.conf"
    local pool_dir
    pool_dir="$(os_php_fpm_pool_dir 2>/dev/null || echo /etc/php-fpm.d)"
    local pool_file="${pool_dir}/${domain}.conf"
    local site_user="${domain//./_}"
    site_user="${site_user:0:32}"

    [[ -d "$site_root" ]] || die "Document root not found: ${site_root} — is ${domain} installed?"

    echo -e "  What would you like to repair?\n"
    echo -e "    ${YELLOW}1)${RESET} Nginx vhost config"
    echo -e "    ${YELLOW}2)${RESET} PHP-FPM pool config"
    echo -e "    ${YELLOW}3)${RESET} File permissions"
    echo -e "    ${YELLOW}4)${RESET} SSL certificate"
    echo -e "    ${YELLOW}5)${RESET} Restart all services"
    echo -e "    ${YELLOW}6)${RESET} Verify database connectivity"
    echo -e "    ${YELLOW}7)${RESET} All of the above"
    echo

    local choice
    read -r -p "$(echo -e "${CYAN}  Enter choice(s) e.g. 3 or 1,3,5 or 7: ${RESET}")" choice

    # Parse comma-separated choices
    IFS=',' read -ra choices <<< "$choice"
    local do_all=false
    for c in "${choices[@]}"; do
        [[ "${c// /}" == "7" ]] && do_all=true && break
    done

    _repair_contains() { $do_all || [[ " ${choices[*]} " == *" $1 "* ]]; }

    DOMAIN="$domain"
    SITE_ROOT="$site_root"

    # Detect install mode from wp-config presence
    INSTALL_MODE="php"
    [[ -f "${site_root}/wp-config.php" ]] && INSTALL_MODE="wp"

    # Detect PHP version from pool file
    PHP_VERSION="${PHP_VERSION:-8.3}"
    if [[ -f "$pool_file" ]]; then
        local detected_ver
        detected_ver="$(grep -oP 'php\K[\d.]+' <<< "$pool_file" 2>/dev/null || true)"
        [[ -n "$detected_ver" ]] && PHP_VERSION="$detected_ver"
        # Try from socket path
        local sock_path
        sock_path="$(grep '^listen\s*=' "$pool_file" 2>/dev/null | awk -F= '{print $2}' | tr -d ' ')"
        if [[ "$sock_path" =~ php([0-9.]+) ]]; then
            PHP_VERSION="${BASH_REMATCH[1]}"
        fi
    fi

    os_php_fpm_sock   # sets PHP_FPM_SOCK

    # Detect canonical www
    CANONICAL_WWW=false
    if [[ -f "$vhost_file" ]]; then
        grep -q "www\.${domain}" "$vhost_file" && CANONICAL_WWW=false
    fi

    step "Repairing ${domain} (mode: ${INSTALL_MODE^^}, PHP: ${PHP_VERSION})"

    # ---- 1. Nginx vhost ----
    if _repair_contains "1"; then
        step "Rebuilding Nginx vhost"
        [[ -f "$vhost_file" ]] && cp "$vhost_file" "${vhost_file}.bak.$(date +%s)" && ok "Backup: ${vhost_file}.bak"
        if [[ "$INSTALL_MODE" == "wp" ]]; then
            _nginx_wp_vhost "${DOMAIN}" "$vhost_file"
        else
            _nginx_php_vhost "${DOMAIN}" "$vhost_file"
        fi
        if nginx -t 2>/dev/null; then
            systemctl reload nginx && ok "Nginx vhost rebuilt and reloaded"
        else
            warn "Nginx config test failed — review ${vhost_file}"
        fi
    fi

    # ---- 2. PHP-FPM pool ----
    if _repair_contains "2"; then
        step "Rebuilding PHP-FPM pool"
        [[ -f "$pool_file" ]] && cp "$pool_file" "${pool_file}.bak.$(date +%s)" && ok "Backup: ${pool_file}.bak"
        php_configure_pool
        local php_fpm_svc="php${PHP_VERSION}-fpm"
        systemctl restart "$php_fpm_svc" 2>/dev/null \
            || systemctl restart php-fpm 2>/dev/null \
            || warn "Could not restart PHP-FPM"
        ok "PHP-FPM pool rebuilt"
    fi

    # ---- 3. Permissions ----
    if _repair_contains "3"; then
        step "Fixing file permissions"
        _repair_permissions "$site_root" "$site_user"
    fi

    # ---- 4. SSL ----
    if _repair_contains "4"; then
        step "Re-issuing SSL certificate"
        local ssl_email
        ssl_email="$(prompt_text "SSL email" "admin@${domain}")"
        SSL_EMAIL="$ssl_email"
        if certbot --nginx -d "${domain}" -d "www.${domain}" \
                --non-interactive --agree-tos \
                --email "${ssl_email}" --redirect 2>&1 | tee -a "${LOG_FILE:-/dev/null}"; then
            ok "SSL certificate issued for ${domain}"
        else
            warn "certbot failed — check DNS and port 80 accessibility"
        fi
    fi

    # ---- 5. Restart services ----
    if _repair_contains "5"; then
        step "Restarting services"
        for svc in nginx mariadb; do
            systemctl restart "$svc" 2>/dev/null && ok "Restarted $svc" || warn "Could not restart $svc"
        done
        local php_fpm_svc="php${PHP_VERSION}-fpm"
        systemctl restart "$php_fpm_svc" 2>/dev/null \
            || systemctl restart php-fpm 2>/dev/null \
            || warn "Could not restart PHP-FPM"
        systemctl restart redis 2>/dev/null || true
        systemctl restart fail2ban 2>/dev/null || true
        ok "Services restarted"
    fi

    # ---- 6. DB check ----
    if _repair_contains "6"; then
        step "Verifying database connectivity"
        if mysql -u root --connect-timeout=3 -e "SHOW DATABASES;" &>/dev/null 2>&1; then
            ok "MariaDB connection OK (unix socket)"
        else
            local db_pass
            db_pass="$(prompt_pass "MariaDB root password")"
            if mysql -u root -p"${db_pass}" --connect-timeout=3 -e "SHOW DATABASES;" &>/dev/null; then
                ok "MariaDB connection OK (password auth)"
            else
                warn "Could not connect to MariaDB — check credentials"
            fi
        fi
    fi

    echo
    ok "Repair complete for ${domain}"
    info "Run 'install diagnose ${domain}' to verify the full stack."
}

# ---------------------------------------------------------------------------
_repair_permissions() {
    local site_root="$1"
    local site_user="$2"
    local web_user
    web_user="$(os_web_user 2>/dev/null || echo www-data)"

    # Create user if missing
    if ! id "$site_user" &>/dev/null; then
        useradd -r -s /usr/sbin/nologin -d "$site_root" "$site_user" 2>/dev/null \
            && ok "Recreated system user: ${site_user}" \
            || warn "Could not create user ${site_user}"
    fi

    chown -R "${site_user}:${web_user}" "$site_root"
    find "$site_root" -type d -exec chmod 755 {} \;
    find "$site_root" -type f -exec chmod 644 {} \;

    # wp-config stricter
    [[ -f "${site_root}/wp-config.php" ]] && chmod 640 "${site_root}/wp-config.php"

    # Uploads writable by web server
    local uploads="${site_root}/wp-content/uploads"
    if [[ -d "$uploads" ]]; then
        chown -R "${web_user}:${web_user}" "$uploads"
        chmod -R 755 "$uploads"
        ok "Uploads directory ownership fixed"
    fi

    ok "Permissions fixed for ${site_root}"
}
