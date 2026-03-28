#!/usr/bin/env bash
# =============================================================================
#  UnderHost One-Domain — Interactive Wizard Module  (v2026.4.0)
#  modules/prompts.sh
# =============================================================================
# New in v4:
#   - Step 8: SSH public key install
#   - Step 8: Auto OS security updates toggle
#   - Step count updated to 9
# =============================================================================

[[ -n "${_UH_PROMPTS_LOADED:-}" ]] && return 0
_UH_PROMPTS_LOADED=1

_WIZARD_SSH_KEY=""

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

$(color LCYAN "  ╔══════════════════════════════════════════════════════╗")
$(color LCYAN "  ║") $(color BOLD "  UnderHost One-Domain Installer v${UNDERHOST_VERSION}") $(color LCYAN "  ║")
$(color LCYAN "  ║") $(color DIM "  https://underhost.com  |  GPL-3.0") $(color LCYAN "                  ║")
$(color LCYAN "  ╚══════════════════════════════════════════════════════╝")

  This wizard sets up a complete web server for a single domain.
  $(color DIM "Run 'install check-deps' first to verify your server is ready.")

EOF
}

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

    SSL_EMAIL="$(prompt_input 'Email for SSL certificate' "admin@${DOMAIN}")"
    _validate_email "$SSL_EMAIL" "SSL email"

    prompt_yn 'Create a database?' 'y' && ENABLE_DB=true || ENABLE_DB=false

    _wizard_confirm_and_run
}

_wizard_advanced() {
    step "Advanced Setup Wizard"

    # Step 1 — Domain
    echo; printf '%b  Step 1 of 9 — Domain%b\n' "$_CLR_BOLD" "$_CLR_RESET"
    DOMAIN="$(prompt_input 'Target domain (e.g. example.com)')"
    _validate_domain "$DOMAIN"
    prompt_yn "Include www.${DOMAIN} as alias?" 'n' && CANONICAL_WWW=true

    # Step 2 — Install type
    echo; printf '%b  Step 2 of 9 — Install Type%b\n' "$_CLR_BOLD" "$_CLR_RESET"
    local mode_choice
    mode_choice="$(prompt_select 'What to install?' 'PHP website' 'WordPress')"
    case "$mode_choice" in
        "PHP website") INSTALL_MODE="php" ;;
        "WordPress")   INSTALL_MODE="wp"  ;;
    esac

    # Step 3 — PHP version
    echo; printf '%b  Step 3 of 9 — PHP%b\n' "$_CLR_BOLD" "$_CLR_RESET"
    local php_choice
    php_choice="$(prompt_select 'PHP version?' '8.3 (recommended)' '8.4' '8.2' '8.1')"
    PHP_VERSION="${php_choice%% *}"

    # Step 4 — SSL & Email
    echo; printf '%b  Step 4 of 9 — SSL & Email%b\n' "$_CLR_BOLD" "$_CLR_RESET"
    SSL_EMAIL="$(prompt_input "Email for Let's Encrypt SSL" "admin@${DOMAIN}")"
    _validate_email "$SSL_EMAIL" "SSL email"
    ADMIN_EMAIL="$SSL_EMAIL"

    # Step 5 — Database
    echo; printf '%b  Step 5 of 9 — Database%b\n' "$_CLR_BOLD" "$_CLR_RESET"
    prompt_yn 'Create a MariaDB database?' 'y' && ENABLE_DB=true || ENABLE_DB=false

    # Step 6 — WordPress options
    echo; printf '%b  Step 6 of 9 — WordPress / Extras%b\n' "$_CLR_BOLD" "$_CLR_RESET"
    if [[ "$INSTALL_MODE" == "wp" ]]; then
        WP_TITLE="$(prompt_input 'Site title' "$DOMAIN")"
        WP_ADMIN_USER="$(prompt_input 'Admin username' 'admin')"
        if prompt_yn 'Enable Redis object cache?' 'n'; then
            WP_REDIS=true; ENABLE_REDIS=true
        fi
        prompt_yn 'Create a staging environment?' 'n' && WP_STAGING=true
    else
        info "No WordPress options needed for PHP mode"
    fi

    # Step 7 — File access
    echo; printf '%b  Step 7 of 9 — File Access%b\n' "$_CLR_BOLD" "$_CLR_RESET"
    local access_choice
    access_choice="$(prompt_select 'File access method?' \
        'None (SSH/root access only)' \
        'SFTP only (recommended)' \
        'FTP with TLS (vsftpd)')"
    case "$access_choice" in
        "SFTP only"*)   FTP_MODE="sftp"    ;;
        "FTP with TLS") FTP_MODE="ftp-tls" ;;
        *)              FTP_MODE="none"    ;;
    esac

    # Step 8 — Security
    echo; printf '%b  Step 8 of 9 — Security%b\n' "$_CLR_BOLD" "$_CLR_RESET"

    if prompt_yn 'Configure automatic OS security updates? (recommended)' 'y'; then
        ENABLE_AUTO_UPDATES=true
    else
        ENABLE_AUTO_UPDATES=false
        warn "Auto-updates disabled — remember to apply security patches manually."
    fi

    if prompt_yn 'Add an SSH public key for root now?' 'n'; then
        printf '\n  Paste your public key (ssh-ed25519 / ssh-rsa / ecdsa): '
        read -r _WIZARD_SSH_KEY
        if [[ -n "$_WIZARD_SSH_KEY" ]]; then
            info "SSH key will be installed after setup completes."
        fi
    fi

    # Step 9 — Performance & options
    echo; printf '%b  Step 9 of 9 — Performance & Options%b\n' "$_CLR_BOLD" "$_CLR_RESET"
    prompt_yn 'Apply performance tuning? (recommended)' 'y' \
        && TUNE_SERVICES=true || TUNE_SERVICES=false
    prompt_yn 'Install image optimisation tools? (jpegoptim, optipng)' 'n' \
        && ENABLE_IMGOPT=true
    prompt_yn 'Back up existing configs before install?' 'n' \
        && BACKUP=true

    _wizard_confirm_and_run

    # Post-wizard: install SSH key if provided
    if [[ -n "$_WIZARD_SSH_KEY" ]]; then
        echo
        step "Installing SSH public key"
        hardening_install_ssh_key "$_WIZARD_SSH_KEY" 2>/dev/null \
            || warn "SSH key install failed — add manually to /root/.ssh/authorized_keys"
    fi
}

_wizard_confirm_and_run() {
    echo
    step "Install Plan"
    _print_plan
    echo
    if ! prompt_yn 'Proceed with installation?' 'y'; then
        die "Installation cancelled."
    fi
    INTERACTIVE=false
    SKIP_PROMPT=true
}
