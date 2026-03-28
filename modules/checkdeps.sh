#!/usr/bin/env bash
# =============================================================================
#  UnderHost One-Domain — Dependency / Connectivity Checker
#  modules/checkdeps.sh
# =============================================================================
# Command: install check-deps
# Verifies all external resources are reachable before install.
# Also checks local tool availability and system readiness.
# =============================================================================

[[ -n "${_UH_CHECKDEPS_LOADED:-}" ]] && return 0
_UH_CHECKDEPS_LOADED=1

checkdeps_run() {
    step "Pre-flight dependency check"
    echo

    local failures=0

    # --- Local tools ---
    printf '%b  Required tools%b\n' "$_CLR_BOLD" "$_CLR_RESET"
    local tools=(curl wget gnupg2 openssl tar rsync bc python3 systemctl)
    for tool in "${tools[@]}"; do
        if command -v "$tool" &>/dev/null; then
            printf '    %b✓%b  %s\n' "$_CLR_LGREEN" "$_CLR_RESET" "$tool"
        else
            printf '    %b✗%b  %s %b(not found)%b\n' \
                "$_CLR_LRED" "$_CLR_RESET" "$tool" "$_CLR_YELLOW" "$_CLR_RESET"
            failures=$(( failures + 1 ))
        fi
    done
    echo

    # --- Package manager ---
    printf '%b  Package manager%b\n' "$_CLR_BOLD" "$_CLR_RESET"
    os_detect 2>/dev/null || true
    case "${OS_PKG_MGR:-}" in
        apt)
            if apt-get -qq check 2>/dev/null; then
                printf '    %b✓%b  apt is functional\n' "$_CLR_LGREEN" "$_CLR_RESET"
            else
                printf '    %b⚠%b  apt has errors — run: apt-get -f install\n' "$_CLR_YELLOW" "$_CLR_RESET"
            fi
            ;;
        dnf)
            if dnf check &>/dev/null; then
                printf '    %b✓%b  dnf is functional\n' "$_CLR_LGREEN" "$_CLR_RESET"
            else
                printf '    %b⚠%b  dnf has errors\n' "$_CLR_YELLOW" "$_CLR_RESET"
            fi
            ;;
        *)
            printf '    %b⚠%b  Package manager unknown\n' "$_CLR_YELLOW" "$_CLR_RESET"
            ;;
    esac
    echo

    # --- External connectivity ---
    printf '%b  External connectivity%b\n' "$_CLR_BOLD" "$_CLR_RESET"
    local endpoints=(
        "Let's Encrypt ACME:https://acme-v02.api.letsencrypt.org"
        "WordPress.org:https://wordpress.org"
        "WP-CLI builds:https://raw.githubusercontent.com/wp-cli/builds"
        "PHP repo (sury):https://packages.sury.org"
        "REMI repo:https://rpms.remirepo.net"
        "GitHub raw:https://raw.githubusercontent.com"
        "PyPI:https://pypi.org"
        "MariaDB repo:https://downloads.mariadb.com"
    )

    for entry in "${endpoints[@]}"; do
        local label="${entry%%:*}"
        local url="${entry#*:}"
        if curl -fsSL --max-time 6 --head "$url" &>/dev/null; then
            printf '    %b✓%b  %s\n' "$_CLR_LGREEN" "$_CLR_RESET" "$label"
        else
            printf '    %b✗%b  %s %b(unreachable — %s)%b\n' \
                "$_CLR_LRED" "$_CLR_RESET" "$label" \
                "$_CLR_YELLOW" "$url" "$_CLR_RESET"
            failures=$(( failures + 1 ))
        fi
    done
    echo

    # --- DNS resolution ---
    printf '%b  DNS resolution%b\n' "$_CLR_BOLD" "$_CLR_RESET"
    local dns_tests=(wordpress.org github.com letsencrypt.org)
    for host in "${dns_tests[@]}"; do
        if getent hosts "$host" &>/dev/null || dig +short "$host" &>/dev/null; then
            printf '    %b✓%b  %s resolves\n' "$_CLR_LGREEN" "$_CLR_RESET" "$host"
        else
            printf '    %b✗%b  %s %b(DNS resolution failed)%b\n' \
                "$_CLR_LRED" "$_CLR_RESET" "$host" "$_CLR_YELLOW" "$_CLR_RESET"
            failures=$(( failures + 1 ))
        fi
    done
    echo

    # --- System readiness ---
    printf '%b  System readiness%b\n' "$_CLR_BOLD" "$_CLR_RESET"

    local ram_mb
    ram_mb="$(detect_ram_mb)"
    if (( ram_mb >= 1024 )); then
        printf '    %b✓%b  RAM: %d MB\n' "$_CLR_LGREEN" "$_CLR_RESET" "$ram_mb"
    elif (( ram_mb >= 512 )); then
        printf '    %b⚠%b  RAM: %d MB (low — recommend 1 GB+)\n' "$_CLR_YELLOW" "$_CLR_RESET" "$ram_mb"
    else
        printf '    %b✗%b  RAM: %d MB (too low — install may fail)\n' "$_CLR_LRED" "$_CLR_RESET" "$ram_mb"
        failures=$(( failures + 1 ))
    fi

    local free_mb
    free_mb=$(( $(df -k / | awk 'NR==2{print $4}') / 1024 ))
    if (( free_mb >= 4096 )); then
        printf '    %b✓%b  Disk free: %d MB on /\n' "$_CLR_LGREEN" "$_CLR_RESET" "$free_mb"
    elif (( free_mb >= 2048 )); then
        printf '    %b⚠%b  Disk free: %d MB on / (low)\n' "$_CLR_YELLOW" "$_CLR_RESET" "$free_mb"
    else
        printf '    %b✗%b  Disk free: %d MB on / (insufficient — need 4 GB+)\n' \
            "$_CLR_LRED" "$_CLR_RESET" "$free_mb"
        failures=$(( failures + 1 ))
    fi

    # Port 80/443 not already in use by something else
    for port in 80 443; do
        if ss -tlnp 2>/dev/null | grep -q ":${port} " && ! systemctl is-active nginx &>/dev/null; then
            printf '    %b⚠%b  Port %d in use by another process\n' \
                "$_CLR_YELLOW" "$_CLR_RESET" "$port"
        else
            printf '    %b✓%b  Port %d available\n' "$_CLR_LGREEN" "$_CLR_RESET" "$port"
        fi
    done
    echo

    # --- Summary ---
    if (( failures == 0 )); then
        ok "All checks passed — ready to install."
    else
        warn "${failures} check(s) failed. Resolve the issues above before installing."
        return 1
    fi
}
