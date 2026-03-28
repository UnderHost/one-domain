#!/usr/bin/env bash
# =============================================================================
#  modules/staging.sh — WordPress staging environment creation
# =============================================================================

staging_create() {
    step "Creating WordPress staging environment"

    case "$WP_STAGING_TYPE" in
        subdomain) _staging_subdomain ;;
        subdir)    _staging_subdir    ;;
    esac
}

# ---------------------------------------------------------------------------
_staging_subdomain() {
    STAGING_DOMAIN="staging.${DOMAIN}"
    local staging_root="/var/www/${STAGING_DOMAIN}"
    local staging_db_name="${DB_NAME}_stg"
    # Staging gets its own DB user — never share production credentials
    local staging_db_user="${DB_USER}_stg"
    local staging_db_pass
    staging_db_pass="$(gen_pass_db 24)"
    local htpasswd_pass
    htpasswd_pass="$(gen_pass 16)"

    info "Staging domain: ${STAGING_DOMAIN}"
    info "Staging root:   ${staging_root}"

    # Create staging database and dedicated user
    mysql -u root -p"${MYSQL_ROOT_PASS}" <<SQL
CREATE DATABASE IF NOT EXISTS \`${staging_db_name}\`
    CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${staging_db_user}'@'localhost'
    IDENTIFIED BY '${staging_db_pass}';
GRANT ALL PRIVILEGES ON \`${staging_db_name}\`.* TO '${staging_db_user}'@'localhost';
FLUSH PRIVILEGES;
SQL
    ok "Staging database '${staging_db_name}' and user '${staging_db_user}' created"

    # Copy production WordPress to staging
    rsync -a --delete "${SITE_ROOT}/" "${staging_root}/"
    ok "WordPress files cloned to ${staging_root}"

    # Create staging wp-config.php with staging DB credentials
    sed \
        -e "s/define( 'DB_NAME',.*$/define( 'DB_NAME',     '${staging_db_name}' );/" \
        -e "s/define( 'DB_USER',.*$/define( 'DB_USER',     '${staging_db_user}' );/" \
        -e "s/define( 'DB_PASSWORD',.*$/define( 'DB_PASSWORD', '${staging_db_pass}' );/" \
        -e "s|define( 'WP_HOME'.*|define( 'WP_HOME',    'https://${STAGING_DOMAIN}' );|" \
        -e "s|define( 'WP_SITEURL'.*|define( 'WP_SITEURL', 'https://${STAGING_DOMAIN}' );|" \
        "${SITE_ROOT}/wp-config.php" > "${staging_root}/wp-config.php"
    chmod 640 "${staging_root}/wp-config.php"

    # Clone production DB into staging
    if command -v wp &>/dev/null; then
        local site_user="${DOMAIN//./_}"
        site_user="${site_user:0:32}"

        # Export production DB
        local dump_file
        dump_file="$(mktemp)"
        mysqldump -u root -p"${MYSQL_ROOT_PASS}" "${DB_NAME}" > "$dump_file"

        # Import into staging DB
        mysql -u root -p"${MYSQL_ROOT_PASS}" "${staging_db_name}" < "$dump_file"
        rm -f "$dump_file"

        # Update URLs in staging DB
        sudo -u "$site_user" wp --path="${staging_root}" \
            search-replace "https://${DOMAIN}" "https://${STAGING_DOMAIN}" --all-tables 2>/dev/null || true

        ok "Production database cloned and URLs replaced"
    else
        warn "WP-CLI not found — import production DB manually into '${staging_db_name}'"
    fi

    # Staging Nginx vhost
    local vhost_file="/etc/nginx/conf.d/${STAGING_DOMAIN}.conf"
    cat > "${vhost_file}" <<STAGINGVHOST
# UnderHost — Staging vhost for ${STAGING_DOMAIN}
# Generated $(date)

server {
    listen      80;
    listen      [::]:80;
    server_name ${STAGING_DOMAIN};
    root        ${staging_root};
    index       index.php index.html;

    # Noindex — prevent staging from appearing in search engines
    add_header  X-Robots-Tag "noindex, nofollow" always;

    # HTTP Basic Auth — password-protect staging
    auth_basic           "Staging Environment";
    auth_basic_user_file /etc/nginx/auth/${STAGING_DOMAIN}.htpasswd;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php$ {
        try_files \$uri =404;
        fastcgi_pass  unix:${PHP_FPM_SOCK};
        fastcgi_index index.php;
        include       fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }

    location ~ /\. {
        deny all;
    }
}
STAGINGVHOST

    # HTTP auth credentials
    mkdir -p /etc/nginx/auth
    if command -v htpasswd &>/dev/null; then
        htpasswd -cb "/etc/nginx/auth/${STAGING_DOMAIN}.htpasswd" \
            "staging" "${htpasswd_pass}" &>/dev/null
    else
        # Pure-bash htpasswd fallback (apr1-md5)
        local hash
        hash="$(openssl passwd -apr1 "${htpasswd_pass}")"
        echo "staging:${hash}" > "/etc/nginx/auth/${STAGING_DOMAIN}.htpasswd"
    fi
    chmod 640 "/etc/nginx/auth/${STAGING_DOMAIN}.htpasswd"

    # Copy staging permissions
    local site_user="${DOMAIN//./_}"
    site_user="${site_user:0:32}"
    local web_user
    web_user="$(os_web_user)"
    chown -R "${site_user}:${web_user}" "${staging_root}"
    find "${staging_root}" -type d -exec chmod 755 {} \;
    find "${staging_root}" -type f -exec chmod 644 {} \;
    chmod 640 "${staging_root}/wp-config.php"
    mkdir -p "${staging_root}/wp-content/uploads"
    chown -R "${web_user}:${web_user}" "${staging_root}/wp-content/uploads"

    # Validate and reload Nginx
    nginx -t 2>/dev/null && systemctl reload nginx

    # Request SSL for staging
    if certbot --nginx -d "${STAGING_DOMAIN}" --non-interactive \
            --agree-tos --email "${SSL_EMAIL}" --redirect &>/dev/null; then
        ok "SSL certificate obtained for ${STAGING_DOMAIN}"
    else
        warn "Could not get SSL for ${STAGING_DOMAIN} — ensure DNS is configured."
    fi

    # Export staging credentials to global scope for summary
    STAGING_HTTP_USER="staging"
    STAGING_HTTP_PASS="${htpasswd_pass}"
    STAGING_DB_NAME="${staging_db_name}"
    STAGING_DB_USER="${staging_db_user}"
    STAGING_DB_PASS="${staging_db_pass}"
    STAGING_ROOT="${staging_root}"

    ok "Staging environment ready: https://${STAGING_DOMAIN}"
    info "  HTTP auth: staging / ${htpasswd_pass}"
}

# ---------------------------------------------------------------------------
_staging_subdir() {
    local staging_root="${SITE_ROOT}/staging"
    info "Staging location: ${DOMAIN}/staging"

    mkdir -p "${staging_root}"
    rsync -a --delete "${SITE_ROOT}/" "${staging_root}/" \
        --exclude staging \
        --exclude wp-config.php

    # Add noindex to staging subdir via Nginx
    local vhost_file="/etc/nginx/conf.d/${DOMAIN}.conf"
    if ! grep -q "location /staging" "${vhost_file}" 2>/dev/null; then
        # Insert before the closing brace of the first server block
        cat >> "${vhost_file}" <<STAGINGSUBDIR

    # Staging subdirectory — password protected & noindexed
    location /staging {
        add_header X-Robots-Tag "noindex, nofollow" always;
        auth_basic           "Staging Environment";
        auth_basic_user_file /etc/nginx/auth/${DOMAIN}-staging.htpasswd;
        try_files \$uri \$uri/ /staging/index.php?\$args;
    }
STAGINGSUBDIR
    fi

    local htpasswd_pass
    htpasswd_pass="$(gen_pass 16)"
    mkdir -p /etc/nginx/auth
    local hash
    hash="$(openssl passwd -apr1 "${htpasswd_pass}")"
    echo "staging:${hash}" > "/etc/nginx/auth/${DOMAIN}-staging.htpasswd"

    nginx -t 2>/dev/null && systemctl reload nginx

    STAGING_HTTP_USER="staging"
    STAGING_HTTP_PASS="${htpasswd_pass}"
    STAGING_ROOT="${staging_root}"

    ok "Staging created at ${DOMAIN}/staging"
    info "  HTTP auth: staging / ${htpasswd_pass}"
}

# ---------------------------------------------------------------------------
# Push staging → production
staging_push() {
    local domain="${1:-$DOMAIN}"
    [[ -z "$domain" ]] && die "Usage: install staging-push domain.com"
    _validate_domain "$domain"

    local staging_root="/var/www/staging.${domain}"
    local prod_root="/var/www/${domain}"

    [[ -d "$staging_root" ]] || die "Staging not found: ${staging_root}"
    [[ -d "$prod_root"    ]] || die "Production root not found: ${prod_root}"

    section_banner "Staging Push → Production: ${domain}"
    warn "This will overwrite production files at ${prod_root}"
    warn "A backup of production will be taken first."
    prompt_yn "Proceed with staging → production push?" "n" \
        || { info "Cancelled."; return 0; }

    # Backup production first
    local backup_dir="/root/prod_backup_${domain//\./-}_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    rsync -a "${prod_root}/" "${backup_dir}/" && ok "Production backed up to: ${backup_dir}"

    # Push staging files to production (exclude wp-config.php — keep prod DB creds)
    step "Syncing staging files → production"
    rsync -a --delete \
        --exclude 'wp-config.php' \
        --exclude '.git' \
        "${staging_root}/" "${prod_root}/"
    ok "Files synced staging → production"

    # URL search-replace in production DB
    if command -v wp &>/dev/null; then
        step "Updating URLs in production database"
        HOME=/root wp --path="${prod_root}" --allow-root \
            search-replace "https://staging.${domain}" "https://${domain}" \
            --all-tables --precise --report-changed-only 2>/dev/null \
            && ok "URLs updated in production DB" || warn "search-replace had warnings"
    fi

    # Flush caches
    HOME=/root wp --path="${prod_root}" --allow-root cache flush 2>/dev/null && ok "Cache flushed" || true

    ok "Staging pushed to production. Backup at: ${backup_dir}"
}

# ---------------------------------------------------------------------------
# Pull production → staging (refresh staging)
staging_pull() {
    local domain="${1:-$DOMAIN}"
    [[ -z "$domain" ]] && die "Usage: install staging-pull domain.com"
    _validate_domain "$domain"

    local prod_root="/var/www/${domain}"
    local staging_root="/var/www/staging.${domain}"
    local staging_domain="staging.${domain}"

    [[ -d "$prod_root"    ]] || die "Production root not found: ${prod_root}"
    [[ -d "$staging_root" ]] || die "Staging not found: ${staging_root} — run install first"

    section_banner "Staging Pull (Refresh) from Production: ${domain}"
    prompt_yn "This will overwrite staging with production data. Continue?" "y" \
        || { info "Cancelled."; return 0; }

    step "Syncing production files → staging"
    rsync -a --delete \
        --exclude 'wp-config.php' \
        --exclude '.git' \
        "${prod_root}/" "${staging_root}/"
    ok "Files synced production → staging"

    # Clone production DB into staging DB
    if command -v wp &>/dev/null && [[ -f "${staging_root}/wp-config.php" ]]; then
        step "Refreshing staging database from production"
        local prod_db
        prod_db="$(grep "DB_NAME" "${prod_root}/wp-config.php" | grep -oP "'\K[^']+" | head -1)"
        local stg_db
        stg_db="$(grep "DB_NAME" "${staging_root}/wp-config.php" | grep -oP "'\K[^']+" | head -1)"

        if [[ -n "$prod_db" && -n "$stg_db" ]]; then
            local db_root_pass
            db_root_pass="$(prompt_pass "MariaDB root password")"
            local dump
            dump="$(mktemp --suffix=.sql)"
            mysqldump -u root -p"${db_root_pass}" "${prod_db}" > "$dump" \
                && mysql -u root -p"${db_root_pass}" "${stg_db}" < "$dump" \
                && ok "Staging DB refreshed from production"
            rm -f "$dump"

            # Fix URLs in staging DB
            HOME=/root wp --path="${staging_root}" --allow-root \
                search-replace "https://${domain}" "https://${staging_domain}" \
                --all-tables --precise --report-changed-only 2>/dev/null \
                && ok "URLs updated in staging DB" || warn "search-replace had warnings"
        fi
    fi

    ok "Staging refreshed from production: https://${staging_domain}"
}
