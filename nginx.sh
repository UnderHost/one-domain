#!/usr/bin/env bash
# =============================================================================
#  modules/nginx.sh — Virtual host configuration for PHP and WordPress
# =============================================================================

nginx_configure_vhost() {
    step "Configuring Nginx virtual host for ${DOMAIN}"

    os_php_fpm_sock  # ensures PHP_FPM_SOCK is set

    mkdir -p "${SITE_ROOT}"
    chown root:root "${SITE_ROOT}"
    chmod 755 "${SITE_ROOT}"

    local canonical_server_name
    if [[ "$CANONICAL_WWW" == true ]]; then
        canonical_server_name="www.${DOMAIN}"
    else
        canonical_server_name="${DOMAIN}"
    fi

    local vhost_file="/etc/nginx/conf.d/${DOMAIN}.conf"
    mkdir -p /etc/nginx/conf.d

    if [[ "$INSTALL_MODE" == "wp" ]]; then
        _nginx_wp_vhost "$canonical_server_name" "$vhost_file"
    else
        _nginx_php_vhost "$canonical_server_name" "$vhost_file"
    fi

    # Validate config
    nginx -t 2>/dev/null || die "Nginx configuration test failed. Check ${vhost_file}."
    systemctl reload nginx
    ok "Nginx virtual host configured: ${vhost_file}"

    # Create a placeholder index if site root is empty
    if [[ ! -f "${SITE_ROOT}/index.php" && ! -f "${SITE_ROOT}/index.html" ]]; then
        _nginx_create_placeholder
    fi
}

# ---------------------------------------------------------------------------
_nginx_security_headers() {
    cat <<'HEADERS'
    # Security headers
    add_header X-Frame-Options          "SAMEORIGIN"                            always;
    add_header X-Content-Type-Options   "nosniff"                               always;
    add_header X-XSS-Protection         "1; mode=block"                         always;
    add_header Referrer-Policy          "strict-origin-when-cross-origin"       always;
    add_header Permissions-Policy       "geolocation=(), microphone=(), camera=()" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains"  always;
HEADERS
}

# ---------------------------------------------------------------------------
_nginx_static_cache() {
    cat <<'CACHE'
    # Static asset caching
    location ~* \.(jpg|jpeg|png|gif|ico|svg|webp|avif|css|js|woff|woff2|ttf|eot|pdf|txt)$ {
        expires     1y;
        access_log  off;
        add_header  Cache-Control "public, immutable";
    }
CACHE
}

# ---------------------------------------------------------------------------
_nginx_php_location() {
    cat <<PHP_LOC
    # PHP processing
    location ~ \.php$ {
        try_files \$uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)\$;
        fastcgi_pass  unix:${PHP_FPM_SOCK};
        fastcgi_index index.php;
        include       fastcgi_params;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO       \$fastcgi_path_info;
        fastcgi_read_timeout          300;
        fastcgi_buffers               16 16k;
        fastcgi_buffer_size           32k;
    }
PHP_LOC
}

# ---------------------------------------------------------------------------
_nginx_deny_hidden() {
    cat <<'DENY'
    # Deny access to dotfiles
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }
DENY
}

# ---------------------------------------------------------------------------
_nginx_gzip() {
    cat <<'GZIP'
    # Compression
    gzip              on;
    gzip_vary         on;
    gzip_comp_level   5;
    gzip_min_length   1024;
    gzip_proxied      any;
    gzip_types
        text/plain text/css text/xml text/javascript
        application/json application/javascript application/xml+rss
        application/vnd.ms-fontobject font/opentype image/svg+xml;
GZIP
}

# ---------------------------------------------------------------------------
_nginx_php_vhost() {
    local server_name="$1"
    local vhost_file="$2"

    cat > "${vhost_file}" <<VHOST
# UnderHost — PHP vhost for ${DOMAIN}
# Generated $(date)

server {
    listen      80;
    listen      [::]:80;
    server_name ${DOMAIN} www.${DOMAIN};
    root        ${SITE_ROOT};
    index       index.php index.html;

$(_nginx_gzip)

$(_nginx_security_headers)

    # Canonical redirect
$(
if [[ "$CANONICAL_WWW" == true ]]; then
echo "    if (\$host = '${DOMAIN}') { return 301 https://www.${DOMAIN}\$request_uri; }"
else
echo "    if (\$host = 'www.${DOMAIN}') { return 301 https://${DOMAIN}\$request_uri; }"
fi
)

    # Certbot well-known
    location /.well-known/acme-challenge/ {
        root /var/www/letsencrypt;
    }

    # Try files
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

$(_nginx_static_cache)
$(_nginx_php_location)
$(_nginx_deny_hidden)

    # Deny access to sensitive files
    location ~* \.(env|log|ini|sql|bak|conf|htpasswd)$ {
        deny all;
    }
}
VHOST
}

# ---------------------------------------------------------------------------
_nginx_wp_vhost() {
    local server_name="$1"
    local vhost_file="$2"

    cat > "${vhost_file}" <<WPVHOST
# UnderHost — WordPress vhost for ${DOMAIN}
# Generated $(date)

# FastCGI cache zone (defined once globally)
# Add to /etc/nginx/nginx.conf http block if not present:
#   fastcgi_cache_path /tmp/nginx_cache levels=1:2
#       keys_zone=WORDPRESS:100m inactive=60m max_size=1g;

server {
    listen      80;
    listen      [::]:80;
    server_name ${DOMAIN} www.${DOMAIN};
    root        ${SITE_ROOT};
    index       index.php index.html;

$(_nginx_gzip)

$(_nginx_security_headers)

    # Canonical redirect
$(
if [[ "$CANONICAL_WWW" == true ]]; then
echo "    if (\$host = '${DOMAIN}') { return 301 https://www.${DOMAIN}\$request_uri; }"
else
echo "    if (\$host = 'www.${DOMAIN}') { return 301 https://${DOMAIN}\$request_uri; }"
fi
)

    # Certbot well-known
    location /.well-known/acme-challenge/ {
        root /var/www/letsencrypt;
    }

    # WordPress-specific: block xmlrpc if not needed
    location = /xmlrpc.php {
        deny all;
        access_log off;
        log_not_found off;
    }

    # WordPress: try files with PHP fallback
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    # WordPress: block direct access to wp-config and sensitive files
    location ~* (wp-config\.php|wp-settings\.php|readme\.html|license\.txt)$ {
        deny all;
    }

    # WordPress: block PHP in uploads/includes
    location ~* /(?:uploads|files|wp-content/uploads)/.*\.php$ {
        deny all;
    }

$(_nginx_static_cache)
$(_nginx_php_location)
$(_nginx_deny_hidden)

    # Deny sensitive file types
    location ~* \.(env|log|ini|sql|bak|conf|htpasswd)$ {
        deny all;
    }
}
WPVHOST
}

# ---------------------------------------------------------------------------
_nginx_create_placeholder() {
    local site_user="${DOMAIN//./_}"
    site_user="${site_user:0:32}"

    cat > "${SITE_ROOT}/index.php" <<'PLACEHOLDER'
<?php
// UnderHost — placeholder page (remove after uploading your site)
?>
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Site Ready</title>
  <style>
    body { font-family: system-ui, sans-serif; background: #0f172a; color: #e2e8f0;
           display: flex; justify-content: center; align-items: center; min-height: 100vh; margin: 0; }
    .card { text-align: center; padding: 2rem; }
    h1 { font-size: 2rem; margin-bottom: .5rem; }
    p  { color: #94a3b8; }
    a  { color: #38bdf8; }
  </style>
</head>
<body>
  <div class="card">
    <h1>✅ Server Ready</h1>
    <p>Upload your website files to replace this page.</p>
    <p><a href="https://underhost.com" target="_blank" rel="noopener">UnderHost.com</a></p>
    <p style="font-size:.75rem;color:#475569"><?php echo phpversion(); ?></p>
  </div>
</body>
</html>
PLACEHOLDER

    chown "${site_user}:${site_user}" "${SITE_ROOT}/index.php" 2>/dev/null || true
    ok "Placeholder index.php created at ${SITE_ROOT}"
}
