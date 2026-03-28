#!/usr/bin/env bash
# =============================================================================
#  modules/ssl.sh — SSL certificate provisioning via Certbot
# =============================================================================

ssl_provision() {
    step "Provisioning SSL certificate for ${DOMAIN}"

    command -v certbot &>/dev/null || {
        warn "certbot not installed — installing"
        case "$PKG_MGR" in
            apt) DEBIAN_FRONTEND=noninteractive apt-get install -y -q certbot python3-certbot-nginx &>/dev/null ;;
            dnf) dnf install -y certbot python3-certbot-nginx &>/dev/null ;;
        esac
    }

    # Create webroot for ACME challenges (certbot --nginx manages this itself,
    # but we keep the dir for webroot fallback)
    mkdir -p /var/www/letsencrypt/.well-known/acme-challenge

    # Check DNS resolves to this server before trying to get cert
    _ssl_check_dns

    # Request certificate
    local certbot_domains=(-d "${DOMAIN}" -d "www.${DOMAIN}")
    [[ "${WP_STAGING:-false}" == true && -n "${STAGING_DOMAIN:-}" ]] \
        && certbot_domains+=(-d "${STAGING_DOMAIN}")

    if certbot --nginx \
            "${certbot_domains[@]}" \
            --non-interactive \
            --agree-tos \
            --email "${SSL_EMAIL}" \
            --redirect \
            2>&1 | tee -a "${LOG_FILE}"; then
        ok "SSL certificate obtained for ${DOMAIN}"
        _ssl_enable_renewal_timer
    else
        warn "certbot failed — possible causes:"
        warn "  • DNS for ${DOMAIN} not pointing to this server"
        warn "  • Port 80 not reachable from the internet"
        warn "  • Rate limit hit (5 certs per domain per week)"
        warn "Retry manually: certbot --nginx -d ${DOMAIN} -d www.${DOMAIN} --email ${SSL_EMAIL}"
    fi
}

# ---------------------------------------------------------------------------
ssl_renew_test() {
    local domain="${1:-$DOMAIN}"
    step "Testing SSL renewal for ${domain}"
    certbot renew --dry-run --cert-name "${domain}" 2>&1 \
        && ok "SSL renewal test passed" \
        || warn "SSL renewal test failed — check certbot config"
}

# ---------------------------------------------------------------------------
_ssl_check_dns() {
    local server_ip
    server_ip="$(curl -sf --max-time 5 https://api.ipify.org 2>/dev/null \
              || hostname -I 2>/dev/null | awk '{print $1}')"

    local resolved_ip
    resolved_ip="$(dig +short "${DOMAIN}" A 2>/dev/null | tail -1 \
               || host "${DOMAIN}" 2>/dev/null | awk '/has address/{print $NF}' | head -1 \
               || echo "")"

    if [[ -z "$resolved_ip" ]]; then
        warn "DNS for ${DOMAIN} is not resolving yet."
        warn "SSL certificate request may fail. Continuing anyway..."
    elif [[ "$resolved_ip" != "$server_ip" ]]; then
        info "DNS for ${DOMAIN} → ${resolved_ip} (this server: ${server_ip})"
        info "Looks like CDN/proxy — SSL may still work if proxied correctly."
    else
        ok "DNS for ${DOMAIN} resolves to this server (${server_ip})"
    fi
}

# ---------------------------------------------------------------------------
_ssl_enable_renewal_timer() {
    # Prefer systemd timer over cron
    if systemctl list-unit-files certbot.timer &>/dev/null; then
        systemctl enable --now certbot.timer 2>/dev/null \
            && ok "certbot.timer enabled (automatic renewal)"
        return
    fi

    if systemctl list-unit-files snap.certbot.renew.timer &>/dev/null; then
        systemctl enable --now snap.certbot.renew.timer 2>/dev/null \
            && ok "snap certbot renewal timer enabled"
        return
    fi

    # Fallback: add cron job
    if ! crontab -l 2>/dev/null | grep -q "certbot renew"; then
        (crontab -l 2>/dev/null; \
            echo "0 3 * * * certbot renew --quiet --post-hook 'systemctl reload nginx' 2>/dev/null") \
            | crontab -
        ok "certbot renewal cron job added (daily at 03:00)"
    fi
}
