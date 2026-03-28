#!/usr/bin/env bash
# =============================================================================
#  modules/packages.sh — System package installation
# =============================================================================

# ---------------------------------------------------------------------------
# Install a single package quietly (used by other modules)
pkg_install() {
    local pkg="$1"
    case "$PKG_MGR" in
        apt) DEBIAN_FRONTEND=noninteractive apt-get install -y -q "$pkg" &>/dev/null ;;
        dnf) dnf install -y "$pkg" &>/dev/null ;;
        *)   warn "Unknown package manager — cannot install $pkg" ;;
    esac
}

# ---------------------------------------------------------------------------
# Base system packages needed by every install
pkg_install_base() {
    step "Installing base system packages"

    case "$PKG_MGR" in
        apt)
            apt-get update -q &>/dev/null
            DEBIAN_FRONTEND=noninteractive apt-get install -y -q \
                curl wget gnupg2 ca-certificates lsb-release \
                unzip tar rsync cron logrotate \
                software-properties-common \
                net-tools dnsutils openssl \
                htop vim nano ufw fail2ban \
                2>/dev/null
            ;;
        dnf)
            dnf update -y -q &>/dev/null
            dnf install -y -q \
                curl wget gnupg2 ca-certificates \
                unzip tar rsync cronie logrotate \
                net-tools bind-utils openssl \
                htop vim nano firewalld fail2ban \
                2>/dev/null
            ;;
    esac
    ok "Base packages installed"
}

# ---------------------------------------------------------------------------
# Stack packages (Nginx, PHP, MariaDB, etc.)
pkg_install_stack() {
    step "Installing web stack"

    # Ensure PHP repo is available
    os_add_php_repo

    case "$PKG_MGR" in
        apt) _pkg_install_stack_apt ;;
        dnf) _pkg_install_stack_dnf ;;
    esac

    # WP-CLI (if WordPress mode)
    [[ "${ENABLE_WPCLI:-true}" == true ]] && _pkg_install_wpcli

    # Composer (optional)
    [[ "${ENABLE_COMPOSER:-false}" == true ]] && _pkg_install_composer

    # Image optimization (optional)
    [[ "${ENABLE_IMGOPT:-false}" == true ]] && _pkg_install_imgopt

    # Redis server (if requested)
    [[ "${ENABLE_REDIS:-false}" == true ]] && _pkg_install_redis

    ok "Web stack installed"
}

# ---------------------------------------------------------------------------
_pkg_install_stack_apt() {
    local php_pkgs=(
        "php${PHP_VERSION}-fpm"
        "php${PHP_VERSION}-cli"
        "php${PHP_VERSION}-common"
        "php${PHP_VERSION}-mysql"
        "php${PHP_VERSION}-curl"
        "php${PHP_VERSION}-gd"
        "php${PHP_VERSION}-intl"
        "php${PHP_VERSION}-mbstring"
        "php${PHP_VERSION}-xml"
        "php${PHP_VERSION}-zip"
        "php${PHP_VERSION}-bcmath"
        "php${PHP_VERSION}-soap"
        "php${PHP_VERSION}-opcache"
    )
    [[ "${ENABLE_REDIS:-false}" == true ]] && php_pkgs+=("php${PHP_VERSION}-redis")

    DEBIAN_FRONTEND=noninteractive apt-get install -y -q \
        nginx \
        mariadb-server \
        certbot python3-certbot-nginx \
        "${php_pkgs[@]}" \
        apache2-utils \
        2>/dev/null \
        || die "Package installation failed — check apt logs"

    # Enable services
    systemctl enable nginx mariadb "php${PHP_VERSION}-fpm" 2>/dev/null || true
    systemctl start  nginx mariadb "php${PHP_VERSION}-fpm" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
_pkg_install_stack_dnf() {
    local php_pkgs=(
        php php-fpm php-cli php-common
        php-mysqlnd php-curl php-gd php-intl
        php-mbstring php-xml php-zip php-bcmath
        php-soap php-opcache
    )
    [[ "${ENABLE_REDIS:-false}" == true ]] && php_pkgs+=(php-redis)

    dnf install -y \
        nginx \
        mariadb-server \
        certbot python3-certbot-nginx \
        "${php_pkgs[@]}" \
        httpd-tools \
        2>/dev/null \
        || die "Package installation failed — check dnf logs"

    systemctl enable nginx mariadb php-fpm 2>/dev/null || true
    systemctl start  nginx mariadb php-fpm 2>/dev/null || true
}

# ---------------------------------------------------------------------------
_pkg_install_wpcli() {
    if command -v wp &>/dev/null; then
        ok "WP-CLI already installed: $(wp --version 2>/dev/null | head -1)"
        return
    fi
    info "Installing WP-CLI"
    curl --fail --silent --location \
        https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
        -o /usr/local/bin/wp \
        || { warn "Could not download WP-CLI"; return; }
    chmod +x /usr/local/bin/wp
    ok "WP-CLI installed: $(wp --version --allow-root 2>/dev/null | head -1)"
}

# ---------------------------------------------------------------------------
_pkg_install_composer() {
    if command -v composer &>/dev/null; then
        ok "Composer already installed"
        return
    fi
    info "Installing Composer"
    local tmp_installer
    tmp_installer="$(mktemp)"
    curl --fail --silent \
        https://getcomposer.org/installer \
        -o "$tmp_installer" \
        || { warn "Could not download Composer installer"; return; }
    php "$tmp_installer" --install-dir=/usr/local/bin --filename=composer &>/dev/null \
        && ok "Composer installed" \
        || warn "Composer install failed"
    rm -f "$tmp_installer"
}

# ---------------------------------------------------------------------------
_pkg_install_redis() {
    if command -v redis-cli &>/dev/null; then
        ok "Redis already installed"
        return
    fi
    info "Installing Redis"
    case "$PKG_MGR" in
        apt) DEBIAN_FRONTEND=noninteractive apt-get install -y -q redis-server &>/dev/null ;;
        dnf) dnf install -y redis &>/dev/null ;;
    esac
    systemctl enable --now redis 2>/dev/null || systemctl enable --now redis-server 2>/dev/null || true
    ok "Redis installed"
}

# ---------------------------------------------------------------------------
_pkg_install_imgopt() {
    info "Installing image optimization tools"
    case "$PKG_MGR" in
        apt) DEBIAN_FRONTEND=noninteractive apt-get install -y -q \
                jpegoptim optipng pngquant webp gifsicle &>/dev/null || true ;;
        dnf) dnf install -y jpegoptim optipng pngquant libwebp-tools &>/dev/null || true ;;
    esac
    ok "Image optimization tools installed"
}
