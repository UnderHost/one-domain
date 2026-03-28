#!/usr/bin/env bash
# =============================================================================
#  modules/redis.sh — Redis installation and per-site configuration
# =============================================================================

redis_configure() {
    step "Configuring Redis"

    command -v redis-cli &>/dev/null || {
        warn "Redis not installed — installing now"
        case "$PKG_MGR" in
            apt) DEBIAN_FRONTEND=noninteractive apt-get install -y -q redis-server &>/dev/null ;;
            dnf) dnf install -y redis &>/dev/null ;;
        esac
    }

    local redis_conf="/etc/redis/redis.conf"
    [[ -f "$redis_conf" ]] || redis_conf="/etc/redis.conf"

    if [[ -f "$redis_conf" ]]; then
        # Bind to localhost only (security)
        sed -i 's/^bind .*/bind 127.0.0.1 ::1/' "$redis_conf" 2>/dev/null || true
        # Disable protected-mode override
        sed -i 's/^protected-mode .*/protected-mode yes/' "$redis_conf" 2>/dev/null || true
        # Require a password for Redis access
        local redis_pass
        redis_pass="$(gen_pass_alpha 32)"
        if ! grep -q "^requirepass" "$redis_conf"; then
            echo "requirepass ${redis_pass}" >> "$redis_conf"
        else
            sed -i "s/^requirepass .*/requirepass ${redis_pass}/" "$redis_conf"
        fi
        ok "Redis secured with password"
    fi

    systemctl enable --now redis 2>/dev/null \
        || systemctl enable --now redis-server 2>/dev/null \
        || warn "Could not enable Redis service"

    # Verify Redis is responding
    if redis-cli ping &>/dev/null 2>&1; then
        ok "Redis is running and responding"
    else
        warn "Redis ping failed — check /etc/redis/redis.conf"
    fi
}
