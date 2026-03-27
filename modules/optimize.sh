#!/usr/bin/env bash
# =============================================================================
#  modules/optimize.sh — Auto-tune Nginx, PHP-FPM, MariaDB based on resources
# =============================================================================

optimize_tune() {
    [[ "$TUNE_SERVICES" == true ]] || return
    step "Auto-tuning services based on server resources"

    local ram_mb cpu
    ram_mb="$(get_total_ram_mb)"
    cpu="$(get_cpu_cores)"

    info "Resources: ${ram_mb}MB RAM · ${cpu} CPU cores"

    _optimize_swap "$ram_mb"
    _optimize_nginx "$cpu" "$ram_mb"
    _optimize_php_fpm "$ram_mb" "$cpu"
    db_tune   # defined in database.sh
    ok "Service tuning complete"
}

# ---------------------------------------------------------------------------
_optimize_swap() {
    local ram_mb="$1"
    [[ "$CONFIGURE_SWAP" != true ]] && return
    [[ -f /swapfile ]] && { ok "Swap already configured"; return; }

    # Only add swap if RAM < 2 GB
    (( ram_mb >= 2048 )) && return

    local swap_size="1G"
    local swap_blocks=1024   # MB — matches 1G default
    if (( ram_mb < 512 )); then
        swap_size="512M"
        swap_blocks=512
    fi

    info "Configuring ${swap_size} swap (low-RAM server)"
    fallocate -l "$swap_size" /swapfile 2>/dev/null \
        || dd if=/dev/zero of=/swapfile bs=1M count="${swap_blocks}" 2>/dev/null
    chmod 600 /swapfile
    mkswap /swapfile &>/dev/null
    swapon /swapfile

    # Persist across reboots
    grep -q '/swapfile' /etc/fstab \
        || echo '/swapfile none swap sw 0 0' >> /etc/fstab

    # Reduce swappiness for web servers
    sysctl -w vm.swappiness=10 &>/dev/null
    grep -q 'vm.swappiness' /etc/sysctl.d/99-underhost.conf 2>/dev/null \
        || echo 'vm.swappiness = 10' >> /etc/sysctl.d/99-underhost.conf

    ok "Swap (${swap_size}) enabled"
}

# ---------------------------------------------------------------------------
_optimize_nginx() {
    local cpu="$1"
    local ram_mb="$2"

    local nginx_conf="/etc/nginx/nginx.conf"
    [[ -f "$nginx_conf" ]] || return

    # worker_processes — one per CPU core
    sed -i "s/worker_processes[[:space:]]\+[^;]*/worker_processes ${cpu}/" "$nginx_conf"

    # worker_connections — scale with RAM, cap at 4096
    local worker_conn=$(( cpu * 1024 ))
    (( worker_conn > 4096 )) && worker_conn=4096
    sed -i "s/worker_connections[[:space:]]\+[0-9]\+/worker_connections ${worker_conn}/" "$nginx_conf"

    # Write a performance snippet if not present
    local perf_snippet="/etc/nginx/conf.d/uh-perf.conf"
    if [[ ! -f "$perf_snippet" ]]; then
        cat > "$perf_snippet" <<NGINXPERF
# UnderHost Nginx performance tuning
# Do not edit — managed by installer

# Connection efficiency
keepalive_timeout  65;
keepalive_requests 1000;
sendfile           on;
tcp_nopush         on;
tcp_nodelay        on;

# Buffer sizes
client_body_buffer_size    128k;
client_max_body_size       64m;
client_header_buffer_size  1k;
large_client_header_buffers 4 8k;
output_buffers             1 32k;
postpone_output            1460;

# Timeouts
client_header_timeout  30;
client_body_timeout    30;
send_timeout           60;
reset_timedout_connection on;

# Open file cache
open_file_cache          max=10000 inactive=20s;
open_file_cache_valid    30s;
open_file_cache_min_uses 2;
open_file_cache_errors   on;

# Hide Nginx version
server_tokens off;
NGINXPERF
    fi

    nginx -t 2>/dev/null && systemctl reload nginx
    ok "Nginx tuned (${cpu} workers, ${worker_conn} connections)"
}

# ---------------------------------------------------------------------------
_optimize_php_fpm() {
    local ram_mb="$1"
    local cpu="$2"

    # Per-domain pool was already written in php.sh; here we tune global PHP-FPM settings
    local global_conf=""
    case "$OS_ID" in
        ubuntu|debian) global_conf="/etc/php/${PHP_VERSION}/fpm/php-fpm.conf" ;;
        almalinux)     global_conf="/etc/php-fpm.conf" ;;
    esac

    [[ -f "$global_conf" ]] || return

    # Emergency restart after 3 failed children
    grep -q 'emergency_restart_threshold' "$global_conf" \
        || cat >> "$global_conf" <<PHPFPMGLOBAL

; UnderHost tuning
emergency_restart_threshold = 3
emergency_restart_interval   = 1m
process_control_timeout      = 10s
PHPFPMGLOBAL

    # Tune php.ini upload/memory limits
    local php_ini=""
    case "$OS_ID" in
        ubuntu|debian) php_ini="/etc/php/${PHP_VERSION}/fpm/php.ini" ;;
        almalinux)     php_ini="/etc/php.ini" ;;
    esac

    local mem_limit="256M"
    (( ram_mb >= 4096 )) && mem_limit="512M"

    if [[ -f "$php_ini" ]]; then
        sed -i "s/^memory_limit = .*/memory_limit = ${mem_limit}/"        "$php_ini"
        sed -i "s/^upload_max_filesize = .*/upload_max_filesize = 64M/"   "$php_ini"
        sed -i "s/^post_max_size = .*/post_max_size = 64M/"               "$php_ini"
        sed -i "s/^max_execution_time = .*/max_execution_time = 300/"     "$php_ini"
        sed -i "s/^max_input_time = .*/max_input_time = 300/"             "$php_ini"
        sed -i "s/^expose_php = .*/expose_php = Off/"                     "$php_ini"
        sed -i "s/^;date.timezone.*/date.timezone = UTC/"                 "$php_ini"
    fi

    local php_fpm_svc
    php_fpm_svc="$(os_php_fpm_service)"
    systemctl restart "$php_fpm_svc" 2>/dev/null || true
    ok "PHP-FPM tuned (memory_limit: ${mem_limit:-256M})"
}
