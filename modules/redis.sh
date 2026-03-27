#!/usr/bin/env bash
# =============================================================================
#  modules/redis.sh — Redis installation and configuration
# =============================================================================

redis_configure() {
    step "Installing and configuring Redis"

    case "$PKG_MGR" in
        apt) DEBIAN_FRONTEND=noninteractive apt-get install -y -qq redis-server ;;
        dnf) dnf -y -q install redis ;;
    esac

    local ram_mb
    ram_mb="$(get_total_ram_mb)"
    local max_memory=$(( ram_mb / 8 ))
    (( max_memory < 64 )) && max_memory=64

    # Secure Redis: bind localhost only, disable protected-mode warning
    local redis_conf="/etc/redis/redis.conf"
    [[ -f /etc/redis.conf ]] && redis_conf="/etc/redis.conf"

    if [[ -f "$redis_conf" ]]; then
        # Bind to localhost only
        sed -i 's/^bind .*/bind 127.0.0.1 -::1/' "$redis_conf"
        # Set sensible max memory
        sed -i "s/^# maxmemory .*/maxmemory ${max_memory}mb/" "$redis_conf"
        grep -q "^maxmemory " "$redis_conf" \
            || echo "maxmemory ${max_memory}mb" >> "$redis_conf"
        sed -i "s/^# maxmemory-policy .*/maxmemory-policy allkeys-lru/" "$redis_conf"
        grep -q "^maxmemory-policy " "$redis_conf" \
            || echo "maxmemory-policy allkeys-lru" >> "$redis_conf"
        # Disable remote access
        sed -i 's/^protected-mode no/protected-mode yes/' "$redis_conf"
    fi

    systemctl enable redis --now 2>/dev/null \
        || systemctl enable redis-server --now 2>/dev/null \
        || warn "Could not enable Redis service"

    ok "Redis installed (max memory: ${max_memory}MB, localhost only)"
}
