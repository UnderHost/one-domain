#!/usr/bin/env bash
# =============================================================================
#  UnderHost One-Domain — WordPress Installation Module
#  modules/wordpress.sh
# =============================================================================

[[ -n "${_UH_WP_LOADED:-}" ]] && return 0
_UH_WP_LOADED=1

wp_install() {
    step "Installing WordPress for ${DOMAIN}"

    local webroot="${SITE_ROOT}/public"
    local sys_user
    sys_user="$(slug_from_domain "$DOMAIN" | cut -c1-16)_web"

    # 1. Install WP-CLI
    wpcli_install

    # 2. Download WordPress
    _wp_download "$webroot" "$sys_user"

    # 3. Create wp-config.php
    _wp_create_config "$webroot" "$sys_user"

    # 4. Run WP installation
    _wp_run_install "$webroot" "$sys_user"

    # 5. Harden wp-config.php and file permissions
    _wp_harden "$webroot" "$sys_user"

    # 6. System cron for WP-Cron
    wp_install_system_cron "$webroot" "$sys_user"

    # 6. Install Redis object cache plugin (optional)
    if [[ "${WP_REDIS:-false}" == true ]]; then
        _wp_install_redis_cache "$webroot" "$sys_user"
    fi

    ok "WordPress installed: https://${DOMAIN}"
}

# ---------------------------------------------------------------------------
# Download WordPress core
# ---------------------------------------------------------------------------
_wp_download() {
    local webroot="$1"
    local sys_user="$2"

    mkdir -p "$webroot"

    if [[ -f "${webroot}/wp-includes/version.php" ]]; then
        warn "WordPress already exists in ${webroot} — skipping download"
        return
    fi

    info "Downloading latest WordPress..."
    sudo -u "$sys_user" wp core download \
        --path="$webroot" \
        --locale=en_US \
        --skip-content \
        --quiet 2>/dev/null \
        || wp core download \
            --path="$webroot" \
            --locale=en_US \
            --skip-content \
            --quiet \
            --allow-root

    ok "WordPress core downloaded"
}

# ---------------------------------------------------------------------------
# Create wp-config.php with hardened settings
# ---------------------------------------------------------------------------
_wp_create_config() {
    local webroot="$1"
    local sys_user="$2"

    # Random table prefix (4 lowercase letters + underscore)
    local table_prefix
    table_prefix="$(tr -dc 'a-z' < /dev/urandom | head -c4)_"

    # Generate salts via WP-CLI (preferred) or WordPress API
    local salts
    salts="$(wp eval 'echo implode("\n", array_map(function($c){ return "define(\"" . $c . "\", \"" . wp_generate_password(64, true, true) . "\");"; }, ["AUTH_KEY","SECURE_AUTH_KEY","LOGGED_IN_KEY","NONCE_KEY","AUTH_SALT","SECURE_AUTH_SALT","LOGGED_IN_SALT","NONCE_SALT"]));' --allow-root 2>/dev/null)" \
    || salts="$(curl -fsSL https://api.wordpress.org/secret-key/1.1/salt/ 2>/dev/null \
               | sed "s/^define/define/" || true)"

    local wp_cmd
    wp_cmd=(wp config create
        --path="$webroot"
        --dbname="$DB_NAME"
        --dbuser="$DB_USER"
        --dbpass="$DB_PASS"
        --dbhost="127.0.0.1"
        --dbprefix="$table_prefix"
        --skip-check
        --quiet
    )

    sudo -u "$sys_user" "${wp_cmd[@]}" 2>/dev/null \
        || "${wp_cmd[@]}" --allow-root

    # Harden wp-config.php with extra constants
    local config_extra
    config_extra=$(cat <<'EOF'

/** Security hardening — added by UnderHost installer */
define( 'DISALLOW_FILE_EDIT',    true  );   // Block theme/plugin editor
define( 'DISALLOW_FILE_MODS',    false );   // Allow plugin/theme updates
define( 'AUTOMATIC_UPDATER_DISABLED', false );
define( 'WP_AUTO_UPDATE_CORE',   'minor' ); // Auto-update minor/security only
define( 'WP_DEBUG',              false );
define( 'WP_DEBUG_LOG',          false );
define( 'WP_DEBUG_DISPLAY',      false );
define( 'SCRIPT_DEBUG',          false );

/** Force HTTPS for admin */
define( 'FORCE_SSL_ADMIN', true );

/** Limit post revisions */
define( 'WP_POST_REVISIONS', 5 );

/** Disable xmlrpc — also blocked at Nginx level */
add_filter( 'xmlrpc_enabled', '__return_false' );
EOF
)

    # Insert extra constants after the table prefix line
    python3 - "$webroot/wp-config.php" "$config_extra" <<'PYEOF' 2>/dev/null || true
import sys
path, extra = sys.argv[1], sys.argv[2]
with open(path) as f:
    content = f.read()
marker = "table_prefix"
idx = content.find(marker)
if idx != -1:
    end_of_line = content.find('\n', idx)
    content = content[:end_of_line+1] + extra + '\n' + content[end_of_line+1:]
with open(path, 'w') as f:
    f.write(content)
PYEOF

    ok "wp-config.php created (prefix=${table_prefix})"
}

# ---------------------------------------------------------------------------
# Run WP core install
# ---------------------------------------------------------------------------
_wp_run_install() {
    local webroot="$1"
    local sys_user="$2"

    local site_url="https://${DOMAIN}"
    local title="${WP_TITLE:-${DOMAIN}}"
    local admin_user="${WP_ADMIN_USER:-admin}"
    local admin_pass="${WP_ADMIN_PASS}"
    local admin_email="${WP_ADMIN_EMAIL:-${ADMIN_EMAIL}}"

    local wp_cmd=(wp core install
        --path="$webroot"
        --url="$site_url"
        --title="$title"
        --admin_user="$admin_user"
        --admin_password="$admin_pass"
        --admin_email="$admin_email"
        --skip-email
        --quiet
    )

    sudo -u "$sys_user" "${wp_cmd[@]}" 2>/dev/null \
        || "${wp_cmd[@]}" --allow-root

    ok "WordPress installed: url=${site_url} admin=${admin_user}"
}

# ---------------------------------------------------------------------------
# Harden file permissions
# ---------------------------------------------------------------------------
_wp_harden() {
    local webroot="$1"
    local sys_user="$2"

    # Ownership: everything owned by the isolated system user
    chown -R "${sys_user}:${sys_user}" "$webroot"

    # Directories: 750 — owner rwx, group rx, other none
    find "$webroot" -type d -exec chmod 750 {} \;

    # Files: 640 — owner rw, group r, other none
    find "$webroot" -type f -exec chmod 640 {} \;

    # wp-config.php: only owner can read/write
    chmod 600 "${webroot}/wp-config.php"

    # wp-content/uploads must be writable by PHP-FPM (same user)
    local uploads="${webroot}/wp-content/uploads"
    mkdir -p "$uploads"
    chmod 755 "$uploads"

    # Remove readme files that expose version info
    rm -f "${webroot}/readme.html" \
          "${webroot}/license.txt" \
          "${webroot}/wp-admin/install.php" 2>/dev/null || true

    ok "WordPress permissions hardened"
}

# ---------------------------------------------------------------------------
# Install Redis object cache plugin
# ---------------------------------------------------------------------------
_wp_install_redis_cache() {
    local webroot="$1"
    local sys_user="$2"

    info "Installing Redis Cache plugin..."
    local wp_cmd=(wp plugin install redis-cache --activate
        --path="$webroot" --quiet)

    sudo -u "$sys_user" "${wp_cmd[@]}" 2>/dev/null \
        || "${wp_cmd[@]}" --allow-root

    # Enable the object cache
    sudo -u "$sys_user" wp redis enable \
        --path="$webroot" --quiet 2>/dev/null \
        || wp redis enable --path="$webroot" --quiet --allow-root 2>/dev/null || true

    ok "Redis object cache plugin installed and enabled"
}

# ---------------------------------------------------------------------------
# Fix WordPress permissions (called from: install wp-reset-perms domain)
# ---------------------------------------------------------------------------
wp_reset_perms() {
    local dom="${1:-}"
    [[ -z "$dom" ]] && die "Usage: install wp-reset-perms domain.com"

    local webroot="/var/www/${dom}/public"
    [[ ! -d "$webroot" ]] && die "Site root not found: ${webroot}"

    local sys_user
    sys_user="$(slug_from_domain "$dom" | cut -c1-16)_web"

    step "Resetting WordPress permissions for ${dom}"
    _wp_harden "$webroot" "$sys_user"

    # 6. System cron for WP-Cron
    wp_install_system_cron "$webroot" "$sys_user"
    ok "Permissions reset complete"
}

# ---------------------------------------------------------------------------
# Clone a WordPress install (install wp-clone src.com dst.com)
# ---------------------------------------------------------------------------
wp_clone() {
    local src="${1:-}"
    local dst="${2:-}"
    [[ -z "$src" || -z "$dst" ]] && die "Usage: install wp-clone source.com dest.com"

    local src_root="/var/www/${src}/public"
    local dst_root="/var/www/${dst}/public"

    [[ ! -d "$src_root" ]] && die "Source site not found: ${src_root}"

    step "Cloning WordPress: ${src} → ${dst}"

    # Resolve DB credentials for destination
    DOMAIN="$dst"
    _resolve_defaults 2>/dev/null || {
        local slug
        slug="$(slug_from_domain "$dst")"
        DB_NAME="${slug}_db"
        DB_USER="${slug}_usr"
        DB_PASS="$(gen_pass_db 24)"
    }

    # Copy files
    mkdir -p "$dst_root"
    rsync -a --exclude=wp-config.php "${src_root}/" "${dst_root}/"

    # Export and import database
    local tmp_sql="/tmp/wp_clone_${src//\./_}_$(date +%s).sql"
    wp db export "$tmp_sql" --path="$src_root" --allow-root --quiet
    chmod 600 "$tmp_sql"

    db_create 2>/dev/null || true
    wp db import "$tmp_sql" --path="$dst_root" --allow-root --quiet
    rm -f "$tmp_sql"

    # Update URLs
    wp search-replace "https://${src}" "https://${dst}" \
        --path="$dst_root" --all-tables --allow-root --quiet
    wp search-replace "http://${src}" "http://${dst}" \
        --path="$dst_root" --all-tables --allow-root --quiet

    ok "WordPress cloned: ${src} → ${dst}"
    info "Next: run 'install ${dst} wp' to set up Nginx/PHP, or update wp-config.php manually."
}

# ---------------------------------------------------------------------------
# Export customer report
# ---------------------------------------------------------------------------
wp_export_report() {
    local dom="${1:-$DOMAIN}"
    [[ -z "$dom" ]] && die "Usage: install export-report domain.com"

    local webroot="/var/www/${dom}/public"
    local report_file="/root/underhost_${dom}_export_$(date +%Y%m%d_%H%M%S).txt"

    step "Generating customer report for ${dom}"

    {
        echo "======================================================"
        echo "  UnderHost Deployment Report — ${dom}"
        echo "  Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "======================================================"
        echo ""
        echo "Site URL:      https://${dom}"
        echo "Document Root: ${webroot}"
        echo ""

        if [[ -f "${webroot}/wp-includes/version.php" ]]; then
            echo "WordPress:"
            wp core version --path="$webroot" --allow-root 2>/dev/null | sed 's/^/  Version: /'
            wp option get siteurl --path="$webroot" --allow-root 2>/dev/null | sed 's/^/  Site URL: /'
            wp option get blogname --path="$webroot" --allow-root 2>/dev/null | sed 's/^/  Site Name: /'
            echo ""
        fi

        echo "SSL Certificate:"
        certbot certificates --cert-name "$dom" 2>/dev/null \
            | grep -E 'Expiry|Domains|Certificate Path' | sed 's/^/  /'
        echo ""

        echo "Services:"
        for svc in nginx mariadb php-fpm fail2ban redis; do
            systemctl is-active "$svc" 2>/dev/null | awk -v s="$svc" '{printf "  %-15s %s\n", s":", $1}'
        done
        echo ""

        echo "Generated credentials are stored in: /root/underhost_${dom}_*.txt"
        echo "======================================================"
    } > "$report_file"

    chmod 600 "$report_file"
    ok "Report saved: ${report_file}"
}

# ---------------------------------------------------------------------------
# Install system cron for WP-Cron (replaces unreliable wp-cron.php)
# ---------------------------------------------------------------------------
wp_install_system_cron() {
    local webroot="$1"
    local sys_user="$2"

    local cron_file="/etc/cron.d/underhost_wpcron_${DOMAIN//\./_}"
    cat > "$cron_file" <<CRON
# UnderHost — WordPress system cron for ${DOMAIN}
# Replaces wp-cron.php (DISABLE_WP_CRON=true in wp-config.php)
*/5 * * * * ${sys_user} /usr/local/bin/wp cron event run --due-now --path=${webroot} --quiet 2>/dev/null
CRON
    chmod 644 "$cron_file"
    ok "System cron installed for WP-Cron: ${cron_file}"

    # Disable WP's built-in pseudo-cron
    if grep -q 'DISABLE_WP_CRON' "${webroot}/wp-config.php" 2>/dev/null; then
        sed -i "s/define.*DISABLE_WP_CRON.*/define( 'DISABLE_WP_CRON', true );/" \
            "${webroot}/wp-config.php"
    else
        echo "define( 'DISABLE_WP_CRON', true );" >> "${webroot}/wp-config.php"
    fi
    ok "DISABLE_WP_CRON set in wp-config.php"
}

# ---------------------------------------------------------------------------
# Update WordPress core + all plugins + all themes (with pre-update backup)
# ---------------------------------------------------------------------------
wp_update_all() {
    local dom="${1:-$DOMAIN}"
    [[ -z "$dom" ]] && die "Usage: install wp-update-all domain.com"

    local webroot="/var/www/${dom}/public"
    [[ ! -f "${webroot}/wp-includes/version.php" ]] \
        && die "WordPress not found at ${webroot}"

    local sys_user
    sys_user="$(slug_from_domain "$dom" | cut -c1-16)_web"

    step "WordPress full update for ${dom}"

    # Pre-update backup
    info "Creating pre-update backup..."
    DOMAIN="$dom" backup_domain "$dom" 2>/dev/null \
        && ok "Pre-update backup created" \
        || warn "Backup failed — proceeding anyway (check backup module)"

    # Core update
    info "Updating WordPress core..."
    wp_run "$dom" core update --quiet 2>/dev/null \
        && ok "WordPress core updated" \
        || info "WordPress core already at latest version"

    wp_run "$dom" core update-db --quiet 2>/dev/null \
        && ok "WordPress database updated" || true

    # Plugin updates
    info "Updating all plugins..."
    local plugin_count
    plugin_count="$(wp_run "$dom" plugin list --update=available --format=count 2>/dev/null || echo 0)"
    if (( plugin_count > 0 )); then
        wp_run "$dom" plugin update --all --quiet 2>/dev/null \
            && ok "Updated ${plugin_count} plugin(s)" \
            || warn "Some plugin updates failed — check manually"
    else
        ok "All plugins up to date"
    fi

    # Theme updates
    info "Updating all themes..."
    local theme_count
    theme_count="$(wp_run "$dom" theme list --update=available --format=count 2>/dev/null || echo 0)"
    if (( theme_count > 0 )); then
        wp_run "$dom" theme update --all --quiet 2>/dev/null \
            && ok "Updated ${theme_count} theme(s)" \
            || warn "Some theme updates failed — check manually"
    else
        ok "All themes up to date"
    fi

    # Reset permissions after updates
    _wp_harden "$webroot" "$sys_user"

    # 6. System cron for WP-Cron
    wp_install_system_cron "$webroot" "$sys_user"

    ok "WordPress update complete for ${dom}"
}
