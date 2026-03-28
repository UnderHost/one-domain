#!/usr/bin/env bash
# =============================================================================
#  modules/wpcli.sh — WordPress utility commands
#
#  Provides:
#    wp_reset_perms domain.com   — fix WordPress file ownership/permissions
#    wp_clone src.com dest.com   — clone a WordPress install
#    wp_export_report domain.com — generate customer install report
# =============================================================================

# Wrapper: run WP-CLI as root
_wp_util() {
    local path="$1"; shift
    HOME=/root wp --path="$path" --allow-root "$@"
}

# ---------------------------------------------------------------------------
wp_reset_perms() {
    local domain="${1:-$DOMAIN}"
    [[ -z "$domain" ]] && die "Usage: install wp-reset-perms domain.com"
    _validate_domain "$domain"

    local site_root="/var/www/${domain}"
    [[ -d "$site_root" ]] || die "Document root not found: ${site_root}"
    [[ -f "${site_root}/wp-config.php" ]] || die "WordPress not detected at ${site_root}"

    local site_user="${domain//./_}"
    site_user="${site_user:0:32}"
    local web_user
    web_user="$(os_web_user 2>/dev/null || echo www-data)"

    section_banner "WordPress: Reset Permissions — ${domain}"
    step "Setting ownership: ${site_user}:${web_user}"

    chown -R "${site_user}:${web_user}" "$site_root"

    step "Setting directory permissions to 755"
    find "$site_root" -type d -exec chmod 755 {} \;

    step "Setting file permissions to 644"
    find "$site_root" -type f -exec chmod 644 {} \;

    step "Securing wp-config.php (640)"
    chmod 640 "${site_root}/wp-config.php"

    step "Fixing uploads directory (writeable by web server)"
    local uploads="${site_root}/wp-content/uploads"
    mkdir -p "$uploads"
    chown -R "${web_user}:${web_user}" "$uploads"
    chmod -R 755 "$uploads"

    ok "WordPress permissions reset complete for ${domain}"
    info "Site root : ${site_root}"
    info "Owner     : ${site_user}:${web_user}"
}

# ---------------------------------------------------------------------------
wp_clone() {
    local src_domain="${1:-}"
    local dst_domain="${2:-}"

    [[ -z "$src_domain" || -z "$dst_domain" ]] \
        && die "Usage: install wp-clone source.com destination.com"

    _validate_domain "$src_domain"
    _validate_domain "$dst_domain"

    local src_root="/var/www/${src_domain}"
    local dst_root="/var/www/${dst_domain}"

    [[ -d "$src_root" ]]              || die "Source not found: ${src_root}"
    [[ -f "${src_root}/wp-config.php" ]] || die "WordPress not detected at ${src_root}"

    section_banner "WordPress Clone: ${src_domain} → ${dst_domain}"

    step "Creating destination directory"
    mkdir -p "$dst_root"

    step "Cloning files with rsync"
    rsync -a --delete \
        --exclude '.git' \
        --exclude '*.log' \
        "${src_root}/" "${dst_root}/"
    ok "Files cloned"

    # Create destination database
    local dst_slug="${dst_domain//./_}"
    dst_slug="${dst_slug:0:32}"
    local dst_db_name="${dst_slug}_db"
    local dst_db_user="${dst_slug}_usr"
    local dst_db_pass
    dst_db_pass="$(gen_pass_db 24)"

    step "Creating destination database: ${dst_db_name}"
    local db_root_pass
    db_root_pass="$(prompt_pass "MariaDB root password")"

    mysql -u root -p"${db_root_pass}" <<SQL
CREATE DATABASE IF NOT EXISTS \`${dst_db_name}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${dst_db_user}'@'localhost' IDENTIFIED BY '${dst_db_pass}';
GRANT ALL PRIVILEGES ON \`${dst_db_name}\`.* TO '${dst_db_user}'@'localhost';
FLUSH PRIVILEGES;
SQL
    ok "Database created"

    step "Cloning source database into destination"
    local src_db_name
    src_db_name="$(grep "DB_NAME" "${src_root}/wp-config.php" | grep -oP "'[^']+'" | head -1 | tr -d "'")"
    [[ -z "$src_db_name" ]] && die "Could not detect source DB name from wp-config.php"

    local dump_file
    dump_file="$(mktemp --suffix=.sql)"
    mysqldump -u root -p"${db_root_pass}" "${src_db_name}" > "$dump_file" \
        || die "mysqldump failed for ${src_db_name}"
    mysql -u root -p"${db_root_pass}" "${dst_db_name}" < "$dump_file"
    rm -f "$dump_file"
    ok "Database cloned"

    step "Updating wp-config.php for destination"
    sed -i \
        -e "s/define( 'DB_NAME',.*$/define( 'DB_NAME',     '${dst_db_name}' );/" \
        -e "s/define( 'DB_USER',.*$/define( 'DB_USER',     '${dst_db_user}' );/" \
        -e "s/define( 'DB_PASSWORD',.*$/define( 'DB_PASSWORD', '${dst_db_pass}' );/" \
        -e "s|define( 'WP_HOME'.*|define( 'WP_HOME',    'https://${dst_domain}' );|" \
        -e "s|define( 'WP_SITEURL'.*|define( 'WP_SITEURL', 'https://${dst_domain}' );|" \
        "${dst_root}/wp-config.php"
    chmod 640 "${dst_root}/wp-config.php"
    ok "wp-config.php updated"

    step "Running WP-CLI search-replace"
    command -v wp &>/dev/null || { warn "WP-CLI not found — run search-replace manually"; return; }
    _wp_util "$dst_root" search-replace \
        "https://${src_domain}" "https://${dst_domain}" \
        --all-tables --precise --report-changed-only 2>/dev/null \
        && ok "Search-replace: https://${src_domain} → https://${dst_domain}" || true
    _wp_util "$dst_root" search-replace \
        "http://${src_domain}" "https://${dst_domain}" \
        --all-tables --precise --report-changed-only 2>/dev/null || true

    step "Fixing permissions"
    local dst_user="${dst_slug:0:32}"
    id "$dst_user" &>/dev/null \
        || useradd -r -s /usr/sbin/nologin -d "$dst_root" "$dst_user" 2>/dev/null || true
    local web_user
    web_user="$(os_web_user 2>/dev/null || echo www-data)"
    chown -R "${dst_user}:${web_user}" "$dst_root"
    find "$dst_root" -type d -exec chmod 755 {} \;
    find "$dst_root" -type f -exec chmod 644 {} \;
    chmod 640 "${dst_root}/wp-config.php"
    mkdir -p "${dst_root}/wp-content/uploads"
    chown -R "${web_user}:${web_user}" "${dst_root}/wp-content/uploads"

    echo
    ok "WordPress clone complete!"
    info "  Source      : https://${src_domain}"
    info "  Destination : https://${dst_domain}  (DNS + Nginx vhost needed)"
    info "  DB name     : ${dst_db_name}"
    info "  DB user     : ${dst_db_user}"
    info "  DB pass     : ${dst_db_pass}"
    warn "  Next: run 'install ${dst_domain} wp' or add a Nginx vhost for ${dst_domain}"
}

# ---------------------------------------------------------------------------
wp_export_report() {
    local domain="${1:-$DOMAIN}"
    [[ -z "$domain" ]] && die "Usage: install export-report domain.com"
    _validate_domain "$domain"

    local site_root="/var/www/${domain}"
    [[ -d "$site_root" ]] || die "Document root not found: ${site_root}"

    local ssl_cert="/etc/letsencrypt/live/${domain}/cert.pem"
    local ssl_expiry="Not installed"
    [[ -f "$ssl_cert" ]] && ssl_expiry="$(openssl x509 -enddate -noout -in "$ssl_cert" 2>/dev/null \
        | sed 's/notAfter=//' || echo unknown)"

    local wp_ver="N/A"
    [[ -f "${site_root}/wp-includes/version.php" ]] \
        && wp_ver="$(grep -oP "wp_version = '\K[^']+" "${site_root}/wp-includes/version.php" 2>/dev/null || echo unknown)"

    local nginx_ver php_ver mariadb_ver
    nginx_ver="$(  nginx -v 2>&1 | grep -oP 'nginx/\K[\d.]+' || echo unknown)"
    php_ver="$(    php -v 2>/dev/null | head -1 | awk '{print $2}' || echo unknown)"
    mariadb_ver="$(mysql --version 2>/dev/null | awk '{print $5}' | tr -d ',' || echo unknown)"

    local report_file="/root/underhost_report_${domain}_$(date +%Y%m%d%H%M%S).txt"

    cat > "$report_file" <<REPORT
══════════════════════════════════════════════════════════════════════
  UnderHost — Customer Site Report
  Generated: $(date)
══════════════════════════════════════════════════════════════════════

  SITE DETAILS
  ─────────────────────────────────────────────────────────────────────
  Domain          : ${domain}
  URL             : https://${domain}
  Document Root   : ${site_root}
  WordPress       : ${wp_ver}

  HOSTING ENVIRONMENT
  ─────────────────────────────────────────────────────────────────────
  OS              : $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2 || uname -o)
  Nginx           : ${nginx_ver}
  PHP             : ${php_ver}
  MariaDB         : ${mariadb_ver}
  Redis           : $(redis-cli --version 2>/dev/null | awk '{print $2}' || echo "not installed")

  SSL CERTIFICATE
  ─────────────────────────────────────────────────────────────────────
  Provider        : Let's Encrypt (Certbot)
  Expiry          : ${ssl_expiry}
  Auto-renewal    : $(systemctl is-active certbot.timer 2>/dev/null || echo "check manually")

  SERVICES STATUS
  ─────────────────────────────────────────────────────────────────────
  Nginx           : $(systemctl is-active nginx    2>/dev/null || echo unknown)
  MariaDB         : $(systemctl is-active mariadb  2>/dev/null || echo unknown)
  PHP-FPM         : $(systemctl is-active php8.3-fpm php8.2-fpm php-fpm 2>/dev/null | grep active | head -1 || echo unknown)
  Redis           : $(systemctl is-active redis    2>/dev/null || echo "not installed")
  Fail2Ban        : $(systemctl is-active fail2ban 2>/dev/null || echo "not installed")
  Firewall        : $(ufw status 2>/dev/null | head -1 || firewall-cmd --state 2>/dev/null || echo unknown)

  DISK USAGE
  ─────────────────────────────────────────────────────────────────────
$(df -h /var/www 2>/dev/null | awk 'NR<=2{printf "  %s\n",$0}')
  Site size       : $(du -sh "${site_root}" 2>/dev/null | cut -f1)

  IMPORTANT PATHS
  ─────────────────────────────────────────────────────────────────────
  Nginx vhost     : /etc/nginx/conf.d/${domain}.conf
  PHP-FPM pool    : (see /etc/php or /etc/php-fpm.d)
  SSL certs       : /etc/letsencrypt/live/${domain}/
  Nginx logs      : /var/log/nginx/${domain}*.log
  Install log     : /var/log/underhost_install.log

  SUPPORT
  ─────────────────────────────────────────────────────────────────────
  Installer       : UnderHost One-Domain Installer
  Documentation   : https://underhost.com/docs
  Support         : https://underhost.com/support

══════════════════════════════════════════════════════════════════════
REPORT

    chmod 600 "$report_file"
    ok "Customer report saved: ${report_file}"
    echo
    cat "$report_file"
}
