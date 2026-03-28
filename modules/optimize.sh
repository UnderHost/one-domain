#!/usr/bin/env bash
# =============================================================================
#  modules/optimize.sh — Performance tuning for Nginx / PHP-FPM / MariaDB / Redis
#
#  Usage:  install optimize domain.com
#          install --optimize-only
#          Called internally after install
# =============================================================================

optimize_tune() {
    step "Applying performance optimizations"

    local ram_mb
    ram_mb="$(get_total_ram_mb)"
    local cpu_cores
    cpu_cores="$(get_cpu_cores)"

    info "Server: ${cpu_cores} CPU core(s), ${ram_mb} MB RAM"

    _optimize_nginx_global "$cpu_cores"
    _optimize_php_opcache "$ram_mb"
    _optimize_mariadb "$ram_mb"
    [[ "${ENABLE_REDIS:-false}" == true ]] && _optimize_redis "$ram_mb"
    _optimize_swap "$ram_mb"

    ok "Performance tuning complete"
}

optimize_only() {
    local domain="${1:-${DOMAIN:-}}"
    os_detect
    section_banner "UnderHost: Optimize${domain:+ — $domain}"
    optimize_tune
    info "Restarting services to apply tuning"
    systemctl restart nginx 2>/dev/null || true
    systemctl restart mariadb 2>/dev/null || true
    for svc in php8.4-fpm php8.3-fpm php8.2-fpm php-fpm; do
        systemctl restart "$svc" 2>/dev/null && break || true
    done
    systemctl restart redis 2>/dev/null || true
    ok "Optimization applied and services restarted"
}

# ---------------------------------------------------------------------------
_optimize_nginx_global() {
    local cores="$1"
    local nginx_conf="/etc/nginx/nginx.conf"
    [[ -f "$nginx_conf" ]] || { warn "Nginx not installed — skipping Nginx tuning"; return; }

    step "Tuning Nginx (${cores} cores)"

    # worker_processes
    if grep -q "worker_processes" "$nginx_conf"; then
        sed -i "s/worker_processes\s\+[^;]*/worker_processes ${cores}/" "$nginx_conf" 2>/dev/null || true
    fi

    # worker_connections — tune in events block
    local events_conf="/etc/nginx/conf.d/underhost-performance.conf"
    cat > "$events_conf" <<NGINXPERF
# UnderHost — Nginx performance tuning
# Generated $(date)

# Connection efficiency
upstream_keepalive_requests 1000;

# Improve file serving
sendfile        on;
tcp_nopush      on;
tcp_nodelay     on;
keepalive_timeout 75;
keepalive_requests 100;
reset_timedout_connection on;
client_max_body_size 64m;
client_body_timeout 12;
client_header_timeout 12;
send_timeout 10;

# FastCGI cache zone (for WordPress microcache — opt-in per vhost)
fastcgi_cache_path /var/cache/nginx_fcgi
    levels=1:2
    keys_zone=UNDERHOST:64m
    inactive=60m
    max_size=512m
    use_temp_path=off;
NGINXPERF

    ok "Nginx performance config written: ${events_conf}"
    mkdir -p /var/cache/nginx_fcgi
    chown www-data:www-data /var/cache/nginx_fcgi 2>/dev/null \
        || chown nginx:nginx /var/cache/nginx_fcgi 2>/dev/null || true
}

# ---------------------------------------------------------------------------
_optimize_php_opcache() {
    local ram="$1"

    step "Tuning PHP OPcache (RAM: ${ram} MB)"

    # Determine memory tier
    local opcache_mem opcache_max_files opcache_revalidate
    if   (( ram >= 4096 )); then opcache_mem=256; opcache_max_files=20000; opcache_revalidate=2
    elif (( ram >= 2048 )); then opcache_mem=128; opcache_max_files=10000; opcache_revalidate=2
    elif (( ram >= 1024 )); then opcache_mem=64;  opcache_max_files=8000;  opcache_revalidate=60
    else                         opcache_mem=32;  opcache_max_files=4000;  opcache_revalidate=120
    fi

    # Find PHP config dirs
    local php_dirs=()
    while IFS= read -r -d '' dir; do
        php_dirs+=("$dir")
    done < <(find /etc/php -maxdepth 2 -name "fpm" -type d -print0 2>/dev/null)
    # Also try /etc/php.d for RHEL
    [[ -d /etc/php.d ]] && php_dirs+=("/etc/php.d")

    if [[ ${#php_dirs[@]} -eq 0 ]]; then
        warn "No PHP config directories found — skipping OPcache tuning"
        return
    fi

    for phpdir in "${php_dirs[@]}"; do
        local conf="${phpdir}/underhost-opcache.ini"
        cat > "$conf" <<OPCACHE
; UnderHost OPcache tuning — ${ram} MB RAM tier
; Generated $(date)
opcache.enable=1
opcache.memory_consumption=${opcache_mem}
opcache.interned_strings_buffer=16
opcache.max_accelerated_files=${opcache_max_files}
opcache.revalidate_freq=${opcache_revalidate}
opcache.validate_timestamps=1
opcache.save_comments=1
opcache.fast_shutdown=1
opcache.enable_cli=0
; JIT (PHP 8+)
opcache.jit_buffer_size=64M
opcache.jit=tracing
OPCACHE
        ok "OPcache tuning written: ${conf}"
    done
}

# ---------------------------------------------------------------------------
_optimize_mariadb() {
    local ram="$1"

    step "Tuning MariaDB (RAM: ${ram} MB)"

    # Determine tuning tier
    local innodb_buf query_cache_size max_conn
    if   (( ram >= 8192 )); then innodb_buf="4G"; query_cache_size="256M"; max_conn=500
    elif (( ram >= 4096 )); then innodb_buf="2G"; query_cache_size="128M"; max_conn=300
    elif (( ram >= 2048 )); then innodb_buf="1G"; query_cache_size="64M";  max_conn=200
    elif (( ram >= 1024 )); then innodb_buf="512M"; query_cache_size="32M"; max_conn=100
    else                         innodb_buf="256M"; query_cache_size="16M"; max_conn=50
    fi

    # Find MariaDB config location
    local mariadb_conf
    for f in /etc/mysql/mariadb.conf.d/99-underhost.cnf \
              /etc/my.cnf.d/99-underhost.cnf; do
        mariadb_conf="$f"
        mkdir -p "$(dirname "$f")"
        break
    done

    cat > "$mariadb_conf" <<MYCONF
# UnderHost MariaDB tuning — ${ram} MB RAM tier
# Generated $(date)

[mysqld]
# InnoDB
innodb_buffer_pool_size    = ${innodb_buf}
innodb_buffer_pool_instances = 2
innodb_log_file_size       = 256M
innodb_flush_log_at_trx_commit = 2
innodb_flush_method        = O_DIRECT
innodb_file_per_table      = 1
innodb_read_io_threads     = 4
innodb_write_io_threads    = 4

# Connections
max_connections            = ${max_conn}
max_allowed_packet         = 64M
connect_timeout            = 10
wait_timeout               = 300
interactive_timeout        = 300

# Query cache (MariaDB ≤10.5)
# query_cache_type           = 1
# query_cache_size           = ${query_cache_size}
# query_cache_limit          = 2M

# Temp tables
tmp_table_size             = 64M
max_heap_table_size        = 64M

# Logging (enable slow query log for tuning)
slow_query_log             = 1
slow_query_log_file        = /var/log/mysql/slow.log
long_query_time            = 2
MYCONF

    mkdir -p /var/log/mysql
    ok "MariaDB tuning written: ${mariadb_conf}"
    warn "Restart MariaDB to apply: systemctl restart mariadb"
}

# ---------------------------------------------------------------------------
_optimize_redis() {
    local ram="$1"

    command -v redis-cli &>/dev/null || { warn "Redis not installed — skipping Redis tuning"; return; }

    step "Tuning Redis (RAM: ${ram} MB)"

    local redis_max_mem
    if   (( ram >= 4096 )); then redis_max_mem="512mb"
    elif (( ram >= 2048 )); then redis_max_mem="256mb"
    elif (( ram >= 1024 )); then redis_max_mem="128mb"
    else                         redis_max_mem="64mb"
    fi

    local redis_conf="/etc/redis/redis.conf"
    [[ -f "$redis_conf" ]] || redis_conf="/etc/redis.conf"
    [[ -f "$redis_conf" ]] || { warn "Redis config not found"; return; }

    # Update maxmemory settings
    _redis_set_param "$redis_conf" "maxmemory"        "$redis_max_mem"
    _redis_set_param "$redis_conf" "maxmemory-policy" "allkeys-lru"
    _redis_set_param "$redis_conf" "save"             '""'  # disable RDB persistence for cache use
    _redis_set_param "$redis_conf" "appendonly"       "no"

    ok "Redis tuned: maxmemory=${redis_max_mem}, policy=allkeys-lru"
    warn "Restart Redis to apply: systemctl restart redis"
}

_redis_set_param() {
    local file="$1" key="$2" val="$3"
    if grep -q "^${key}" "$file" 2>/dev/null; then
        sed -i "s|^${key}.*|${key} ${val}|" "$file"
    else
        echo "${key} ${val}" >> "$file"
    fi
}

# ---------------------------------------------------------------------------
_optimize_swap() {
    local ram="$1"

    [[ "${CONFIGURE_SWAP:-true}" == false ]] && return

    # Only create swap if < 2 GB RAM and no swap exists
    local swap_mb
    swap_mb="$(awk '/SwapTotal/{printf "%.0f",$2/1024}' /proc/meminfo 2>/dev/null || echo 0)"

    if (( swap_mb > 0 )); then
        ok "Swap already configured (${swap_mb} MB) — skipping"
        return
    fi

    if (( ram >= 2048 )); then
        info "RAM ≥ 2 GB — swap creation skipped"
        return
    fi

    local swap_size_mb=1024
    (( ram < 512 )) && swap_size_mb=512

    step "Creating ${swap_size_mb} MB swap file"

    local swapfile="/swapfile"
    if [[ -f "$swapfile" ]]; then
        info "Swap file already exists at ${swapfile}"
        return
    fi

    fallocate -l "${swap_size_mb}M" "$swapfile" \
        || dd if=/dev/zero of="$swapfile" bs=1M count="${swap_size_mb}" 2>/dev/null

    chmod 600 "$swapfile"
    mkswap "$swapfile" &>/dev/null
    swapon "$swapfile"

    # Persist across reboots
    if ! grep -q "$swapfile" /etc/fstab; then
        echo "${swapfile} none swap sw 0 0" >> /etc/fstab
    fi

    # Lower swappiness for server workload
    sysctl vm.swappiness=10 &>/dev/null || true
    echo "vm.swappiness=10" > /etc/sysctl.d/99-underhost-swappiness.conf

    ok "Swap file created: ${swapfile} (${swap_size_mb} MB, swappiness=10)"
}
