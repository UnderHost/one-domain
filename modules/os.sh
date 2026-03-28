#!/usr/bin/env bash
# =============================================================================
#  UnderHost One-Domain — OS Detection Module
#  modules/os.sh
# =============================================================================
# Exports: OS_ID, OS_VERSION, OS_CODENAME, OS_FAMILY (debian|rhel),
#          OS_PKG_MGR (apt|dnf), OS_ARCH
#          Functions: os_detect, os_validate_support, os_preflight,
#                     os_php_fpm_service, os_nginx_conf_dir,
#                     os_php_pool_dir, os_php_ini_dir
# =============================================================================

[[ -n "${_UH_OS_LOADED:-}" ]] && return 0
_UH_OS_LOADED=1

# Supported OS matrix  (ID : min-version)
# Extend this table when adding new support — nowhere else.
declare -A _OS_SUPPORT_MATRIX=(
    ["ubuntu"]="24.04"
    ["debian"]="12"
    ["almalinux"]="9"
)

OS_ID=""
OS_VERSION=""
OS_CODENAME=""
OS_FAMILY=""        # debian | rhel
OS_PKG_MGR=""       # apt | dnf
OS_ARCH=""

os_detect() {
    if [[ ! -f /etc/os-release ]]; then
        die "Cannot detect OS: /etc/os-release not found"
    fi

    # shellcheck disable=SC1091
    source /etc/os-release

    OS_ID="${ID,,}"
    OS_VERSION="${VERSION_ID:-}"
    OS_CODENAME="${VERSION_CODENAME:-}"
    OS_ARCH="$(uname -m)"

    # Normalise AlmaLinux version (strip patch: 9.3 → 9)
    case "$OS_ID" in
        almalinux|rocky|rhel)
            OS_VERSION="${OS_VERSION%%.*}"   # major only
            OS_FAMILY="rhel"
            OS_PKG_MGR="dnf"
            ;;
        ubuntu|debian)
            OS_FAMILY="debian"
            OS_PKG_MGR="apt"
            ;;
        *)
            # Check if it's a derivative
            local id_like="${ID_LIKE:-}"
            if [[ "$id_like" =~ rhel|fedora ]]; then
                OS_FAMILY="rhel"
                OS_PKG_MGR="dnf"
            elif [[ "$id_like" =~ debian|ubuntu ]]; then
                OS_FAMILY="debian"
                OS_PKG_MGR="apt"
            else
                die "Unrecognised OS: ${OS_ID} — supported: Ubuntu 24+, Debian 12+, AlmaLinux 9+"
            fi
            ;;
    esac

    info "Detected: ${OS_ID} ${OS_VERSION} (${OS_ARCH})"
}

os_validate_support() {
    local min_ver="${_OS_SUPPORT_MATRIX[$OS_ID]:-}"

    if [[ -z "$min_ver" ]]; then
        die "OS '${OS_ID}' is not supported.
Supported: Ubuntu 24.04+, Debian 12+, AlmaLinux 9/10
CentOS, Rocky Linux, RHEL, and older distros are not supported."
    fi

    # Version comparison: split on '.' and compare numerically per segment
    if ! _version_gte "$OS_VERSION" "$min_ver"; then
        die "${OS_ID} ${OS_VERSION} is below the minimum supported version (${min_ver}).
Please upgrade to ${OS_ID} ${min_ver} or later."
    fi

    ok "OS check passed: ${OS_ID} ${OS_VERSION}"
}

# _version_gte ver1 ver2 — true if ver1 >= ver2
_version_gte() {
    local v1="$1" v2="$2"
    # Use sort -V (version sort) for reliable comparison
    [[ "$(printf '%s\n%s' "$v1" "$v2" | sort -V | head -n1)" == "$v2" ]]
}

os_preflight() {
    step "Running preflight checks"

    # Architecture
    case "$OS_ARCH" in
        x86_64|aarch64) ok "Architecture: ${OS_ARCH}" ;;
        *) warn "Untested architecture: ${OS_ARCH} — proceeding with caution" ;;
    esac

    # Check for systemd
    if ! command -v systemctl &>/dev/null; then
        die "systemd is required but not found. This installer does not support SysV init."
    fi
    ok "systemd available"

    # Minimum RAM: warn below 512 MB
    local ram_mb
    ram_mb="$(detect_ram_mb)"
    if (( ram_mb < 512 )); then
        warn "Low RAM detected: ${ram_mb} MB. Minimum recommended is 1 GB for a stable install."
    else
        ok "RAM: ${ram_mb} MB"
    fi

    # Disk space: warn below 4 GB free on /
    local free_kb
    free_kb="$(df -k / | awk 'NR==2 {print $4}')"
    local free_mb=$(( free_kb / 1024 ))
    if (( free_mb < 4096 )); then
        warn "Low disk space on /: ${free_mb} MB free. Recommend at least 4 GB free."
    else
        ok "Disk: ${free_mb} MB free on /"
    fi

    # Ensure package manager is functional
    case "$OS_PKG_MGR" in
        apt)
            if ! apt-get -qq check 2>/dev/null; then
                warn "apt has pending errors — running: apt-get -f install"
                apt-get -y -f install &>/dev/null || true
            fi
            ;;
        dnf)
            dnf clean expire-cache &>/dev/null || true
            ;;
    esac
    ok "Package manager: ${OS_PKG_MGR}"
}

# ---------------------------------------------------------------------------
# Path resolution helpers — returns correct paths for each OS
# ---------------------------------------------------------------------------

# PHP-FPM systemd service name
os_php_fpm_service() {
    case "$OS_FAMILY" in
        debian)  echo "php${PHP_VERSION}-fpm" ;;
        rhel)    echo "php-fpm" ;;
        *)       echo "php-fpm" ;;
    esac
}

# Nginx conf.d directory
os_nginx_conf_dir() {
    echo "/etc/nginx/conf.d"
}

# PHP-FPM pool directory
os_php_pool_dir() {
    case "$OS_FAMILY" in
        debian)  echo "/etc/php/${PHP_VERSION}/fpm/pool.d" ;;
        rhel)    echo "/etc/php-fpm.d" ;;
        *)       echo "/etc/php-fpm.d" ;;
    esac
}

# PHP ini directory (for cli / fpm)
os_php_ini_dir() {
    case "$OS_FAMILY" in
        debian)  echo "/etc/php/${PHP_VERSION}/fpm/conf.d" ;;
        rhel)    echo "/etc/php.d" ;;
        *)       echo "/etc/php.d" ;;
    esac
}

# PHP binary path
os_php_bin() {
    command -v "php${PHP_VERSION}" 2>/dev/null \
        || command -v php 2>/dev/null \
        || echo "/usr/bin/php"
}

# MariaDB config file location
os_mariadb_conf() {
    if [[ -f /etc/my.cnf.d/server.cnf ]]; then
        echo "/etc/my.cnf.d/server.cnf"       # AlmaLinux
    elif [[ -f /etc/mysql/mariadb.conf.d/50-server.cnf ]]; then
        echo "/etc/mysql/mariadb.conf.d/50-server.cnf"  # Debian/Ubuntu
    else
        echo "/etc/my.cnf"
    fi
}

# vsftpd chroot list
os_vsftpd_chroot_file() {
    echo "/etc/vsftpd/chroot_list"
}
