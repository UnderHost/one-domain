#!/usr/bin/env bash
# =============================================================================
#  UnderHost One-Domain — SSL Module
#  modules/ssl.sh
# =============================================================================

[[ -n "${_UH_SSL_LOADED:-}" ]] && return 0
_UH_SSL_LOADED=1

ssl_provision() {
    step "Provisioning SSL certificate for ${DOMAIN}"

    if ! command -v certbot &>/dev/null; then
        die "certbot not found — install it via pkg_install_stack first"
    fi

    # Verify DNS resolves to this server before requesting cert
    _ssl_check_dns "$DOMAIN"

    local domains="-d ${DOMAIN}"
    if [[ "${CANONICAL_WWW:-false}" == true ]]; then
        _ssl_check_dns "www.${DOMAIN}" || warn "www.${DOMAIN} DNS not resolving — skipping www"
        domains="${domains} -d www.${DOMAIN}"
    fi

    # Request cert via Nginx plugin
    certbot --nginx \
        $domains \
        --email "${SSL_EMAIL}" \
        --agree-tos \
        --non-interactive \
        --redirect \
        --hsts \
        --staple-ocsp \
        --no-eff-email \
        2>&1 | while IFS= read -r line; do
            log_msg "certbot: ${line}"
            # Surface errors to console
            [[ "$line" =~ [Ee]rror|[Ff]ailed|[Cc]hallenge ]] && warn "certbot: ${line}"
        done

    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        warn "Certbot exited with an error. Check log: ${LOG_FILE}"
        warn "DNS must point to this server before SSL provisioning."
        warn "To retry manually:  certbot --nginx ${domains} --email ${SSL_EMAIL}"
        return 1
    fi

    # Post-certbot: harden the SSL configuration added by certbot
    _ssl_harden_nginx_block

    # Install deploy hook for automatic Nginx reload after renewal
    _ssl_install_deploy_hook

    # Verify renewal works in dry-run
    if certbot renew --dry-run --quiet 2>/dev/null; then
        ok "SSL auto-renewal dry-run passed"
    else
        warn "SSL dry-run renewal failed — check: certbot renew --dry-run"
    fi

    ok "SSL certificate provisioned for ${DOMAIN}"
}

# ---------------------------------------------------------------------------
# DNS pre-check — warns but does not abort (DNS propagation may be partial)
# ---------------------------------------------------------------------------
_ssl_check_dns() {
    local dom="$1"
    local server_ip
    server_ip="$(curl -4 -fsSL --max-time 5 https://api.ipify.org 2>/dev/null || true)"

    if [[ -z "$server_ip" ]]; then
        warn "Could not determine server public IP — skipping DNS pre-check for ${dom}"
        return 0
    fi

    local dns_ip
    dns_ip="$(dig +short "${dom}" @8.8.8.8 2>/dev/null | tail -1)"

    if [[ -z "$dns_ip" ]]; then
        warn "DNS: ${dom} does not resolve — certbot will likely fail"
        warn "Point your DNS A record to ${server_ip} and wait for propagation"
    elif [[ "$dns_ip" != "$server_ip" ]]; then
        warn "DNS mismatch for ${dom}:"
        warn "  DNS resolves to: ${dns_ip}"
        warn "  This server is:  ${server_ip}"
        warn "Certbot may fail if DNS has not propagated yet."
    else
        ok "DNS check passed: ${dom} → ${server_ip}"
    fi
}

# ---------------------------------------------------------------------------
# Harden the SSL nginx block that certbot creates
# Enforces TLS 1.2/1.3 only, disables session tickets, adds HSTS header
# ---------------------------------------------------------------------------
_ssl_harden_nginx_block() {
    local conf_dir
    conf_dir="$(os_nginx_conf_dir)"
    local vhost="${conf_dir}/${DOMAIN}.conf"

    [[ ! -f "$vhost" ]] && return

    # Ensure TLS 1.2+ only (certbot may leave 1.0/1.1 in older configs)
    if grep -q 'ssl_protocols' "$vhost"; then
        sed -i 's/ssl_protocols.*/ssl_protocols TLSv1.2 TLSv1.3;/' "$vhost"
    fi

    # Disable TLS session tickets (forward secrecy)
    if ! grep -q 'ssl_session_tickets' "$vhost"; then
        sed -i '/ssl_protocols/a\    ssl_session_tickets off;' "$vhost"
    fi

    # Strong ciphers
    if grep -q 'ssl_ciphers' "$vhost"; then
        sed -i "s|ssl_ciphers.*|ssl_ciphers 'ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256';|" "$vhost"
    else
        sed -i '/ssl_protocols/a\    ssl_ciphers '"'"'ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305'"'"';' "$vhost"
    fi

    # HSTS (long duration — ensure SSL is stable before deploying)
    if ! grep -q 'Strict-Transport-Security' "$vhost"; then
        sed -i '/ssl_protocols/a\    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;' "$vhost"
    fi

    # Validate
    nginx -t 2>/dev/null && svc_reload nginx && ok "SSL configuration hardened"
}

# ---------------------------------------------------------------------------
# Deploy hook — reload Nginx after each auto-renewal
# ---------------------------------------------------------------------------
_ssl_install_deploy_hook() {
    local hook_dir="/etc/letsencrypt/renewal-hooks/deploy"
    local hook_file="${hook_dir}/reload-nginx.sh"

    mkdir -p "$hook_dir"

    cat > "$hook_file" <<'EOF'
#!/usr/bin/env bash
# UnderHost — Reload Nginx after Let's Encrypt cert renewal
set -euo pipefail
nginx -t && systemctl reload nginx
EOF
    chmod 755 "$hook_file"
    ok "Certbot deploy hook installed: ${hook_file}"
}

# ---------------------------------------------------------------------------
# Dry-run renewal test (used by: install ssl-renew-test domain)
# ---------------------------------------------------------------------------
ssl_renew_test() {
    local dom="${1:-$DOMAIN}"
    step "SSL renewal dry-run for ${dom}"
    certbot renew --dry-run --cert-name "${dom}" 2>&1 \
        | while IFS= read -r line; do info "$line"; done
}
