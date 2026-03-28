#!/usr/bin/env bash
# =============================================================================
#  UnderHost One-Domain — Interactive Wizard Module
#  modules/prompts.sh
# =============================================================================

[[ -n "${_UH_PROMPTS_LOADED:-}" ]] && return 0
_UH_PROMPTS_LOADED=1

run_wizard() {
    _wizard_banner
    if [[ "${BASIC_MODE:-false}" == true ]]; then
        _wizard_basic
    else
        _wizard_advanced
    fi
}

_wizard_banner() {
    clear 2>/dev/null || true
    cat <<EOF

$(color LCYAN "  ╔══════════════════════════════════════════════════╗")
$(color LCYAN "  ║") $(color BOLD "  UnderHost One-Domain Installer v${UNDERHOST_VERSION}") $(color LCYAN "    ║")
$(color LCYAN "  ║") $(color DIM "  https://underhost.com") $(color LCYAN "                        ║")
$(color LCYAN "  ╚══════════════════════════════════════════════════╝")

  This wizard will set up a complete web server for a single domain.
  Run $(color BOLD "install --basic --interactive") for a shorter guided setup.

EOF
}

# ---------------------------------------------------------------------------
# Basic wizard — essential questions only
# ---------------------------------------------------------------------------
_wizard_basic() {
    step "Basic Setup Wizard"

    DOMAIN="$(prompt_input 'Target domain (e.g. example.com)')"
    _validate_domain "$DOMAIN"

    local mode_choice
    mode_choice="$(prompt_select 'What do you want to install?' 'PHP website' 'WordPress')"
    case "$mode_choice" in
        "PHP website") INSTALL_MODE="php" ;;
        "WordPress")   INSTALL_MODE="wp"  ;;
    esac

    local php_choice
    php_choice="$(prompt_select 'PHP version?' '8.3 (recommended)' '8.4' '8.2' '8.1')"
    PHP_VERSION="${php_choice%% *}"

    SSL_EMAIL="$(prompt_input 'Email for SSL certificate notices' "admin@${DOMAIN}")"
    _validate_email "$SSL_EMAIL" "SSL email"

    if prompt_yn 'Create a database?' 'y'; then
        ENABLE_DB=true
    else
        ENABLE_DB=false
    fi

    _wizard_confirm_and_run
}

# ---------------------------------------------------------------------------
# Advanced wizard — all options
# ---------------------------------------------------------------------------
_wizard_advanced() {
    step "Advanced Setup Wizard"

    # Step 1: Domain
    echo; color BOLD "  Step 1 of 7 — Domain\n"
    DOMAIN="$(prompt_input 'Target domain (e.g. example.com)')"
    _validate_domain "$DOMAIN"

    if prompt_yn "Add www.${DOMAIN} as an alias?" 'n'; then
        CANONICAL_WWW=true
    fi

    # Step 2: Install mode
    echo; color BOLD "  Step 2 of 7 — Install Type\n"
    local mode_choice
    mode_choice="$(prompt_select 'What do you want to install?' 'PHP website' 'WordPress')"
    case "$mode_choice" in
        "PHP website") INSTALL_MODE="php" ;;
        "WordPress")   INSTALL_MODE="wp"  ;;
    esac

    # Step 3: PHP
    echo; color BOLD "  Step 3 of 7 — PHP\n"
    local php_choice
    php_choice="$(prompt_select 'PHP version?' '8.3 (recommended)' '8.4' '8.2' '8.1')"
    PHP_VERSION="${php_choice%% *}"

    # Step 4: SSL & Email
    echo; color BOLD "  Step 4 of 7 — SSL & Email\n"
    SSL_EMAIL="$(prompt_input 'Email for Let'\''s Encrypt SSL notices' "admin@${DOMAIN}")"
    _validate_email "$SSL_EMAIL" "SSL email"
    ADMIN_EMAIL="$SSL_EMAIL"

    # Step 5: Database
    echo; color BOLD "  Step 5 of 7 — Database\n"
    if prompt_yn 'Create a MariaDB database?' 'y'; then
        ENABLE_DB=true
    else
        ENABLE_DB=false
    fi

    # Step 6: WordPress-specific options
    if [[ "$INSTALL_MODE" == "wp" ]]; then
        echo; color BOLD "  Step 6 of 7 — WordPress Options\n"
        WP_TITLE="$(prompt_input 'WordPress site title' "$DOMAIN")"
        WP_ADMIN_USER="$(prompt_input 'Admin username' 'admin')"

        if prompt_yn 'Enable Redis object cache?' 'n'; then
            WP_REDIS=true
            ENABLE_REDIS=true
        fi

        if prompt_yn 'Create a staging environment?' 'n'; then
            WP_STAGING=true
        fi
    else
        echo; color BOLD "  Step 6 of 7 — Extras\n"
    fi

    # Step 7: Advanced options
    echo; color BOLD "  Step 7 of 7 — Advanced Options\n"

    local access_choice
    access_choice="$(prompt_select 'File access method?' 'None (SSH/root access only)' 'SFTP (recommended)' 'FTP with TLS (vsftpd)')"
    case "$access_choice" in
        "SFTP"*)        FTP_MODE="sftp"    ;;
        "FTP with TLS") FTP_MODE="ftp-tls" ;;
        *)              FTP_MODE="none"    ;;
    esac

    if prompt_yn 'Apply performance tuning?' 'y'; then
        TUNE_SERVICES=true
    else
        TUNE_SERVICES=false
    fi

    if prompt_yn 'Back up existing configs before install?' 'n'; then
        BACKUP=true
    fi

    if prompt_yn 'Install image optimisation tools (jpegoptim, optipng)?' 'n'; then
        ENABLE_IMGOPT=true
    fi

    _wizard_confirm_and_run
}

_wizard_confirm_and_run() {
    echo
    step "Install Plan"
    _print_plan
    echo

    if ! prompt_yn 'Proceed with installation?' 'y'; then
        die "Installation cancelled."
    fi

    # Let main() take over — wizard just sets global variables
    INTERACTIVE=false
    SKIP_PROMPT=true
}
