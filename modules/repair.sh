#!/usr/bin/env bash
# =============================================================================
#  UnderHost One-Domain — Repair Module
#  modules/repair.sh
# =============================================================================

[[ -n "${_UH_REPAIR_LOADED:-}" ]] && return 0
_UH_REPAIR_LOADED=1

repair_domain() {
    local dom="${1:-}"
    [[ -z "$dom" ]] && die "Usage: install repair domain.com"

    step "Repair wizard: ${dom}"

    local webroot="/var/www/${dom}/public"
    local sys_user
    sys_user="$(slug_from_domain "$dom" | cut -c1-16)_web"

    # Show current status first
    status_domain "$dom" 2>/dev/null || true

    echo
    info "Select what to repair:"
    local action
    action="$(prompt_select 'What needs fixing?' \
        'Restart all services' \
        'Fix Nginx configuration' \
        'Fix PHP-FPM pool' \
        'Fix file permissions' \
        'Test & renew SSL certificate' \
        'Re-apply security hardening' \
        'Re-apply performance tuning' \
        'Rebuild Nginx vhost' \
        'Exit')"

    case "$action" in
        "Restart all services")
            for svc in nginx mariadb "$(os_php_fpm_service 2>/dev/null || echo php-fpm)" fail2ban; do
                systemctl restart "$svc" 2>/dev/null \
                    && ok "Restarted ${svc}" \
                    || warn "Could not restart ${svc}"
            done
            ;;
        "Fix Nginx configuration")
            nginx -t && svc_reload nginx \
                || warn "Nginx configuration invalid — check $(os_nginx_conf_dir)/${dom}.conf"
            ;;
        "Fix PHP-FPM pool")
            local pool_dir
            pool_dir="$(os_php_pool_dir 2>/dev/null || echo /etc/php-fpm.d)"
            local pool="${pool_dir}/${dom}.conf"
            if [[ ! -f "$pool" ]]; then
                warn "PHP pool not found: ${pool}"
                if prompt_yn 'Rebuild PHP pool configuration?' 'y'; then
                    DOMAIN="$dom"
                    os_detect 2>/dev/null || true
                    _resolve_defaults 2>/dev/null || true
                    php_configure_pool
                fi
            else
                svc_reload "$(os_php_fpm_service 2>/dev/null || echo php-fpm)"
                ok "PHP-FPM reloaded"
            fi
            ;;
        "Fix file permissions")
            if [[ -f "${webroot}/wp-includes/version.php" ]]; then
                wp_reset_perms "$dom"
            else
                chown -R "${sys_user}:${sys_user}" "$webroot" 2>/dev/null || true
                find "$webroot" -type d -exec chmod 750 {} \; 2>/dev/null || true
                find "$webroot" -type f -exec chmod 640 {} \; 2>/dev/null || true
                ok "Permissions reset for ${dom}"
            fi
            ;;
        "Test & renew SSL certificate")
            ssl_renew_test "$dom"
            if prompt_yn 'Force SSL renewal now?' 'n'; then
                certbot renew --cert-name "$dom" --force-renewal 2>&1 \
                    | while IFS= read -r line; do info "$line"; done
            fi
            ;;
        "Re-apply security hardening")
            os_detect 2>/dev/null || true
            DOMAIN="$dom"
            hardening_apply
            ;;
        "Re-apply performance tuning")
            os_detect 2>/dev/null || true
            optimize_tune
            ;;
        "Rebuild Nginx vhost")
            warn "This will overwrite $(os_nginx_conf_dir)/${dom}.conf"
            if prompt_yn 'Proceed?' 'n'; then
                DOMAIN="$dom"
                os_detect 2>/dev/null || true
                nginx_configure_vhost
            fi
            ;;
        "Exit")
            info "Repair wizard exited."
            ;;
    esac
}
