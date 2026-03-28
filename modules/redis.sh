#!/usr/bin/env bash
# =============================================================================
#  UnderHost One-Domain — Redis Module
#  modules/redis.sh
# =============================================================================

[[ -n "${_UH_REDIS_LOADED:-}" ]] && return 0
_UH_REDIS_LOADED=1

redis_configure() {
    step "Configuring Redis"

    pkg_install_redis

    local conf_file
    conf_file="$(_redis_conf_path)"

    [[ ! -f "$conf_file" ]] && { warn "Redis config not found at ${conf_file}"; return; }

    # Back up original once
    [[ ! -f "${conf_file}.uh_orig" ]] && cp "$conf_file" "${conf_file}.uh_orig"

    local ram_mb
    ram_mb="$(detect_ram_mb)"

    # Max memory: 10% of RAM, minimum 64MB, maximum 512MB
    local max_mem_mb=$(( ram_mb / 10 ))
    (( max_mem_mb < 64  )) && max_mem_mb=64
    (( max_mem_mb > 512 )) && max_mem_mb=512

    _redis_set() {
        local key="$1" val="$2"
        if grep -qE "^#?\\s*${key}\\s" "$conf_file"; then
            sed -i -E "s|^#?\\s*${key}\\s.*|${key} ${val}|" "$conf_file"
        else
            echo "${key} ${val}" >> "$conf_file"
        fi
    }

    # Security: bind to localhost only — never expose to network
    _redis_set "bind"              "127.0.0.1 ::1"
    _redis_set "protected-mode"    "yes"
    _redis_set "port"              "6379"

    # Memory management
    _redis_set "maxmemory"         "${max_mem_mb}mb"
    _redis_set "maxmemory-policy"  "allkeys-lru"

    # Persistence: disable AOF for cache-only usage (reduces I/O)
    _redis_set "appendonly"        "no"
    _redis_set "save"              "\"\""   # disable RDB snapshots for cache-only

    # Unix socket for PHP — faster than TCP for same-host connections
    _redis_set "unixsocket"        "/run/redis/redis.sock"
    _redis_set "unixsocketperm"    "770"

    # Logging
    _redis_set "loglevel"          "notice"
    _redis_set "logfile"           "/var/log/redis/redis-server.log"

    # Give the web user access to the Redis socket
    local redis_grp
    case "$OS_FAMILY" in
        debian) redis_grp="redis" ;;
        rhel)   redis_grp="redis" ;;
    esac

    # Add nginx user and the domain system user to redis group
    usermod -aG "$redis_grp" nginx 2>/dev/null || true
    local sys_user
    sys_user="$(slug_from_domain "${DOMAIN:-localhost}" | cut -c1-16)_web"
    usermod -aG "$redis_grp" "$sys_user" 2>/dev/null || true

    svc_reload "$(_redis_svc)"
    ok "Redis configured: maxmemory=${max_mem_mb}MB, bind=127.0.0.1, socket=/run/redis/redis.sock"
}

_redis_conf_path() {
    if   [[ -f /etc/redis/redis.conf ]];   then echo "/etc/redis/redis.conf"
    elif [[ -f /etc/redis.conf ]];          then echo "/etc/redis.conf"
    else echo "/etc/redis/redis.conf"
    fi
}

_redis_svc() {
    systemctl list-units --type=service --all 2>/dev/null \
        | grep -o 'redis[^ ]*' | head -1 || echo "redis"
}
