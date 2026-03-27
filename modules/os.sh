#!/usr/bin/env bash
# =============================================================================
#  modules/os.sh — OS detection, validation, package manager abstraction
# =============================================================================

OS_ID=""
OS_VERSION=""
OS_CODENAME=""
PKG_MGR=""          # apt | dnf
PKG_PHP_PREFIX=""   # "php8.3-" (Debian/Ubuntu) | "php" (AlmaLinux)
PHP_FPM_SOCK=""     # resolved after PHP version is known

# ---------------------------------------------------------------------------
# Supported OS matrix
#   Format: "id:min_version"
# ---------------------------------------------------------------------------
_SUPPORTED_OS=(
    "almalinux:9"
    "ubuntu:24.04"
    "debian:12"
)

os_detect() {
    [[ -f /etc/os-release ]] || die "Cannot detect OS — /etc/os-release missing."
    # shellcheck source=/dev/null
    source /etc/os-release
    OS_ID="${ID,,}"
    OS_VERSION="${VERSION_ID:-}"
    OS_CODENAME="${VERSION_CODENAME:-}"

    case "$OS_ID" in
        almalinux)
            PKG_MGR="dnf"
            PKG_PHP_PREFIX="php"
            ;;
        ubuntu|debian)
            PKG_MGR="apt"
            PKG_PHP_PREFIX="php${PHP_VERSION}-"
            ;;
        *)
            # Ubuntu might report as ubuntu with a numeric version
            ;;
    esac

    ok "Detected OS: ${OS_ID} ${OS_VERSION} ${OS_CODENAME:+(${OS_CODENAME})}"
}

os_validate_support() {
    local supported=false
    for entry in "${_SUPPORTED_OS[@]}"; do
        local sid="${entry%%:*}"
        local sver="${entry##*:}"
        if [[ "$OS_ID" == "$sid" ]]; then
            # Compare major version number
            local maj_running="${OS_VERSION%%.*}"
            local maj_required="${sver%%.*}"
            if (( maj_running >= maj_required )); then
                supported=true
                break
            fi
        fi
    done

    if [[ "$supported" == false ]]; then
        die "Unsupported OS: ${OS_ID} ${OS_VERSION}
Supported: AlmaLinux 9/10 · Ubuntu 24.04+ · Debian 12+"
    fi
    ok "OS is supported"
}

os_php_fpm_sock() {
    # Resolve the PHP-FPM socket path per OS
    local ver="${PHP_VERSION}"
    case "$OS_ID" in
        ubuntu|debian)
            PHP_FPM_SOCK="/run/php/php${ver}-fpm-${DOMAIN}.sock"
            ;;
        almalinux)
            PHP_FPM_SOCK="/run/php-fpm/${DOMAIN}.sock"
            ;;
    esac
}

os_php_fpm_service() {
    case "$OS_ID" in
        ubuntu|debian) echo "php${PHP_VERSION}-fpm" ;;
        almalinux)     echo "php-fpm" ;;
    esac
}

os_php_ini_dir() {
    case "$OS_ID" in
        ubuntu|debian) echo "/etc/php/${PHP_VERSION}/fpm" ;;
        almalinux)     echo "/etc/php.d" ;;
    esac
}

os_php_fpm_pool_dir() {
    case "$OS_ID" in
        ubuntu|debian) echo "/etc/php/${PHP_VERSION}/fpm/pool.d" ;;
        almalinux)     echo "/etc/php-fpm.d" ;;
    esac
}

os_web_user() {
    # The system user that Nginx runs as
    case "$OS_ID" in
        almalinux) echo "nginx" ;;
        *)         echo "www-data" ;;
    esac
}
