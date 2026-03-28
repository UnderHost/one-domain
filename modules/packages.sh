#!/usr/bin/env bash
# =============================================================================
#  UnderHost One-Domain — Package Installation Module
#  modules/packages.sh
# =============================================================================

[[ -n "${_UH_PACKAGES_LOADED:-}" ]] && return 0
_UH_PACKAGES_LOADED=1

pkg_install_base() {
    step "Installing base packages"
    case "$OS_PKG_MGR" in
        apt)  _pkg_install_base_apt  ;;
        dnf)  _pkg_install_base_dnf  ;;
    esac
}

pkg_install_stack() {
    step "Installing web stack (Nginx, PHP ${PHP_VERSION}, MariaDB)"
    case "$OS_PKG_MGR" in
        apt)  _pkg_install_stack_apt  ;;
        dnf)  _pkg_install_stack_dnf  ;;
    esac
}

# ---------------------------------------------------------------------------
# APT (Ubuntu / Debian)
# ---------------------------------------------------------------------------
_pkg_install_base_apt() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get -qq update
    apt-get -y -qq install --no-install-recommends \
        curl wget gnupg2 lsb-release ca-certificates \
        software-properties-common apt-transport-https \
        unzip tar git rsync bc openssl \
        fail2ban ufw \
        2>&1 | grep -v "^$" || true
    ok "Base packages installed"
}

_pkg_install_stack_apt() {
    export DEBIAN_FRONTEND=noninteractive

    # ---- PHP via Ondrej PPA (signed-by keyring) ----------------------------
    local keyring_dir="/usr/share/keyrings"
    local php_keyring="${keyring_dir}/ondrej-php-keyring.gpg"

    if [[ ! -f "$php_keyring" ]]; then
        curl -fsSL https://packages.sury.org/php/apt.gpg \
            | gpg --dearmor -o "$php_keyring"
        chmod 644 "$php_keyring"
    fi

    local codename
    codename="$(lsb_release -sc 2>/dev/null || echo "${OS_CODENAME:-noble}")"

    cat > /etc/apt/sources.list.d/ondrej-php.list <<EOF
deb [signed-by=${php_keyring}] https://packages.sury.org/php/ ${codename} main
EOF

    # ---- Nginx stable (nginx.org signed repo) ------------------------------
    local nginx_keyring="${keyring_dir}/nginx-archive-keyring.gpg"
    if [[ ! -f "$nginx_keyring" ]]; then
        curl -fsSL https://nginx.org/keys/nginx_signing.key \
            | gpg --dearmor -o "$nginx_keyring"
        chmod 644 "$nginx_keyring"
    fi

    cat > /etc/apt/sources.list.d/nginx-stable.list <<EOF
deb [signed-by=${nginx_keyring}] https://nginx.org/packages/$(lsb_release -si | tr '[:upper:]' '[:lower:]')/ ${codename} nginx
EOF

    apt-get -qq update

    # Core stack
    apt-get -y -qq install --no-install-recommends \
        nginx \
        "php${PHP_VERSION}-fpm" \
        "php${PHP_VERSION}-cli" \
        "php${PHP_VERSION}-common" \
        "php${PHP_VERSION}-mysql" \
        "php${PHP_VERSION}-curl" \
        "php${PHP_VERSION}-gd" \
        "php${PHP_VERSION}-mbstring" \
        "php${PHP_VERSION}-xml" \
        "php${PHP_VERSION}-xmlrpc" \
        "php${PHP_VERSION}-zip" \
        "php${PHP_VERSION}-intl" \
        "php${PHP_VERSION}-bcmath" \
        "php${PHP_VERSION}-imagick" \
        "php${PHP_VERSION}-opcache" \
        "php${PHP_VERSION}-redis" \
        mariadb-server \
        certbot python3-certbot-nginx \
        2>&1 | grep -v "^$" || true

    svc_enable_start nginx
    svc_enable_start mariadb
    svc_enable_start "php${PHP_VERSION}-fpm"
    ok "Stack installed (apt)"
}

# ---------------------------------------------------------------------------
# DNF (AlmaLinux 9/10)
# ---------------------------------------------------------------------------
_pkg_install_base_dnf() {
    dnf -q -y install epel-release 2>/dev/null || true
    dnf -q -y install \
        curl wget gnupg2 ca-certificates \
        unzip tar git rsync bc openssl \
        fail2ban firewalld \
        2>&1 | grep -v "^$" || true
    ok "Base packages installed"
}

_pkg_install_stack_dnf() {
    # ---- REMI repo for PHP -------------------------------------------------
    local remi_rpm
    case "$OS_VERSION" in
        9)  remi_rpm="https://rpms.remirepo.net/enterprise/remi-release-9.rpm" ;;
        10) remi_rpm="https://rpms.remirepo.net/enterprise/remi-release-10.rpm" ;;
        *)  die "No REMI package available for AlmaLinux ${OS_VERSION}" ;;
    esac

    if ! rpm -q remi-release &>/dev/null; then
        dnf -q -y install "$remi_rpm" 2>/dev/null || true
    fi

    # Enable the correct PHP stream
    local remi_stream="remi-php${PHP_VERSION/./}"
    dnf -q -y module reset  php 2>/dev/null || true
    dnf -q -y module disable php 2>/dev/null || true
    dnf -q -y --enablerepo="${remi_stream}" install \
        nginx \
        php php-fpm php-cli php-common \
        php-mysqlnd php-curl php-gd php-mbstring \
        php-xml php-xmlrpc php-zip php-intl php-bcmath \
        php-imagick php-opcache php-pecl-redis \
        mariadb-server \
        certbot python3-certbot-nginx \
        2>&1 | grep -v "^$" || true

    svc_enable_start nginx
    svc_enable_start mariadb
    svc_enable_start php-fpm
    ok "Stack installed (dnf)"
}

# ---------------------------------------------------------------------------
# Optional package installers (called from specific modules)
# ---------------------------------------------------------------------------
pkg_install_redis() {
    step "Installing Redis"
    case "$OS_PKG_MGR" in
        apt)
            apt-get -y -qq install --no-install-recommends redis-server
            svc_enable_start redis-server
            ;;
        dnf)
            dnf -q -y install redis
            svc_enable_start redis
            ;;
    esac
    ok "Redis installed"
}

pkg_install_vsftpd() {
    step "Installing vsftpd"
    case "$OS_PKG_MGR" in
        apt) apt-get -y -qq install --no-install-recommends vsftpd ;;
        dnf) dnf -q -y install vsftpd ;;
    esac
    ok "vsftpd installed"
}

pkg_install_imgopt() {
    step "Installing image optimisation tools"
    case "$OS_PKG_MGR" in
        apt)
            apt-get -y -qq install --no-install-recommends \
                jpegoptim optipng pngquant webp gifsicle
            ;;
        dnf)
            dnf -q -y install jpegoptim optipng pngquant libwebp-tools gifsicle
            ;;
    esac
    ok "Image optimisation tools installed"
}

pkg_install_composer() {
    step "Installing Composer"
    local expected_checksum
    expected_checksum="$(curl -fsSL https://composer.github.io/installer.sig)"
    local actual_checksum

    curl -fsSL https://getcomposer.org/installer -o /tmp/composer-setup.php
    actual_checksum="$(php -r "echo hash_file('sha384', '/tmp/composer-setup.php');")"

    if [[ "$expected_checksum" != "$actual_checksum" ]]; then
        rm -f /tmp/composer-setup.php
        die "Composer installer checksum mismatch — aborting"
    fi

    php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer --quiet
    rm -f /tmp/composer-setup.php
    chmod +x /usr/local/bin/composer
    ok "Composer installed: $(composer --version 2>/dev/null | head -1)"
}
