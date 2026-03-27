#!/usr/bin/env bash
# =============================================================================
#  modules/prompts.sh — Interactive installation wizard
# =============================================================================

run_wizard() {
    clear
    _wizard_banner

    section_banner "Step 1 · System & Domain"
    _wizard_os_confirm
    _wizard_domain
    _wizard_mode

    section_banner "Step 2 · Web Stack"
    _wizard_php_version
    _wizard_canonical
    _wizard_ssl_email

    section_banner "Step 3 · Services"
    _wizard_database
    _wizard_redis
    _wizard_firewall
    _wizard_fail2ban

    if [[ "$INSTALL_MODE" == "wp" ]]; then
        section_banner "Step 4 · WordPress"
        _wizard_wordpress
        section_banner "Step 5 · Staging"
        _wizard_staging
    fi

    if [[ "$BASIC_MODE" == false ]]; then
        section_banner "Step 6 · File Access (FTP/SFTP)"
        _wizard_ftp

        section_banner "Step 7 · Optional Tools"
        _wizard_optional_tools

        section_banner "Step 8 · Performance"
        _wizard_performance
    fi

    # Resolve all defaults now that wizard is done
    _resolve_defaults
    _wizard_confirm_summary
}

# ---------------------------------------------------------------------------
_wizard_banner() {
    echo -e "${BOLD}${BLUE}"
    cat <<'EOF'
  ╔═══════════════════════════════════════════════════════════════╗
  ║                                                               ║
  ║          UnderHost One-Domain Installer  2026                 ║
  ║          https://underhost.com                                ║
  ║                                                               ║
  ╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${RESET}"
    echo -e "  Welcome! This wizard will guide you through deploying a"
    echo -e "  production-ready web server for a single domain.\n"

    if prompt_yn "Use basic mode? (asks only essential questions)" "n"; then
        BASIC_MODE=true
        info "Basic mode selected — using recommended defaults for advanced options."
    fi
}

# ---------------------------------------------------------------------------
_wizard_os_confirm() {
    os_detect
    os_validate_support
    echo
    info "OS detected: ${BOLD}${OS_ID} ${OS_VERSION}${RESET}"
    prompt_yn "Continue with this OS?" "y" || die "Aborted by user."
}

# ---------------------------------------------------------------------------
_wizard_domain() {
    while true; do
        DOMAIN="$(prompt_text "Target domain" "${DOMAIN}")"
        _validate_domain "$DOMAIN" 2>/dev/null && break
        warn "Invalid domain format. Example: example.com or sub.example.com"
    done
}

# ---------------------------------------------------------------------------
_wizard_mode() {
    if [[ -z "$INSTALL_MODE" ]]; then
        local choice
        choice="$(prompt_select "What do you want to install?" "PHP website stack" "WordPress site")"
        case "$choice" in
            "PHP website stack") INSTALL_MODE="php" ;;
            "WordPress site")    INSTALL_MODE="wp"  ;;
        esac
    fi
    ok "Install mode: ${INSTALL_MODE^^}"
}

# ---------------------------------------------------------------------------
_wizard_php_version() {
    local versions=("8.3" "8.4")
    local choice
    choice="$(prompt_select "PHP version?" "${versions[@]}")"
    PHP_VERSION="$choice"
    ok "PHP ${PHP_VERSION}"
}

# ---------------------------------------------------------------------------
_wizard_canonical() {
    if prompt_yn "Use www.${DOMAIN} as the canonical domain? (non-www redirects to www)" "n"; then
        CANONICAL_WWW=true
    fi
}

# ---------------------------------------------------------------------------
_wizard_ssl_email() {
    SSL_EMAIL="$(prompt_text "Email address for Let's Encrypt SSL notices" "admin@${DOMAIN}")"
    ADMIN_EMAIL="${SSL_EMAIL}"
}

# ---------------------------------------------------------------------------
_wizard_database() {
    if prompt_yn "Create a database for this site?" "y"; then
        ENABLE_DB=true
        info "A database and random credentials will be created automatically."
        if prompt_yn "Customise database credentials?" "n"; then
            DB_NAME="$(prompt_text "Database name" "${DOMAIN//./_}_db")"
            DB_USER="$(prompt_text "Database username" "${DOMAIN//./_}_usr")"
            local p
            p="$(prompt_pass "Database password (leave blank to auto-generate)")"
            [[ -n "$p" ]] && DB_PASS="$p"
        fi
    else
        ENABLE_DB=false
    fi
}

# ---------------------------------------------------------------------------
_wizard_redis() {
    if prompt_yn "Enable Redis object cache?" "n"; then
        ENABLE_REDIS=true
    fi
}

# ---------------------------------------------------------------------------
_wizard_firewall() {
    if prompt_yn "Configure firewall (recommended)?" "y"; then
        ENABLE_FIREWALL=true
    else
        warn "Firewall will NOT be configured. Ensure your server is protected."
        ENABLE_FIREWALL=false
    fi
}

# ---------------------------------------------------------------------------
_wizard_fail2ban() {
    if prompt_yn "Install Fail2Ban (brute-force protection)?" "y"; then
        ENABLE_FAIL2BAN=true
    else
        ENABLE_FAIL2BAN=false
    fi
}

# ---------------------------------------------------------------------------
_wizard_wordpress() {
    WP_TITLE="$(prompt_text "WordPress site title" "My WordPress Site")"
    WP_ADMIN_USER="$(prompt_text "WordPress admin username" "admin")"

    local p
    p="$(prompt_pass "WordPress admin password (blank = auto-generate)")"
    [[ -n "$p" ]] && WP_ADMIN_PASS="$p"

    WP_ADMIN_EMAIL="$(prompt_text "WordPress admin email" "${ADMIN_EMAIL:-admin@${DOMAIN}}")"

    if prompt_yn "Enable Redis object cache for WordPress?" "n"; then
        WP_REDIS=true
        ENABLE_REDIS=true
    fi

    if prompt_yn "Apply WordPress security hardening?" "y"; then
        WP_HARDEN=true
    fi

    if prompt_yn "Enable automatic WordPress minor/security updates?" "y"; then
        WP_AUTO_UPDATES=true
    fi

    if [[ "$BASIC_MODE" == false ]]; then
        if prompt_yn "Install WP-CLI?" "y"; then
            ENABLE_WPCLI=true
        fi
    fi
}

# ---------------------------------------------------------------------------
_wizard_staging() {
    if prompt_yn "Create a staging environment for WordPress?" "n"; then
        WP_STAGING=true

        local stype
        stype="$(prompt_select "Staging location?" \
            "staging.${DOMAIN} (subdomain — recommended)" \
            "${DOMAIN}/staging (subdirectory)")"
        case "$stype" in
            *subdomain*) WP_STAGING_TYPE="subdomain" ;;
            *)           WP_STAGING_TYPE="subdir"    ;;
        esac
        info "Staging will be noindex'd and password-protected."
    else
        WP_STAGING=false
    fi
}

# ---------------------------------------------------------------------------
_wizard_ftp() {
    echo
    echo -e "  How should file access be provided for ${BOLD}${DOMAIN}${RESET}?"
    local choice
    choice="$(prompt_select "File access method:" \
        "SFTP only (recommended — uses SSH, no extra setup)" \
        "FTP with TLS (encrypted FTP)" \
        "No FTP or SFTP setup")"

    case "$choice" in
        "SFTP only"*)
            FTP_MODE="sftp"
            info "SFTP will be configured. Users connect via SSH credentials."
            ;;
        "FTP with TLS"*)
            security_warning \
                "FTP transmits credentials over the network." \
                "FTP with TLS (FTPS) encrypts the session but is more complex" \
                "to configure and less recommended than SFTP." \
                "Only proceed if your client software requires FTP."
            if prompt_yn "Proceed with FTP+TLS anyway?" "n"; then
                FTP_MODE="ftp-tls"
            else
                FTP_MODE="sftp"
                info "Falling back to SFTP."
            fi
            ;;
        *)
            FTP_MODE="none"
            ;;
    esac
}

# ---------------------------------------------------------------------------
_wizard_optional_tools() {
    if [[ "$INSTALL_MODE" == "php" ]]; then
        if prompt_yn "Install Composer?" "n"; then
            ENABLE_COMPOSER=true
        fi
    fi

    if prompt_yn "Install image optimisation packages (jpegoptim, optipng, webp)?" "n"; then
        ENABLE_IMGOPT=true
    fi

    if [[ "$INSTALL_MODE" == "wp" || "$ENABLE_DB" == true ]]; then
        if prompt_yn "Install phpMyAdmin? (security warning applies)" "n"; then
            security_warning \
                "Exposing phpMyAdmin publicly significantly increases attack surface." \
                "Ensure it is protected by HTTP auth or IP allowlist after install." \
                "Consider using a local tunnel instead of public access."
            if prompt_yn "Understood. Install phpMyAdmin?" "n"; then
                ENABLE_PHPMYADMIN=true
            fi
        fi
    fi
}

# ---------------------------------------------------------------------------
_wizard_performance() {
    local ram
    ram="$(get_total_ram_mb)"
    info "Server RAM: ${ram}MB"

    if (( ram < 2048 )); then
        if prompt_yn "Configure swap space? (recommended for low-RAM servers)" "y"; then
            CONFIGURE_SWAP=true
        fi
    fi

    if prompt_yn "Auto-tune services based on available RAM and CPU?" "y"; then
        TUNE_SERVICES=true
    fi
}

# ---------------------------------------------------------------------------
_wizard_confirm_summary() {
    section_banner "Installation Summary"
    echo
    printf "  %-24s %s\n" "Domain:"       "${DOMAIN}"
    printf "  %-24s %s\n" "Mode:"         "${INSTALL_MODE^^}"
    printf "  %-24s %s\n" "PHP version:"  "${PHP_VERSION}"
    printf "  %-24s %s\n" "Database:"     "$( [[ "$ENABLE_DB" == true ]] && echo "yes" || echo "no" )"
    printf "  %-24s %s\n" "Redis:"        "$( [[ "$ENABLE_REDIS" == true ]] && echo "yes" || echo "no" )"
    printf "  %-24s %s\n" "Firewall:"     "$( [[ "$ENABLE_FIREWALL" == true ]] && echo "yes" || echo "no" )"
    printf "  %-24s %s\n" "Fail2Ban:"     "$( [[ "$ENABLE_FAIL2BAN" == true ]] && echo "yes" || echo "no" )"
    printf "  %-24s %s\n" "File access:"  "${FTP_MODE}"
    printf "  %-24s %s\n" "SSL email:"    "${SSL_EMAIL}"
    if [[ "$INSTALL_MODE" == "wp" ]]; then
        printf "  %-24s %s\n" "WP title:"     "${WP_TITLE}"
        printf "  %-24s %s\n" "WP admin:"     "${WP_ADMIN_USER}"
        printf "  %-24s %s\n" "Staging:"      "$( [[ "$WP_STAGING" == true ]] && echo "${WP_STAGING_TYPE}" || echo "no" )"
    fi
    echo
    prompt_yn "Start installation with these settings?" "y" || die "Installation cancelled."
}
