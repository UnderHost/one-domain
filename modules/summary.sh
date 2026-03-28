#!/usr/bin/env bash
# =============================================================================
#  UnderHost One-Domain — Post-Install Summary Module
#  modules/summary.sh
# =============================================================================

[[ -n "${_UH_SUMMARY_LOADED:-}" ]] && return 0
_UH_SUMMARY_LOADED=1

summary_print() {
    local report_file="/root/underhost_${DOMAIN}_$(date +%Y%m%d_%H%M%S).txt"

    # Generate the report content
    local content
    content="$(_summary_build)"

    # Save to file
    printf '%s\n' "$content" > "$report_file"
    chmod 600 "$report_file"

    # Print to terminal (with colors)
    _summary_print_terminal

    echo
    info "Credentials saved to: ${report_file}"
    info "Log file: ${LOG_FILE}"
    info "Keep ${report_file} secure — it contains all generated passwords."
}

_summary_build() {
    cat <<EOF
======================================================
  UnderHost One-Domain Install Report
  Domain:    ${DOMAIN}
  Mode:      ${INSTALL_MODE^^}
  Date:      $(date '+%Y-%m-%d %H:%M:%S')
  Installer: v${UNDERHOST_VERSION}
======================================================

SITE
  URL:            https://${DOMAIN}
  Document Root:  ${SITE_ROOT}/public
  PHP Version:    ${PHP_VERSION}

$(if [[ "$ENABLE_DB" == true ]]; then
cat <<DBEOF
DATABASE
  Name:           ${DB_NAME}
  User:           ${DB_USER}
  Password:       ${DB_PASS}
  Host:           127.0.0.1
  Root creds:     /root/.my.cnf (socket auth)
DBEOF
fi)

$(if [[ "$INSTALL_MODE" == "wp" ]]; then
cat <<WPEOF
WORDPRESS
  Admin URL:      https://${DOMAIN}/wp-admin/
  Admin User:     ${WP_ADMIN_USER}
  Admin Password: ${WP_ADMIN_PASS}
  Admin Email:    ${WP_ADMIN_EMAIL}
WPEOF
fi)

$(if [[ "$WP_STAGING" == true ]]; then
cat <<STGEOF
STAGING
  URL:            https://${STAGING_DOMAIN}
  Database:       ${STAGING_DB_NAME}
  DB User:        ${STAGING_DB_USER}
  DB Password:    ${STAGING_DB_PASS}
  HTTP Auth User: ${STAGING_HTTP_USER}
  HTTP Auth Pass: ${STAGING_HTTP_PASS}
STGEOF
fi)

$(if [[ "$FTP_MODE" != "none" ]]; then
cat <<FTPEOF
FILE ACCESS (${FTP_MODE^^})
  User:           ${FTP_USER}
  Password:       ${FTP_PASS}
  Host:           ${DOMAIN}
$(if [[ "$FTP_MODE" == "ftp-tls" ]]; then
  echo "  Port:           21 (FTPS/TLS required)"
elif [[ "$FTP_MODE" == "sftp" ]]; then
  echo "  Port:           22 (SFTP)"
fi)
FTPEOF
fi)

FILES
  Nginx vhost:    $(os_nginx_conf_dir 2>/dev/null || echo /etc/nginx/conf.d)/${DOMAIN}.conf
  PHP-FPM pool:   $(os_php_pool_dir   2>/dev/null || echo /etc/php-fpm.d)/${DOMAIN}.conf
  SSL certs:      /etc/letsencrypt/live/${DOMAIN}/
  Install log:    ${LOG_FILE}
  This report:    /root/underhost_${DOMAIN}_*.txt

NEXT STEPS
  1. Upload your site files to ${SITE_ROOT}/public/
  2. Verify your site loads: https://${DOMAIN}
  3. Set up backups — not configured automatically
  4. Review logs: tail -f /var/log/nginx/${DOMAIN}.access.log
  5. Test SSL renewal: certbot renew --dry-run

SECURITY CHECKLIST
  [x] Nginx security headers
  [x] HTTPS enforced (HTTP redirects to HTTPS)
  [x] HSTS header with preload
  [x] TLS 1.2 / 1.3 only
  [x] Fail2Ban: SSH + Nginx jails active
  [x] PHP-FPM: isolated system user
  [x] PHP open_basedir: restricted to site root
  [x] MariaDB: anonymous users removed, remote root disabled
  [x] Kernel: SYN cookies, rp_filter, ICMP broadcast protection
  [x] SSH: root login requires key, MaxAuthTries=4
  [ ] Backups: configure a backup strategy
  [ ] Monitoring: set up uptime monitoring
  [ ] Updates: schedule regular OS + WordPress updates

======================================================
  UnderHost.com — High-Performance Managed Hosting
======================================================
EOF
}

_summary_print_terminal() {
    echo
    printf '%b%s%b\n' "$_CLR_LCYAN" "$(printf '=%.0s' {1..60})" "$_CLR_RESET"
    printf '%b  ✓  Installation Complete — %s%b\n' "$_CLR_LGREEN" "$DOMAIN" "$_CLR_RESET"
    printf '%b%s%b\n' "$_CLR_LCYAN" "$(printf '=%.0s' {1..60})" "$_CLR_RESET"
    echo

    printf '  %b%-18s%b %s\n' "$_CLR_BOLD" "Site URL:"       "$_CLR_RESET" "https://${DOMAIN}"
    printf '  %b%-18s%b %s\n' "$_CLR_BOLD" "Document Root:"  "$_CLR_RESET" "${SITE_ROOT}/public"
    printf '  %b%-18s%b %s\n' "$_CLR_BOLD" "PHP Version:"    "$_CLR_RESET" "${PHP_VERSION}"

    if [[ "$ENABLE_DB" == true ]]; then
        echo
        printf '  %b%-18s%b %s\n' "$_CLR_BOLD" "DB Name:"    "$_CLR_RESET" "$DB_NAME"
        printf '  %b%-18s%b %s\n' "$_CLR_BOLD" "DB User:"    "$_CLR_RESET" "$DB_USER"
        printf '  %b%-18s%b %s\n' "$_CLR_BOLD" "DB Pass:"    "$_CLR_RESET" "$DB_PASS"
    fi

    if [[ "$INSTALL_MODE" == "wp" ]]; then
        echo
        printf '  %b%-18s%b %s\n' "$_CLR_BOLD" "WP Admin URL:"  "$_CLR_RESET" "https://${DOMAIN}/wp-admin/"
        printf '  %b%-18s%b %s\n' "$_CLR_BOLD" "WP Admin:"      "$_CLR_RESET" "$WP_ADMIN_USER"
        printf '  %b%-18s%b %s\n' "$_CLR_BOLD" "WP Password:"   "$_CLR_RESET" "$WP_ADMIN_PASS"
    fi

    if [[ "$WP_STAGING" == true ]]; then
        echo
        printf '  %b%-18s%b %s\n' "$_CLR_BOLD" "Staging URL:"   "$_CLR_RESET" "https://${STAGING_DOMAIN}"
        printf '  %b%-18s%b %s\n' "$_CLR_BOLD" "Staging Auth:"  "$_CLR_RESET" "${STAGING_HTTP_USER} / ${STAGING_HTTP_PASS}"
    fi

    if [[ "$FTP_MODE" != "none" ]]; then
        echo
        printf '  %b%-18s%b %s\n' "$_CLR_BOLD" "FTP/SFTP User:"  "$_CLR_RESET" "$FTP_USER"
        printf '  %b%-18s%b %s\n' "$_CLR_BOLD" "FTP/SFTP Pass:"  "$_CLR_RESET" "$FTP_PASS"
    fi

    echo
    printf '%b  Service Status:%b\n' "$_CLR_BOLD" "$_CLR_RESET"
    for svc in nginx mariadb "$(os_php_fpm_service 2>/dev/null || echo php-fpm)"; do
        local state
        state="$(systemctl is-active "$svc" 2>/dev/null || echo unknown)"
        local color="$_CLR_LGREEN"
        [[ "$state" != "active" ]] && color="$_CLR_YELLOW"
        printf '    %b%-22s%b %b%s%b\n' "$_CLR_BOLD" "${svc}:" "$_CLR_RESET" "$color" "$state" "$_CLR_RESET"
    done

    echo
    printf '%b  Security Checklist:%b\n' "$_CLR_BOLD" "$_CLR_RESET"
    local checks=(
        "HTTPS enforced"
        "TLS 1.2/1.3 only"
        "Nginx security headers"
        "PHP-FPM isolated user"
        "MariaDB secured"
        "Fail2Ban active"
        "SSH hardened"
        "Kernel hardened"
    )
    for check in "${checks[@]}"; do
        printf '    %b✓%b  %s\n' "$_CLR_LGREEN" "$_CLR_RESET" "$check"
    done
    printf '    %b✗%b  Backups — %bconfigure separately%b\n' \
        "$_CLR_YELLOW" "$_CLR_RESET" "$_CLR_YELLOW" "$_CLR_RESET"

    echo
    printf '%b%s%b\n' "$_CLR_DIM" "$(printf '=%.0s' {1..60})" "$_CLR_RESET"
}
