#!/usr/bin/env bash
# =============================================================================
#  modules/database.sh — MariaDB initialization and database creation
# =============================================================================

db_create() {
    step "Configuring MariaDB and creating database"

    systemctl enable mariadb --now 2>/dev/null

    _db_secure_install
    _db_create_site_db

    ok "Database '${DB_NAME}' and user '${DB_USER}' created"
}

# ---------------------------------------------------------------------------
# Secure the MariaDB installation without relying on the interactive
# mysql_secure_installation binary (which cannot be piped reliably).
# ---------------------------------------------------------------------------
_db_secure_install() {
    info "Securing MariaDB installation"

    # Only attempt if we can connect without a password (fresh install)
    if mysql -u root --connect-expired-password -e "SELECT 1;" &>/dev/null; then
        mysql -u root --connect-expired-password <<SQL
-- Remove anonymous accounts
DELETE FROM mysql.user WHERE User='';
-- Remove remote root accounts
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
-- Remove test database
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
-- Set root password
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASS}';
FLUSH PRIVILEGES;
SQL
        ok "MariaDB secured. Root password set."
    else
        info "MariaDB appears already secured — skipping initial hardening."
    fi
}

# ---------------------------------------------------------------------------
_db_create_site_db() {
    mysql -u root -p"${MYSQL_ROOT_PASS}" <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`
    CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost'
    IDENTIFIED BY '${DB_PASS}';

GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL
}

# ---------------------------------------------------------------------------
# Tune MariaDB based on available RAM
# Called from optimize module but defined here for cohesion
# ---------------------------------------------------------------------------
db_tune() {
    local ram_mb
    ram_mb="$(get_total_ram_mb)"
    local innodb_pool_size
    local max_conn

    if (( ram_mb < 1024 )); then
        innodb_pool_size="64M"
        max_conn=50
    elif (( ram_mb < 2048 )); then
        innodb_pool_size="128M"
        max_conn=100
    elif (( ram_mb < 4096 )); then
        innodb_pool_size="256M"
        max_conn=150
    elif (( ram_mb < 8192 )); then
        innodb_pool_size="512M"
        max_conn=200
    else
        innodb_pool_size="1G"
        max_conn=300
    fi

    local conf_dir
    case "$OS_ID" in
        ubuntu|debian) conf_dir="/etc/mysql/mariadb.conf.d"   ;;
        almalinux)     conf_dir="/etc/my.cnf.d"               ;;
    esac

    mkdir -p "$conf_dir"
    cat > "${conf_dir}/uh-tuning.cnf" <<MARIADB
# UnderHost MariaDB tuning — generated $(date)
[mysqld]
innodb_buffer_pool_size = ${innodb_pool_size}
innodb_log_file_size    = 64M
innodb_flush_log_at_trx_commit = 2
innodb_flush_method     = O_DIRECT
max_connections         = ${max_conn}
query_cache_type        = 0
query_cache_size        = 0
slow_query_log          = 1
long_query_time         = 2
slow_query_log_file     = /var/log/mysql/slow.log
MARIADB

    mkdir -p /var/log/mysql
    ok "MariaDB tuned (innodb_buffer_pool: ${innodb_pool_size}, max_conn: ${max_conn})"
}
