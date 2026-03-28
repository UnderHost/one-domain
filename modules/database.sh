#!/usr/bin/env bash
# =============================================================================
#  modules/database.sh — MariaDB database and user management
# =============================================================================

db_create() {
    step "Setting up MariaDB database for ${DOMAIN}"

    _db_secure_install
    _db_create_database
    _db_setup_logrotate

    ok "Database '${DB_NAME}' and user '${DB_USER}' created"
}

# ---------------------------------------------------------------------------
_db_secure_install() {
    # Only run if root has no password set (fresh install)
    if mysql -u root --connect-timeout=3 -e "SELECT 1;" &>/dev/null 2>&1; then
        info "MariaDB root accessible via unix socket — securing"

        mysql -u root <<SQL 2>/dev/null
-- Set root password
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MYSQL_ROOT_PASS}';
-- Remove anonymous users
DELETE FROM mysql.user WHERE User='';
-- Remove remote root
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost','127.0.0.1','::1');
-- Drop test database
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
SQL
        ok "MariaDB secured (root password set)"
    else
        info "MariaDB root already requires a password — skipping initial secure setup"
    fi
}

# ---------------------------------------------------------------------------
_db_create_database() {
    mysql -u root -p"${MYSQL_ROOT_PASS}" <<SQL \
        || die "Failed to create database — check MariaDB root password"
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`
    CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost'
    IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
FLUSH PRIVILEGES;
SQL
}

# ---------------------------------------------------------------------------
_db_setup_logrotate() {
    local logrotate_file="/etc/logrotate.d/underhost-${DOMAIN//\./-}"
    cat > "$logrotate_file" <<LOGROTATE
/var/log/nginx/${DOMAIN}*.log
/var/log/php-fpm/${DOMAIN}*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    sharedscripts
    postrotate
        nginx -s reopen 2>/dev/null || true
    endscript
}
LOGROTATE
    ok "Log rotation configured"
}

# ---------------------------------------------------------------------------
# Verify database connection (used by repair/diagnose)
db_test_connection() {
    local db_pass="${1:-$MYSQL_ROOT_PASS}"
    if mysql -u root -p"${db_pass}" --connect-timeout=3 \
            -e "SELECT 1;" &>/dev/null 2>&1; then
        return 0
    fi
    return 1
}
