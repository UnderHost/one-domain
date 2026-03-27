#!/usr/bin/env bash
# =============================================================================
#  modules/packages.sh — Package installation per OS
# =============================================================================

pkg_install_base() {
    step "Installing base packages"
    case "$PKG_MGR" in
        apt)
            DEBIAN_FRONTEND=noninteractive apt-get update -qq
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
                curl wget gnupg2 ca-certificates lsb-release \
                software-properties-common apt-transport-https \
                unzip git rsync logrotate cron
            ;;
        dnf)
            dnf -y -q update
            dnf -y -q install \
                curl wget gnupg2 ca-certificates \
                epel-release \
                unzip git rsync logrotate cronie
            ;;
    esac
    ok "Base packages installed"
}

pkg_install_stack() {
    step "Installing web stack (Nginx · PHP ${PHP_VERSION} · MariaDB)"

    case "$OS_ID" in
        ubuntu|debian) _pkg_stack_debian ;;
        almalinux)     _pkg_stack_alma   ;;
    esac

    # Fail2Ban
    if [[ "$ENABLE_FAIL2BAN" == true ]]; then
        case "$PKG_MGR" in
            apt) apt-get install -y -qq fail2ban ;;
            dnf) dnf -y -q install fail2ban       ;;
        esac
        ok "Fail2Ban installed"
    fi

    # Image optimisation
    if [[ "$ENABLE_IMGOPT" == true ]]; then
        case "$PKG_MGR" in
            apt) apt-get install -y -qq jpegoptim optipng webp ;;
            dnf) dnf -y -q install jpegoptim optipng libwebp-tools ;;
        esac
        ok "Image optimisation tools installed"
    fi

    # Composer
    if [[ "$ENABLE_COMPOSER" == true ]] || [[ "$INSTALL_MODE" == "wp" ]]; then
        _install_composer
    fi

    # WP-CLI
    if [[ "$ENABLE_WPCLI" == true && "$INSTALL_MODE" == "wp" ]]; then
        _install_wpcli
    fi
}

# ---------------------------------------------------------------------------
_pkg_stack_debian() {
    # Add Ondrej PHP PPA (Ubuntu) or sury (Debian)
    if [[ "$OS_ID" == "ubuntu" ]]; then
        add-apt-repository -y ppa:ondrej/php &>/dev/null
        add-apt-repository -y ppa:ondrej/nginx-mainline &>/dev/null
    else
        # Debian — sury repository
        curl -sSo /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg 2>/dev/null \
            || warn "Could not add PHP repository key — using distribution PHP"
        echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" \
            > /etc/apt/sources.list.d/php.list 2>/dev/null || true
    fi

    DEBIAN_FRONTEND=noninteractive apt-get update -qq

    local php_pkgs=(
        "php${PHP_VERSION}-fpm"
        "php${PHP_VERSION}-mysql"
        "php${PHP_VERSION}-gd"
        "php${PHP_VERSION}-xml"
        "php${PHP_VERSION}-mbstring"
        "php${PHP_VERSION}-zip"
        "php${PHP_VERSION}-bcmath"
        "php${PHP_VERSION}-curl"
        "php${PHP_VERSION}-intl"
        "php${PHP_VERSION}-soap"
        "php${PHP_VERSION}-opcache"
        "php${PHP_VERSION}-imagick"
    )
    [[ "$ENABLE_REDIS" == true ]] && php_pkgs+=("php${PHP_VERSION}-redis")

    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        nginx \
        mariadb-server mariadb-client \
        certbot python3-certbot-nginx \
        "${php_pkgs[@]}"

    ok "Nginx, MariaDB, PHP ${PHP_VERSION} installed"

    # Enable and start services
    for svc in nginx mariadb "php${PHP_VERSION}-fpm"; do
        systemctl enable "$svc" --now 2>/dev/null
    done
}

# ---------------------------------------------------------------------------
_pkg_stack_alma() {
    # Remi repo for modern PHP on AlmaLinux
    dnf -y -q install "https://rpms.remirepo.net/enterprise/remi-release-$(rpm -E '%{rhel}').rpm" \
        2>/dev/null || warn "Could not add Remi repo — using distribution PHP"
    dnf module reset php -y -q 2>/dev/null || true
    dnf module enable "php:remi-${PHP_VERSION}" -y -q 2>/dev/null || true

    local php_pkgs=(
        php
        php-fpm
        php-mysqlnd
        php-gd
        php-xml
        php-mbstring
        php-zip
        php-bcmath
        php-curl
        php-intl
        php-soap
        php-opcache
        php-pecl-imagick
    )
    [[ "$ENABLE_REDIS" == true ]] && php_pkgs+=(php-redis)

    dnf -y -q install \
        nginx \
        mariadb-server \
        certbot python3-certbot-nginx \
        "${php_pkgs[@]}"

    ok "Nginx, MariaDB, PHP ${PHP_VERSION} installed"

    for svc in nginx mariadb php-fpm; do
        systemctl enable "$svc" --now 2>/dev/null
    done
}

# ---------------------------------------------------------------------------
_install_composer() {
    if command -v composer &>/dev/null; then
        ok "Composer already installed"
        return
    fi
    step "Installing Composer"
    local tmp
    tmp="$(mktemp)"
    curl -sS https://getcomposer.org/installer -o "$tmp"
    php "$tmp" --install-dir=/usr/local/bin --filename=composer --quiet
    rm -f "$tmp"
    ok "Composer installed at /usr/local/bin/composer"
}

# ---------------------------------------------------------------------------
_install_wpcli() {
    if command -v wp &>/dev/null; then
        ok "WP-CLI already installed"
        return
    fi
    step "Installing WP-CLI"
    curl -sL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
        -o /usr/local/bin/wp
    chmod +x /usr/local/bin/wp
    ok "WP-CLI installed at /usr/local/bin/wp"
}
