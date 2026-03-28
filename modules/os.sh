#!/usr/bin/env bash
# =============================================================================
#  modules/os.sh — OS detection, validation, and OS-specific helpers
# =============================================================================

OS_ID=""
OS_VERSION=""
OS_CODENAME=""
PKG_MGR=""        # apt | dnf
PHP_FPM_SOCK=""   # set by os_php_fpm_sock()

# ---------------------------------------------------------------------------
os_detect() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        OS_ID="${ID,,}"
        OS_VERSION="${VERSION_ID%%.*}"
        OS_CODENAME="${VERSION_CODENAME:-}"
    else
        die "Cannot detect OS — /etc/os-release not found."
    fi

    case "$OS_ID" in
        ubuntu|debian)   PKG_MGR="apt"  ;;
        almalinux|rhel|centos|rocky) PKG_MGR="dnf" ;;
        *) PKG_MGR="apt" ;;  # best-effort fallback
    esac
}

# ---------------------------------------------------------------------------
os_validate_support() {
    local supported=false
    case "$OS_ID" in
        ubuntu)    [[ "$OS_VERSION" =~ ^(24|25|26)$ ]] && supported=true ;;
        debian)    [[ "$OS_VERSION" =~ ^(12|13)$    ]] && supported=true ;;
        almalinux) [[ "$OS_VERSION" =~ ^(9|10)$     ]] && supported=true ;;
    esac

    if ! $supported; then
        warn "OS '${OS_ID} ${OS_VERSION}' is not officially supported."
        warn "Supported: Ubuntu 24/25, Debian 12/13, AlmaLinux 9/10"
        prompt_yn "Continue anyway (not recommended)?" "n" \
            || die "Installation cancelled — unsupported OS."
    fi
}

# ---------------------------------------------------------------------------
# Web server process user (nginx on RHEL, www-data on Debian/Ubuntu)
os_web_user() {
    case "$OS_ID" in
        almalinux|rhel|centos|rocky) echo "nginx" ;;
        *) echo "www-data" ;;
    esac
}

# ---------------------------------------------------------------------------
# PHP-FPM pool config directory
os_php_fpm_pool_dir() {
    case "$OS_ID" in
        ubuntu|debian)
            echo "/etc/php/${PHP_VERSION}/fpm/pool.d"
            ;;
        almalinux|rhel|centos|rocky)
            echo "/etc/php-fpm.d"
            ;;
        *)
            # Fallback: try to find the pool directory
            if [[ -d "/etc/php/${PHP_VERSION}/fpm/pool.d" ]]; then
                echo "/etc/php/${PHP_VERSION}/fpm/pool.d"
            else
                echo "/etc/php-fpm.d"
            fi
            ;;
    esac
}

# ---------------------------------------------------------------------------
# PHP-FPM systemd service name
os_php_fpm_service() {
    case "$OS_ID" in
        ubuntu|debian) echo "php${PHP_VERSION}-fpm" ;;
        almalinux|rhel|centos|rocky) echo "php-fpm" ;;
        *) echo "php-fpm" ;;
    esac
}

# ---------------------------------------------------------------------------
# PHP-FPM unix socket path — sets global PHP_FPM_SOCK
os_php_fpm_sock() {
    case "$OS_ID" in
        ubuntu|debian)
            PHP_FPM_SOCK="/run/php/php${PHP_VERSION}-fpm-${DOMAIN}.sock"
            ;;
        almalinux|rhel|centos|rocky)
            PHP_FPM_SOCK="/run/php-fpm/${DOMAIN}.sock"
            ;;
        *)
            PHP_FPM_SOCK="/run/php/php${PHP_VERSION}-fpm-${DOMAIN}.sock"
            ;;
    esac
    export PHP_FPM_SOCK
}

# ---------------------------------------------------------------------------
# PHP repository setup (ondrej/php for Debian/Ubuntu, remi for RHEL)
os_add_php_repo() {
    case "$OS_ID" in
        ubuntu|debian)
            if ! apt-cache show "php${PHP_VERSION}-fpm" &>/dev/null; then
                info "Adding ondrej/php PPA"
                apt-get install -y software-properties-common gnupg2 &>/dev/null
                add-apt-repository -y ppa:ondrej/php &>/dev/null \
                    || { warn "Could not add ondrej/php PPA"; return 1; }
                apt-get update -q &>/dev/null
            fi
            ;;
        almalinux|rhel|centos|rocky)
            if ! rpm -q "php${PHP_VERSION}" &>/dev/null; then
                info "Adding Remi PHP repository"
                dnf install -y epel-release &>/dev/null || true
                dnf install -y "https://rpms.remirepo.net/enterprise/remi-release-${OS_VERSION}.rpm" \
                    &>/dev/null || warn "Remi repo install failed"
                dnf module reset php -y &>/dev/null || true
                dnf module enable "php:remi-${PHP_VERSION}" -y &>/dev/null || true
            fi
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Pre-flight system checks
os_preflight() {
    step "Running pre-flight checks"

    # Root check (belt + suspenders)
    [[ "$EUID" -eq 0 ]] || die "Must run as root."

    # Disk space (need at least 2 GB free on /)
    local free_mb
    free_mb="$(df -BM / | awk 'NR==2{print $4}' | tr -d 'M')"
    if (( ${free_mb:-0} < 2048 )); then
        warn "Low disk space: ${free_mb} MB free on /  (recommend ≥ 2 GB)"
        prompt_yn "Continue anyway?" "n" || die "Aborted — low disk space."
    else
        ok "Disk space OK (${free_mb} MB free)"
    fi

    # RAM
    local ram_mb
    ram_mb="$(awk '/MemTotal/{printf "%.0f",$2/1024}' /proc/meminfo)"
    if (( ${ram_mb:-0} < 512 )); then
        warn "Very low RAM: ${ram_mb} MB — minimum recommended is 512 MB"
        prompt_yn "Continue anyway?" "n" || die "Aborted — insufficient RAM."
    else
        ok "RAM OK (${ram_mb} MB)"
    fi

    # Port 80/443 — only warn, don't block (may be in use by existing Nginx)
    for port in 80 443; do
        if ss -tlnp 2>/dev/null | grep -q ":${port}\b"; then
            info "Port ${port} already in use (existing service detected)"
        fi
    done

    ok "Pre-flight checks passed"
}
