#!/usr/bin/env bash
# =============================================================================
#  UnderHost One-Domain — Status / Health Check Module
#  modules/status.sh
# =============================================================================

[[ -n "${_UH_STATUS_LOADED:-}" ]] && return 0
_UH_STATUS_LOADED=1

status_domain() {
    local dom="${1:-}"
    [[ -z "$dom" ]] && die "Usage: install status domain.com"

    step "Health check: ${dom}"

    local webroot="/var/www/${dom}/public"
    local conf_dir
    conf_dir="$(os_nginx_conf_dir 2>/dev/null || echo /etc/nginx/conf.d)"

    echo
    printf '  %b%-28s%b\n' "$_CLR_BOLD" "Component" "$_CLR_RESET"
    printf '  %s\n' "$(printf '─%.0s' {1..50})"

    # Services
    for svc in nginx mariadb fail2ban redis; do
        _status_svc "$svc"
    done

    # PHP-FPM
    _status_svc "$(os_php_fpm_service 2>/dev/null || echo php-fpm)"

    echo
    printf '  %b%-28s%b\n' "$_CLR_BOLD" "Domain: ${dom}" "$_CLR_RESET"
    printf '  %s\n' "$(printf '─%.0s' {1..50})"

    # Document root
    _status_check "Document root exists" "[[ -d '${webroot}' ]]"

    # Nginx vhost
    _status_check "Nginx vhost" "[[ -f '${conf_dir}/${dom}.conf' ]]"

    # PHP pool
    local pool_dir
    pool_dir="$(os_php_pool_dir 2>/dev/null || echo /etc/php-fpm.d)"
    _status_check "PHP-FPM pool" "[[ -f '${pool_dir}/${dom}.conf' ]]"

    # SSL certificate
    local cert="/etc/letsencrypt/live/${dom}/fullchain.pem"
    if [[ -f "$cert" ]]; then
        local expiry days_left
        expiry="$(openssl x509 -noout -enddate -in "$cert" 2>/dev/null | cut -d= -f2)"
        local expiry_epoch
        expiry_epoch="$(date -d "$expiry" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$expiry" +%s 2>/dev/null || echo 0)"
        local now_epoch
        now_epoch="$(date +%s)"
        days_left=$(( (expiry_epoch - now_epoch) / 86400 ))

        if (( days_left > 14 )); then
            printf '  %b✓%b  %-26s %b%s (%d days)%b\n' \
                "$_CLR_LGREEN" "$_CLR_RESET" "SSL certificate" \
                "$_CLR_LGREEN" "valid" "$days_left" "$_CLR_RESET"
        elif (( days_left > 0 )); then
            printf '  %b⚠%b  %-26s %b%s (%d days — renew soon)%b\n' \
                "$_CLR_YELLOW" "$_CLR_RESET" "SSL certificate" \
                "$_CLR_YELLOW" "expiring" "$days_left" "$_CLR_RESET"
        else
            printf '  %b✗%b  %-26s %bexpired%b\n' \
                "$_CLR_LRED" "$_CLR_RESET" "SSL certificate" \
                "$_CLR_LRED" "$_CLR_RESET"
        fi
    else
        printf '  %b✗%b  %-26s %bnot found%b\n' \
            "$_CLR_YELLOW" "$_CLR_RESET" "SSL certificate" \
            "$_CLR_YELLOW" "$_CLR_RESET"
    fi

    # WordPress
    if [[ -f "${webroot}/wp-includes/version.php" ]]; then
        local wp_ver
        wp_ver="$(grep "\$wp_version" "${webroot}/wp-includes/version.php" 2>/dev/null \
            | head -1 | sed "s/.*'\(.*\)'.*/\1/" || echo "unknown")"
        printf '  %b✓%b  %-26s %s\n' "$_CLR_LGREEN" "$_CLR_RESET" "WordPress" "v${wp_ver}"
    fi

    # Database connectivity
    local slug
    slug="$(slug_from_domain "$dom" 2>/dev/null | cut -c1-32 || echo "${dom//./_}")"
    local db_name="${slug}_db"
    if mysql -e "USE \`${db_name}\`;" 2>/dev/null; then
        printf '  %b✓%b  %-26s %s\n' "$_CLR_LGREEN" "$_CLR_RESET" "Database" "${db_name}"
    fi

    echo
}

_status_svc() {
    local svc="$1"
    local state
    state="$(systemctl is-active "$svc" 2>/dev/null || echo "not found")"
    case "$state" in
        active)
            printf '  %b✓%b  %-26s %bactive%b\n' \
                "$_CLR_LGREEN" "$_CLR_RESET" "$svc" "$_CLR_LGREEN" "$_CLR_RESET" ;;
        inactive)
            printf '  %b--%b  %-26s %binactive%b\n' \
                "$_CLR_DIM" "$_CLR_RESET" "$svc" "$_CLR_DIM" "$_CLR_RESET" ;;
        *)
            printf '  %b✗%b  %-26s %b%s%b\n' \
                "$_CLR_YELLOW" "$_CLR_RESET" "$svc" "$_CLR_YELLOW" "$state" "$_CLR_RESET" ;;
    esac
}

_status_check() {
    local label="$1"
    local test_cmd="$2"
    if eval "$test_cmd" 2>/dev/null; then
        printf '  %b✓%b  %s\n' "$_CLR_LGREEN" "$_CLR_RESET" "$label"
    else
        printf '  %b✗%b  %s\n' "$_CLR_YELLOW" "$_CLR_RESET" "$label"
    fi
}
