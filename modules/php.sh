#!/usr/bin/env bash
# =============================================================================
#  modules/php.sh — PHP-FPM per-domain pool configuration
# =============================================================================

php_configure_pool() {
    step "Configuring PHP-FPM pool for ${DOMAIN}"

    os_php_fpm_sock  # sets PHP_FPM_SOCK

    local pool_dir
    pool_dir="$(os_php_fpm_pool_dir)"
    local pool_file="${pool_dir}/${DOMAIN}.conf"

    # Create site system user if it doesn't exist
    local site_user="${DOMAIN//./_}"
    site_user="${site_user:0:32}"

    if ! id "$site_user" &>/dev/null; then
        useradd -r -s /usr/sbin/nologin \
            -d "${SITE_ROOT}" \
            -c "UnderHost site user for ${DOMAIN}" \
            "$site_user" \
            && ok "Created system user: ${site_user}" \
            || die "Could not create system user: ${site_user}"
    else
        ok "System user already exists: ${site_user}"
    fi

    local web_user
    web_user="$(os_web_user)"

    # Tune pool sizes based on RAM
    local ram_mb
    ram_mb="$(get_total_ram_mb)"
    local max_children start_servers min_spare max_spare

    if   (( ram_mb >= 8192 )); then max_children=200; start_servers=8;  min_spare=6;  max_spare=16
    elif (( ram_mb >= 4096 )); then max_children=100; start_servers=6;  min_spare=4;  max_spare=12
    elif (( ram_mb >= 2048 )); then max_children=50;  start_servers=4;  min_spare=3;  max_spare=8
    elif (( ram_mb >= 1024 )); then max_children=25;  start_servers=2;  min_spare=2;  max_spare=6
    else                            max_children=12;  start_servers=2;  min_spare=2;  max_spare=4
    fi

    # Isolated session directory
    local session_dir="/var/lib/php/sessions/${DOMAIN}"
    mkdir -p "$session_dir"
    chown "${site_user}:${site_user}" "$session_dir"
    chmod 700 "$session_dir"

    # Log directory
    mkdir -p /var/log/php-fpm

    mkdir -p "$pool_dir"

    cat > "${pool_file}" <<POOL
; =============================================================================
; UnderHost PHP-FPM Pool: ${DOMAIN}
; Generated: $(date)
; =============================================================================

[${DOMAIN}]

; ─── Identity ────────────────────────────────────────────────────────────────
user  = ${site_user}
group = ${site_user}

; ─── Socket ──────────────────────────────────────────────────────────────────
listen       = ${PHP_FPM_SOCK}
listen.owner = ${web_user}
listen.group = ${web_user}
listen.mode  = 0660

; ─── Process Manager ─────────────────────────────────────────────────────────
pm                   = dynamic
pm.max_children      = ${max_children}
pm.start_servers     = ${start_servers}
pm.min_spare_servers = ${min_spare}
pm.max_spare_servers = ${max_spare}
pm.max_requests      = 500
pm.status_path       = /fpm-status-${DOMAIN//\./-}

; ─── Timeouts ────────────────────────────────────────────────────────────────
request_terminate_timeout = 300
; request_slowlog_timeout = 5
; slowlog = /var/log/php-fpm/${DOMAIN}.slow.log

; ─── Security ────────────────────────────────────────────────────────────────
security.limit_extensions = .php
php_flag[display_errors]  = off
php_flag[log_errors]      = on

; ─── Logging ─────────────────────────────────────────────────────────────────
access.log           = /var/log/php-fpm/${DOMAIN}.access.log
php_value[error_log] = /var/log/php-fpm/${DOMAIN}.error.log

; ─── Sessions ────────────────────────────────────────────────────────────────
php_value[session.save_path] = ${session_dir}

; ─── Environment ─────────────────────────────────────────────────────────────
env[HOSTNAME] = \$HOSTNAME
env[PATH]     = /usr/local/bin:/usr/bin:/bin
env[TMP]      = /tmp
env[TMPDIR]   = /tmp
env[TEMP]     = /tmp
POOL

    ok "PHP-FPM pool written: ${pool_file}"

    # Remove the default www pool to prevent conflicts (Debian/Ubuntu)
    local default_pool="${pool_dir}/www.conf"
    if [[ -f "$default_pool" ]] && ! grep -q "^\[www\]" "$default_pool" &>/dev/null; then
        true
    elif [[ -f "$default_pool" ]]; then
        mv "$default_pool" "${default_pool}.disabled" 2>/dev/null || true
        ok "Default www pool disabled"
    fi

    # Restart PHP-FPM
    local fpm_svc
    fpm_svc="$(os_php_fpm_service)"
    systemctl restart "$fpm_svc" 2>/dev/null \
        || systemctl restart php-fpm 2>/dev/null \
        || warn "Could not restart PHP-FPM — check: systemctl status ${fpm_svc}"

    ok "PHP-FPM pool configured (max_children=${max_children}, RAM=${ram_mb}MB)"
}
