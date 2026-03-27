#!/usr/bin/env bash
# =============================================================================
#  modules/summary.sh — Post-install summary and credential storage
# =============================================================================

summary_print() {
    local report_file="/root/underhost_${DOMAIN}_$(date +%Y%m%d%H%M%S).txt"

    _summary_render | tee "$report_file"
    chmod 600 "$report_file"

    echo
    ok "Full report saved to: ${report_file}"
    warn "Keep this file secure — it contains credentials."
}

# ---------------------------------------------------------------------------
_summary_render() {
    local ssl_status="Not installed (run certbot manually)"
    [[ -f "/etc/letsencrypt/live/${DOMAIN}/cert.pem" ]] && ssl_status="✔ Installed"

    local canonical="https://${DOMAIN}"
    [[ "$CANONICAL_WWW" == true ]] && canonical="https://www.${DOMAIN}"

    local php_fpm_svc
    php_fpm_svc="$(os_php_fpm_service)"

    local nginx_status mariadb_status php_status redis_status fail2ban_status
    nginx_status="$(   systemctl is-active nginx       2>/dev/null || echo inactive)"
    mariadb_status="$( systemctl is-active mariadb     2>/dev/null || echo inactive)"
    php_status="$(     systemctl is-active "$php_fpm_svc" 2>/dev/null \
                    || systemctl is-active php-fpm      2>/dev/null \
                    || echo inactive)"
    redis_status="$(   [[ "$ENABLE_REDIS" == true ]] \
                    && systemctl is-active redis        2>/dev/null \
                    || echo disabled)"
    fail2ban_status="$([[ "$ENABLE_FAIL2BAN" == true ]] \
                    && systemctl is-active fail2ban     2>/dev/null \
                    || echo disabled)"

    cat <<SUMMARY

╔══════════════════════════════════════════════════════════════════╗
║          UnderHost Installation Complete  🎉                     ║
╚══════════════════════════════════════════════════════════════════╝

  Generated : $(date)
  Version   : UnderHost Installer ${UNDERHOST_VERSION}
  Log       : ${LOG_FILE}

──────────────────────────────────────────────────────────────────
  SITE INFORMATION
──────────────────────────────────────────────────────────────────
  Domain          : ${DOMAIN}
  Canonical URL   : ${canonical}
  Mode            : ${INSTALL_MODE^^}
  Document root   : ${SITE_ROOT}
  PHP version     : ${PHP_VERSION}
  SSL status      : ${ssl_status}

──────────────────────────────────────────────────────────────────
  SERVICE STATUS
──────────────────────────────────────────────────────────────────
  Nginx           : ${nginx_status}
  MariaDB         : ${mariadb_status}
  PHP-FPM         : ${php_status}
  Redis           : ${redis_status}
  Fail2Ban        : ${fail2ban_status}

──────────────────────────────────────────────────────────────────
  DATABASE CREDENTIALS
──────────────────────────────────────────────────────────────────
$( if [[ "$ENABLE_DB" == true ]]; then
cat <<DB
  MySQL root pass : ${MYSQL_ROOT_PASS}
  Database name   : ${DB_NAME}
  Database user   : ${DB_USER}
  Database pass   : ${DB_PASS}
DB
else
  echo "  Database        : Not configured"
fi )

$( if [[ "$INSTALL_MODE" == "wp" ]]; then
cat <<WP
──────────────────────────────────────────────────────────────────
  WORDPRESS
──────────────────────────────────────────────────────────────────
  Admin URL       : ${canonical}/wp-admin/
  Admin user      : ${WP_ADMIN_USER}
  Admin password  : ${WP_ADMIN_PASS}
  Admin email     : ${WP_ADMIN_EMAIL}
  Redis cache     : $( [[ "$WP_REDIS" == true ]] && echo "enabled" || echo "disabled" )
  Hardening       : $( [[ "$WP_HARDEN" == true ]] && echo "applied" || echo "skipped" )
  Auto-updates    : $( [[ "$WP_AUTO_UPDATES" == true ]] && echo "minor/security" || echo "disabled" )
WP
fi )

$( if [[ "$WP_STAGING" == true ]]; then
cat <<STAG
──────────────────────────────────────────────────────────────────
  STAGING ENVIRONMENT
──────────────────────────────────────────────────────────────────
  Staging URL     : https://${STAGING_DOMAIN:-${DOMAIN}/staging}
  Staging root    : ${STAGING_ROOT:-N/A}
  Staging DB name : ${STAGING_DB_NAME:-N/A}
  Staging DB user : ${STAGING_DB_USER:-N/A}
  Staging DB pass : ${STAGING_DB_PASS:-N/A}
  HTTP auth user  : ${STAGING_HTTP_USER:-staging}
  HTTP auth pass  : ${STAGING_HTTP_PASS:-N/A}
STAG
fi )

$( if [[ "$FTP_MODE" != "none" ]]; then
cat <<FTP
──────────────────────────────────────────────────────────────────
  FILE ACCESS
──────────────────────────────────────────────────────────────────
  Method          : ${FTP_MODE}
  Username        : ${FTP_USER:-N/A}
  Password        : ${FTP_PASS:-N/A}
$( [[ "$FTP_MODE" == "sftp" ]]    && echo "  Connect via     : sftp ${FTP_USER:-user}@${DOMAIN}" )
$( [[ "$FTP_MODE" == "ftp-tls" ]] && echo "  Connect via     : FTP client → ${DOMAIN}:21 (explicit TLS)" )
FTP
fi )

──────────────────────────────────────────────────────────────────
  IMPORTANT PATHS
──────────────────────────────────────────────────────────────────
  Nginx vhost     : /etc/nginx/conf.d/${DOMAIN}.conf
  PHP-FPM pool    : $(os_php_fpm_pool_dir)/${DOMAIN}.conf
  PHP socket      : ${PHP_FPM_SOCK}
  Log files       : /var/log/nginx/${DOMAIN}*.log
  PHP logs        : /var/log/php-fpm/${DOMAIN}*.log
  This report     : (saved above)

──────────────────────────────────────────────────────────────────
  NEXT STEPS
──────────────────────────────────────────────────────────────────
$( if [[ "$INSTALL_MODE" == "wp" ]]; then
echo "  1. Log into WordPress: ${canonical}/wp-admin/"
echo "  2. Install your theme and plugins"
echo "  3. Review Settings → Discussion (comments)"
echo "  4. Set up automated backups"
else
echo "  1. Upload your PHP files to: ${SITE_ROOT}"
echo "  2. Remove the placeholder: rm ${SITE_ROOT}/index.php"
echo "  3. Set up automated backups"
fi )
  $( [[ "$INSTALL_MODE" == "wp" ]] && echo 5 || echo 4 ). Monitor logs:  tail -f /var/log/nginx/${DOMAIN}.access.log
  $( [[ "$INSTALL_MODE" == "wp" ]] && echo 6 || echo 5 ). SSL renewal is automatic via certbot systemd timer

  Support: https://underhost.com/support

══════════════════════════════════════════════════════════════════
SUMMARY
}
