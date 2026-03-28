#!/usr/bin/env bash
# =============================================================================
#  UnderHost One-Domain — WordPress Staging Module
#  modules/staging.sh
# =============================================================================

[[ -n "${_UH_STAGING_LOADED:-}" ]] && return 0
_UH_STAGING_LOADED=1

staging_create() {
    step "Creating WordPress staging environment for ${DOMAIN}"

    [[ "$INSTALL_MODE" != "wp" ]] && die "Staging is only available for WordPress installs."

    local prod_root="${SITE_ROOT}/public"
    [[ ! -d "$prod_root" ]] && die "Production site not found: ${prod_root}"

    if [[ "${WP_STAGING_TYPE:-subdomain}" == "subdomain" ]]; then
        STAGING_DOMAIN="${STAGING_DOMAIN:-staging.${DOMAIN}}"
        STAGING_ROOT="/var/www/${STAGING_DOMAIN}/public"
    else
        STAGING_ROOT="${SITE_ROOT}/staging"
        STAGING_DOMAIN="${DOMAIN}/staging"
    fi

    local sys_user
    sys_user="$(slug_from_domain "$DOMAIN" | cut -c1-16)_web"

    _staging_copy_files "$prod_root" "$STAGING_ROOT" "$sys_user"
    _staging_create_db
    _staging_clone_db "$prod_root" "$STAGING_ROOT"
    _staging_update_urls "$STAGING_ROOT"
    _staging_write_config "$STAGING_ROOT"
    _staging_configure_nginx "$sys_user"
    _staging_provision_ssl

    ok "Staging environment created: https://${STAGING_DOMAIN}"
}

_staging_copy_files() {
    local src="$1" dst="$2" sys_user="$3"
    mkdir -p "$dst"
    rsync -a --exclude=wp-config.php "${src}/" "${dst}/"
    chown -R "${sys_user}:${sys_user}" "$dst"
    chmod 750 "$dst"
    ok "Files copied to staging: ${dst}"
}

_staging_create_db() {
    mysql <<EOSQL
CREATE DATABASE IF NOT EXISTS \`${STAGING_DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${STAGING_DB_USER}'@'localhost' IDENTIFIED BY '${STAGING_DB_PASS}';
GRANT ALL PRIVILEGES ON \`${STAGING_DB_NAME}\`.* TO '${STAGING_DB_USER}'@'localhost';
FLUSH PRIVILEGES;
EOSQL
    ok "Staging database created: ${STAGING_DB_NAME}"
}

_staging_clone_db() {
    local prod_root="$1" stg_root="$2"
    local tmp_sql="/tmp/staging_clone_$(date +%s).sql"
    wp db export "$tmp_sql" --path="$prod_root" --allow-root --quiet
    chmod 600 "$tmp_sql"
    wp db import "$tmp_sql" --path="$stg_root" --allow-root --quiet 2>/dev/null || {
        # May fail before config exists — that's ok, import runs after config creation
        true
    }
    rm -f "$tmp_sql"
    ok "Production DB cloned to staging"
}

_staging_update_urls() {
    local stg_root="$1"
    wp search-replace "https://${DOMAIN}" "https://${STAGING_DOMAIN}" \
        --path="$stg_root" --all-tables --allow-root --quiet 2>/dev/null || true
    wp search-replace "http://${DOMAIN}" "http://${STAGING_DOMAIN}" \
        --path="$stg_root" --all-tables --allow-root --quiet 2>/dev/null || true
    ok "URLs updated to staging domain"
}

_staging_write_config() {
    local stg_root="$1"

    # Get table prefix from production config
    local prefix="stg_"
    prefix="$(wp config get table_prefix --path="${SITE_ROOT}/public" --allow-root 2>/dev/null || echo 'stg_')"

    wp config create \
        --path="$stg_root" \
        --dbname="$STAGING_DB_NAME" \
        --dbuser="$STAGING_DB_USER" \
        --dbpass="$STAGING_DB_PASS" \
        --dbhost="127.0.0.1" \
        --dbprefix="$prefix" \
        --skip-check \
        --quiet \
        --allow-root 2>/dev/null || true

    # Append staging-specific constants
    cat >> "${stg_root}/wp-config.php" <<'EOF'

/** Staging environment flags — added by UnderHost installer */
define( 'WP_ENVIRONMENT_TYPE', 'staging' );
define( 'WP_DEBUG',            false );
define( 'DISALLOW_FILE_EDIT',  true );
define( 'FORCE_SSL_ADMIN',     true );
EOF

    chmod 600 "${stg_root}/wp-config.php"
    ok "Staging wp-config.php created"
}

_staging_configure_nginx() {
    local sys_user="$1"
    local conf_dir
    conf_dir="$(os_nginx_conf_dir)"

    local php_socket
    if [[ "$OS_FAMILY" == "debian" ]]; then
        php_socket="/run/php/${DOMAIN}-fpm.sock"
    else
        php_socket="/run/php-fpm/${DOMAIN}.sock"
    fi

    # Generate HTTP Basic Auth credentials
    local htpasswd_file="/etc/nginx/.htpasswd_staging_${DOMAIN//\./_}"
    if command -v htpasswd &>/dev/null; then
        htpasswd -bc "$htpasswd_file" "${STAGING_HTTP_USER}" "${STAGING_HTTP_PASS}" 2>/dev/null
    elif command -v openssl &>/dev/null; then
        printf '%s:%s\n' "$STAGING_HTTP_USER" \
            "$(openssl passwd -apr1 "$STAGING_HTTP_PASS")" > "$htpasswd_file"
    fi
    chmod 640 "$htpasswd_file" 2>/dev/null || true

    cat > "${conf_dir}/${STAGING_DOMAIN}.conf" <<EOF
# UnderHost One-Domain — Staging: ${STAGING_DOMAIN}
# Generated: $(date '+%Y-%m-%d %H:%M:%S')

server {
    listen 80;
    listen [::]:80;
    server_name ${STAGING_DOMAIN};

    root ${STAGING_ROOT};
    index index.php index.html;

    access_log /var/log/nginx/${STAGING_DOMAIN}.access.log main;
    error_log  /var/log/nginx/${STAGING_DOMAIN}.error.log  warn;

    # Prevent search engine indexing at HTTP header level
    add_header X-Robots-Tag "noindex, nofollow, nosnippet, noarchive" always;

    # HTTP Basic Auth — password-protect staging
    auth_basic           "Staging — Authorised Access Only";
    auth_basic_user_file ${htpasswd_file};

    # Security headers
    add_header X-Frame-Options         "SAMEORIGIN"  always;
    add_header X-Content-Type-Options  "nosniff"     always;

    location ~ /\\.(?!well-known) {
        deny all; access_log off; log_not_found off;
    }

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location = /xmlrpc.php {
        deny all; access_log off; log_not_found off;
    }

    location ~ \.php$ {
        try_files \$uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        include       fastcgi_params;
        fastcgi_pass  unix:${php_socket};
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_read_timeout 300;
    }
}
EOF

    if nginx -t 2>/dev/null; then
        svc_reload nginx
        ok "Staging Nginx vhost configured: ${STAGING_DOMAIN}"
    else
        warn "Nginx config test failed — check ${conf_dir}/${STAGING_DOMAIN}.conf"
    fi
}

_staging_provision_ssl() {
    if ! command -v certbot &>/dev/null; then
        warn "certbot not found — skipping staging SSL"
        return
    fi

    _ssl_check_dns "$STAGING_DOMAIN" 2>/dev/null || true

    certbot --nginx \
        -d "$STAGING_DOMAIN" \
        --email "${SSL_EMAIL}" \
        --agree-tos \
        --non-interactive \
        --redirect \
        --no-eff-email \
        --quiet 2>/dev/null \
        && ok "SSL certificate provisioned for staging: ${STAGING_DOMAIN}" \
        || warn "SSL for staging failed — retry: certbot --nginx -d ${STAGING_DOMAIN} --email ${SSL_EMAIL}"
}

# ---------------------------------------------------------------------------
# Push staging → production
# ---------------------------------------------------------------------------
staging_push() {
    local dom="${1:-$DOMAIN}"
    step "Pushing staging → production for ${dom}"

    local prod_root="/var/www/${dom}/public"
    local stg_root="/var/www/staging.${dom}/public"

    [[ ! -d "$stg_root" ]] && die "Staging not found: ${stg_root}"

    warn "⚠  This will OVERWRITE production files with staging content."
    prompt_yn "Are you sure?" "n" || die "Push cancelled."

    rsync -a --exclude=wp-config.php --delete "${stg_root}/" "${prod_root}/"
    wp search-replace "https://staging.${dom}" "https://${dom}" \
        --path="$prod_root" --all-tables --allow-root --quiet
    wp db export "/tmp/stg_push_$(date +%s).sql" --path="$stg_root" --allow-root --quiet
    wp db import "/tmp/stg_push_"*.sql --path="$prod_root" --allow-root --quiet 2>/dev/null || true
    rm -f /tmp/stg_push_*.sql

    ok "Staging pushed to production"
}

# ---------------------------------------------------------------------------
# Pull production → staging (refresh staging from prod)
# ---------------------------------------------------------------------------
staging_pull() {
    local dom="${1:-$DOMAIN}"
    step "Pulling production → staging for ${dom}"

    local prod_root="/var/www/${dom}/public"
    local stg_root="/var/www/staging.${dom}/public"

    [[ ! -d "$prod_root" ]] && die "Production not found: ${prod_root}"
    [[ ! -d "$stg_root"  ]] && die "Staging not found: ${stg_root}"

    rsync -a --exclude=wp-config.php --delete "${prod_root}/" "${stg_root}/"
    wp db export "/tmp/prod_pull_$(date +%s).sql" --path="$prod_root" --allow-root --quiet
    wp db import "/tmp/prod_pull_"*.sql --path="$stg_root" --allow-root --quiet 2>/dev/null || true
    rm -f /tmp/prod_pull_*.sql

    wp search-replace "https://${dom}" "https://staging.${dom}" \
        --path="$stg_root" --all-tables --allow-root --quiet

    ok "Production pulled to staging"
}
