#!/usr/bin/env bash
# =============================================================================
#  UnderHost One-Domain — Performance Optimisation Module
#  modules/optimize.sh
# =============================================================================

[[ -n "${_UH_OPTIMIZE_LOADED:-}" ]] && return 0
_UH_OPTIMIZE_LOADED=1

optimize_tune() {
    step "Applying performance tuning"
    _optimize_nginx
    _optimize_swap
    ok "Performance tuning complete"
}

optimize_only() {
    local dom="${1:-}"
    optimize_tune
    [[ -n "$dom" ]] && info "Domain-specific PHP pool tuning is applied during install only."
}

# ---------------------------------------------------------------------------
# Nginx global performance settings
# ---------------------------------------------------------------------------
_optimize_nginx() {
    local nginx_conf="/etc/nginx/nginx.conf"
    [[ ! -f "$nginx_conf" ]] && { warn "nginx.conf not found"; return; }

    local cpu_count
    cpu_count="$(detect_cpu_count)"

    local ram_mb
    ram_mb="$(detect_ram_mb)"

    # worker_connections: scale with CPU, cap at 4096
    local worker_conn=$(( cpu_count * 1024 ))
    (( worker_conn > 4096 )) && worker_conn=4096

    _nginx_set() {
        local key="$1" val="$2"
        if grep -qE "^\\s*${key}\\s" "$nginx_conf"; then
            sed -i -E "s|^(\\s*)${key}\\s+.*|\\1${key} ${val};|" "$nginx_conf"
        else
            # Append to events block or http block as appropriate
            true
        fi
    }

    # worker_processes — top-level
    sed -i -E "s|^worker_processes\\s+.*;|worker_processes ${cpu_count};|" "$nginx_conf" 2>/dev/null || true

    # worker_connections — inside events {}
    sed -i -E "s|worker_connections\\s+[0-9]+;|worker_connections ${worker_conn};|" "$nginx_conf" 2>/dev/null || true

    # keepalive
    if ! grep -q 'keepalive_timeout' "$nginx_conf"; then
        sed -i '/http {/a\\    keepalive_timeout 65;' "$nginx_conf" 2>/dev/null || true
    fi

    # client body/header buffer
    if ! grep -q 'client_max_body_size' "$nginx_conf"; then
        sed -i '/http {/a\\    client_max_body_size 64m;' "$nginx_conf" 2>/dev/null || true
    fi

    # open_file_cache
    if ! grep -q 'open_file_cache' "$nginx_conf"; then
        sed -i '/http {/a\\    open_file_cache max=10000 inactive=20s;' "$nginx_conf" 2>/dev/null || true
        sed -i '/open_file_cache max/a\\    open_file_cache_valid 30s;' "$nginx_conf" 2>/dev/null || true
        sed -i '/open_file_cache_valid/a\\    open_file_cache_min_uses 2;' "$nginx_conf" 2>/dev/null || true
    fi

    nginx -t 2>/dev/null && svc_reload nginx \
        && ok "Nginx tuned: workers=${cpu_count} connections=${worker_conn}" \
        || warn "Nginx configuration error after tuning — check nginx.conf"
}

# ---------------------------------------------------------------------------
# Swap file — create if RAM < 2GB and no swap exists
# ---------------------------------------------------------------------------
_optimize_swap() {
    [[ "${CONFIGURE_SWAP:-true}" != true ]] && return

    local ram_mb
    ram_mb="$(detect_ram_mb)"

    # Already have swap?
    local existing_swap
    existing_swap="$(swapon --show=SIZE --noheadings 2>/dev/null | head -1 || true)"
    if [[ -n "$existing_swap" ]]; then
        ok "Swap already configured: ${existing_swap}"
        return
    fi

    if (( ram_mb >= 2048 )); then
        info "RAM >= 2GB (${ram_mb}MB) — skipping swap creation"
        return
    fi

    # Size: equal to RAM, min 512MB, max 4GB
    local swap_mb=$ram_mb
    (( swap_mb < 512  )) && swap_mb=512
    (( swap_mb > 4096 )) && swap_mb=4096

    local swap_file="/swapfile"

    info "Creating ${swap_mb}MB swap file at ${swap_file}..."

    # Use fallocate (faster) with dd fallback
    if command -v fallocate &>/dev/null; then
        fallocate -l "${swap_mb}M" "$swap_file"
    else
        dd if=/dev/zero of="$swap_file" bs=1M count="$swap_mb" status=none
    fi

    chmod 600 "$swap_file"
    mkswap "$swap_file" &>/dev/null
    swapon "$swap_file"

    # Make permanent
    if ! grep -q "$swap_file" /etc/fstab; then
        echo "${swap_file} none swap sw 0 0" >> /etc/fstab
    fi

    # Tune swappiness — lower = prefer RAM
    sysctl -w vm.swappiness=10 &>/dev/null || true
    if ! grep -q 'vm.swappiness' /etc/sysctl.conf; then
        echo 'vm.swappiness=10' >> /etc/sysctl.conf
    fi

    ok "Swap created: ${swap_mb}MB at ${swap_file} (swappiness=10)"
}
