#!/usr/bin/env bash
# =============================================================================
#  UnderHost One-Domain — WP-CLI Helper Library
#  lib/wpcli.sh
# =============================================================================
# Moved from modules/wpcli.sh — this is a utility library, not a lifecycle
# module, and belongs in lib/ alongside core.sh.
# =============================================================================

[[ -n "${_UH_WPCLI_LOADED:-}" ]] && return 0
_UH_WPCLI_LOADED=1

_WPCLI_BIN="/usr/local/bin/wp"
_WPCLI_URL="https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar"
_WPCLI_CHECKSUM_URL="https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar.sha512"

# ---------------------------------------------------------------------------
# Install WP-CLI if not present or update if outdated
# ---------------------------------------------------------------------------
wpcli_install() {
    if command -v wp &>/dev/null; then
        local current_ver
        current_ver="$(wp cli version --allow-root 2>/dev/null | awk '{print $2}')"
        ok "WP-CLI already installed: v${current_ver}"
        return 0
    fi

    step "Installing WP-CLI"

    local tmp_phar
    tmp_phar="$(mktemp /tmp/wp-cli.XXXXXX.phar)"

    # Download
    if ! curl -fsSL --max-time 60 "$_WPCLI_URL" -o "$tmp_phar"; then
        rm -f "$tmp_phar"
        die "Failed to download WP-CLI from ${_WPCLI_URL}"
    fi

    # Verify checksum
    local expected_sum
    expected_sum="$(curl -fsSL --max-time 10 "$_WPCLI_CHECKSUM_URL" 2>/dev/null | awk '{print $1}')"

    if [[ -n "$expected_sum" ]]; then
        local actual_sum
        actual_sum="$(sha512sum "$tmp_phar" | awk '{print $1}')"
        if [[ "$expected_sum" != "$actual_sum" ]]; then
            rm -f "$tmp_phar"
            die "WP-CLI checksum verification failed — download may be corrupt or tampered"
        fi
        ok "WP-CLI checksum verified"
    else
        warn "Could not fetch WP-CLI checksum — proceeding without verification"
    fi

    # Install
    chmod +x "$tmp_phar"
    mv "$tmp_phar" "$_WPCLI_BIN"

    local installed_ver
    installed_ver="$(wp cli version --allow-root 2>/dev/null | awk '{print $2}')"
    ok "WP-CLI installed: v${installed_ver} → ${_WPCLI_BIN}"
}

# ---------------------------------------------------------------------------
# Run a wp command as the site's system user (safer than --allow-root)
# Falls back to --allow-root if the user doesn't exist
# ---------------------------------------------------------------------------
wp_run() {
    local dom="${1:-$DOMAIN}"
    shift
    local webroot="/var/www/${dom}/public"
    local sys_user
    sys_user="$(slug_from_domain "$dom" | cut -c1-16)_web"

    if id "$sys_user" &>/dev/null; then
        sudo -u "$sys_user" wp --path="$webroot" "$@"
    else
        wp --path="$webroot" --allow-root "$@"
    fi
}
