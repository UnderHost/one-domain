#!/usr/bin/env bash
# =============================================================================
#  modules/ssl.sh — Let's Encrypt SSL provisioning via Certbot
# =============================================================================

ssl_provision() {
    step "Provisioning SSL certificate for ${DOMAIN}"

    # Ensure the webroot exists for ACME challenge
    mkdir -p /var/www/letsencrypt/.well-known/acme-challenge

    local san_args=("-d" "${DOMAIN}")
    # Only request www SAN if we're also serving www (it must resolve)
    san_args+=("-d" "www.${DOMAIN}")

    local cert_ok=false

    # Try the Nginx plugin first (handles all redirects automatically)
    if certbot --nginx \
            "${san_args[@]}" \
            --non-interactive \
            --agree-tos \
            --email "${SSL_EMAIL}" \
            --redirect \
            2>&1 | tee -a "${LOG_FILE}"; then
        cert_ok=true
        ok "SSL certificate obtained and Nginx updated"
    else
        # Fallback: webroot method
        warn "Nginx plugin failed. Trying webroot method..."
        if certbot certonly \
                --webroot -w /var/www/letsencrypt \
                "${san_args[@]}" \
                --non-interactive \
                --agree-tos \
                --email "${SSL_EMAIL}" \
                2>&1 | tee -a "${LOG_FILE}"; then
            cert_ok=true
            _ssl_patch_vhost
            ok "SSL certificate obtained via webroot"
        fi
    fi

    if [[ "$cert_ok" == false ]]; then
        warn "Could not obtain SSL certificate. This may be because:"
        warn "  • DNS for ${DOMAIN} does not yet point to this server"
        warn "  • Port 80 is blocked by an upstream firewall"
        warn "  • www.${DOMAIN} is not configured in DNS"
        warn "Run manually later: certbot --nginx -d ${DOMAIN} -d www.${DOMAIN}"
        return
    fi

    _ssl_configure_renewal
    _ssl_harden_nginx_ssl
}

# ---------------------------------------------------------------------------
# Manually patch the vhost to use the certificate (webroot fallback)
# ---------------------------------------------------------------------------
_ssl_patch_vhost() {
    local cert_path="/etc/letsencrypt/live/${DOMAIN}"
    [[ -d "$cert_path" ]] || return

    local vhost_file="/etc/nginx/conf.d/${DOMAIN}.conf"
    [[ -f "$vhost_file" ]] || return

    # Append an HTTPS server block to the existing HTTP-only vhost
    cat >> "${vhost_file}" <<SSL_BLOCK

server {
    listen      443 ssl http2;
    listen      [::]:443 ssl http2;
    server_name ${DOMAIN} www.${DOMAIN};
    root        ${SITE_ROOT};
    index       index.php index.html;

    ssl_certificate     ${cert_path}/fullchain.pem;
    ssl_certificate_key ${cert_path}/privkey.pem;
    include             /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam         /etc/letsencrypt/ssl-dhparams.pem;

    include /etc/nginx/conf.d/${DOMAIN}-locations.conf;
}
SSL_BLOCK

    nginx -t 2>/dev/null && systemctl reload nginx
}

# ---------------------------------------------------------------------------
_ssl_harden_nginx_ssl() {
    # Write a global SSL hardening snippet
    cat > /etc/nginx/snippets/uh-ssl.conf <<'SSLCFG'
# UnderHost SSL hardening snippet
ssl_protocols       TLSv1.2 TLSv1.3;
ssl_ciphers         ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
ssl_prefer_server_ciphers off;
ssl_session_cache   shared:SSL:10m;
ssl_session_timeout 1d;
ssl_session_tickets off;
ssl_stapling        on;
ssl_stapling_verify on;
resolver 1.1.1.1 8.8.8.8 valid=300s;
resolver_timeout    5s;
SSLCFG

    mkdir -p /etc/nginx/snippets
    ok "SSL hardening snippet written to /etc/nginx/snippets/uh-ssl.conf"
}

# ---------------------------------------------------------------------------
_ssl_configure_renewal() {
    # Certbot installs a systemd timer or cron automatically on most systems.
    # We add a deploy hook to reload Nginx after renewal.
    mkdir -p /etc/letsencrypt/renewal-hooks/deploy
    cat > /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh <<'HOOK'
#!/bin/bash
systemctl reload nginx
HOOK
    chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
    ok "SSL auto-renewal hook configured"
}
