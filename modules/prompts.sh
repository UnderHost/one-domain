#!/usr/bin/env bash
# =============================================================================
#  modules/prompts.sh — Interactive installation wizard
# =============================================================================

run_wizard() {
    section_banner "UnderHost Installation Wizard"
    echo -e "  Answer the questions below. Press ${YELLOW}Enter${RESET} to accept defaults.\n"

    # ── Domain ──────────────────────────────────────────────────────────────
    while true; do
        DOMAIN="$(prompt_text "Domain name" "${DOMAIN:-example.com}")"
        _validate_domain "$DOMAIN" 2>/dev/null && break
        warn "Invalid domain — enter a domain like example.com or sub.example.com"
    done

    # ── Mode ────────────────────────────────────────────────────────────────
    if [[ -z "$INSTALL_MODE" ]]; then
        INSTALL_MODE="$(prompt_select "What would you like to install?" \
            "wp   — WordPress + PHP stack" \
            "php  — Plain PHP website stack")"
        INSTALL_MODE="${INSTALL_MODE%% *}"
    fi

    # ── SSL email ────────────────────────────────────────────────────────────
    SSL_EMAIL="$(prompt_text "Email for SSL certificate (Let's Encrypt)" "admin@${DOMAIN}")"
    ADMIN_EMAIL="${ADMIN_EMAIL:-$SSL_EMAIL}"

    # ── PHP version ──────────────────────────────────────────────────────────
    PHP_VERSION="$(prompt_select "PHP version" "8.3" "8.4" "8.2" "8.1")"

    # ── Canonical www ────────────────────────────────────────────────────────
    prompt_yn "Use www.${DOMAIN} as canonical URL? (no = use ${DOMAIN})" "n" \
        && CANONICAL_WWW=true || CANONICAL_WWW=false

    if [[ "$BASIC_MODE" == true ]]; then
        _wizard_basic_defaults
    else
        _wizard_advanced
    fi

    _resolve_defaults
    echo
    ok "Configuration complete — review the plan below."
}

# ---------------------------------------------------------------------------
_wizard_basic_defaults() {
    # Sensible defaults for basic mode — skip most prompts
    ENABLE_DB=true
    ENABLE_REDIS=false
    ENABLE_FIREWALL=true
    ENABLE_FAIL2BAN=true
    FTP_MODE="sftp"
    ENABLE_PHPMYADMIN=false
    WP_HARDEN=true
    WP_AUTO_UPDATES=true
    WP_STAGING=false
    CONFIGURE_SWAP=true
    TUNE_SERVICES=true

    if [[ "$INSTALL_MODE" == "wp" ]]; then
        WP_TITLE="$(prompt_text "WordPress site title" "My Website")"
        WP_ADMIN_USER="$(prompt_text "WordPress admin username" "admin")"
        WP_ADMIN_EMAIL="$(prompt_text "WordPress admin email" "${SSL_EMAIL}")"
    fi
}

# ---------------------------------------------------------------------------
_wizard_advanced() {
    section_banner "Advanced Options"

    # Database
    prompt_yn "Create a MariaDB database?" "y" \
        && ENABLE_DB=true || ENABLE_DB=false

    # Redis
    prompt_yn "Enable Redis object cache?" "n" \
        && ENABLE_REDIS=true || ENABLE_REDIS=false

    # Firewall
    prompt_yn "Configure firewall (UFW/firewalld)?" "y" \
        && ENABLE_FIREWALL=true || ENABLE_FIREWALL=false

    # Fail2Ban
    prompt_yn "Install and configure Fail2Ban?" "y" \
        && ENABLE_FAIL2BAN=true || ENABLE_FAIL2BAN=false

    # File access
    local ftp_choice
    ftp_choice="$(prompt_select "File access method" \
        "sftp     — SFTP only (recommended)" \
        "ftp-tls  — FTP with TLS" \
        "none     — No file access user")"
    FTP_MODE="${ftp_choice%% *}"

    # phpMyAdmin
    if prompt_yn "Install phpMyAdmin? (security risk — not recommended)" "n"; then
        ENABLE_PHPMYADMIN=true
        security_warning "phpMyAdmin exposes your database to the internet." \
            "Restrict access by IP in Nginx after install." \
            "Never use on servers with weak MySQL credentials."
    fi

    # Performance tuning
    prompt_yn "Apply performance tuning (Nginx/PHP/MariaDB)?" "y" \
        && TUNE_SERVICES=true || TUNE_SERVICES=false

    # Swap
    prompt_yn "Create swap file if RAM < 2 GB?" "y" \
        && CONFIGURE_SWAP=true || CONFIGURE_SWAP=false

    # WordPress-specific
    if [[ "$INSTALL_MODE" == "wp" ]]; then
        _wizard_wordpress_options
    fi
}

# ---------------------------------------------------------------------------
_wizard_wordpress_options() {
    section_banner "WordPress Options"

    WP_TITLE="$(prompt_text "Site title" "My WordPress Site")"
    WP_ADMIN_USER="$(prompt_text "Admin username" "admin")"
    WP_ADMIN_EMAIL="$(prompt_text "Admin email" "${SSL_EMAIL}")"

    prompt_yn "Apply WordPress security hardening?" "y" \
        && WP_HARDEN=true || WP_HARDEN=false

    prompt_yn "Enable automatic minor/security updates?" "y" \
        && WP_AUTO_UPDATES=true || WP_AUTO_UPDATES=false

    if prompt_yn "Create a staging environment?" "n"; then
        WP_STAGING=true
        WP_STAGING_TYPE="$(prompt_select "Staging location" \
            "subdomain — staging.${DOMAIN}" \
            "subdir    — ${DOMAIN}/staging")"
        WP_STAGING_TYPE="${WP_STAGING_TYPE%% *}"
    fi

    if prompt_yn "Enable Redis object cache for WordPress?" "n"; then
        ENABLE_REDIS=true
        WP_REDIS=true
    fi
}
