#!/usr/bin/env bash
# =============================================================================
#  UnderHost One-Domain — Nginx Module
#  modules/nginx.sh
# =============================================================================

[[ -n "${_UH_NGINX_LOADED:-}" ]] && return 0
_UH_NGINX_LOADED=1

nginx_configure_vhost() {
    step "Configuring Nginx vhost for ${DOMAIN}"

    local conf_dir
    conf_dir="$(os_nginx_conf_dir)"
    local vhost_file="${conf_dir}/${DOMAIN}.conf"
    local webroot="${SITE_ROOT}/public"
    local php_socket="/run/php/${DOMAIN}-fpm.sock"

    # AlmaLinux/RHEL socket path
    [[ "$OS_FAMILY" == "rhel" ]] && php_socket="/run/php-fpm/${DOMAIN}.sock"

    # Create document root
    mkdir -p "$webroot"

    # Nginx global hardening (server_tokens, etc.) — only applied once
    _nginx_global_hardening

    # Write HTTP vhost (will be replaced with HTTPS after certbot)
    cat > "$vhost_file" <<EOF
# UnderHost One-Domain — ${DOMAIN}
# Generated: $(date '+%Y-%m-%d %H:%M:%S')

server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN}$(${CANONICAL_WWW} && echo " www.${DOMAIN}" || echo "");

    root ${webroot};
    index index.php index.html;

    # Redirect HTTP → HTTPS after SSL provisioning
    # (certbot will modify this block automatically)

    access_log  /var/log/nginx/${DOMAIN}.access.log  main;
    error_log   /var/log/nginx/${DOMAIN}.error.log   warn;

    # Security headers
    add_header X-Frame-Options           "SAMEORIGIN"           always;
    add_header X-Content-Type-Options    "nosniff"              always;
    add_header X-XSS-Protection          "1; mode=block"        always;
    add_header Referrer-Policy           "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy        "geolocation=(), microphone=(), camera=()" always;

    # Block sensitive files
    location ~ /\.(?!well-known) {
        deny all;
        access_log off;
        log_not_found off;
    }
    location ~ /\.(env|git|svn|htpasswd|DS_Store) {
        deny all;
        access_log off;
        log_not_found off;
    }
    location = /wp-login.php {
        # Fail2Ban watches this — keep it accessible but logged
        limit_req zone=login burst=5 nodelay;
        include fastcgi_params;
        fastcgi_pass  unix:${php_socket};
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }

$(if [[ "$INSTALL_MODE" == "wp" ]]; then
cat <<'WPEOF'
    # WordPress rules
    location / {
        try_files $uri $uri/ /index.php?$args;
    }
    location = /xmlrpc.php {
        deny all;
        access_log off;
        log_not_found off;
    }
    location ~* /wp-content/uploads/.*\.php$ {
        deny all;
    }
WPEOF
else
cat <<'PHPEOF'
    location / {
        try_files $uri $uri/ =404;
    }
PHPEOF
fi)

    location ~ \.php$ {
        try_files \$uri =404;
        fastcgi_split_path_info ^(.+\.php)(/.+)$;
        include       fastcgi_params;
        fastcgi_pass  unix:${php_socket};
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PHP_VALUE        "upload_max_filesize=64M \n post_max_size=64M";
        fastcgi_read_timeout 300;
        fastcgi_buffers 16 16k;
        fastcgi_buffer_size 32k;
    }

    # Static asset caching
    location ~* \.(jpg|jpeg|gif|png|webp|svg|ico|css|js|woff2?|ttf|otf|eot)$ {
        expires     30d;
        add_header  Cache-Control "public, no-transform";
        access_log  off;
    }

    # Gzip
    gzip              on;
    gzip_vary         on;
    gzip_proxied      any;
    gzip_comp_level   5;
    gzip_types        text/plain text/css application/json application/javascript
                      text/xml application/xml application/xml+rss text/javascript
                      image/svg+xml application/x-font-ttf font/opentype;
}
EOF

    # Rate-limiting zone (defined in http context — ensure it's in nginx.conf)
    _nginx_ensure_rate_limit_zone

    # Validate config
    if nginx -t 2>/dev/null; then
        ok "Nginx vhost written: ${vhost_file}"
    else
        nginx -t 2>&1 | while IFS= read -r line; do warn "$line"; done
        die "Nginx configuration test failed — check ${vhost_file}"
    fi
}

_nginx_global_hardening() {
    local nginx_conf="/etc/nginx/nginx.conf"
    [[ ! -f "$nginx_conf" ]] && return

    # server_tokens off
    if ! grep -q 'server_tokens off' "$nginx_conf"; then
        sed -i '/http {/a\\    server_tokens off;' "$nginx_conf" 2>/dev/null || true
    fi

    # Ensure there's a logs format called 'main' (nginx.org packages have it; distro packages may not)
    if ! grep -q 'log_format.*main' "$nginx_conf"; then
        sed -i '/http {/a\\    log_format  main  '"'"'$remote_addr - $remote_user [$time_local] "$request" '"'"'\n'"'"'                    $status $body_bytes_sent "$http_referer" '"'"'\n'"'"'                    "$http_user_agent" "$http_x_forwarded_for"'"'"';' "$nginx_conf" 2>/dev/null || true
    fi
}

_nginx_ensure_rate_limit_zone() {
    local nginx_conf="/etc/nginx/nginx.conf"
    [[ ! -f "$nginx_conf" ]] && return
    if ! grep -q 'limit_req_zone' "$nginx_conf"; then
        sed -i '/http {/a\\    limit_req_zone $binary_remote_addr zone=login:10m rate=5r\/m;' \
            "$nginx_conf" 2>/dev/null || true
    fi
}

# Called from ssl.sh after certbot runs to reload nginx
nginx_reload() {
    nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null && ok "Nginx reloaded"
}
