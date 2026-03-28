#!/usr/bin/env bash
# =============================================================================
#  UnderHost One-Domain — List Module
#  modules/list.sh
# =============================================================================
# Command: install list
# Lists all domains managed by the installer on this server.
# Reads from /var/www/ and cross-references Nginx vhosts + SSL certs.
# =============================================================================

[[ -n "${_UH_LIST_LOADED:-}" ]] && return 0
_UH_LIST_LOADED=1

list_domains() {
    step "Managed domains on this server"
    echo

    local conf_dir
    conf_dir="$(os_nginx_conf_dir 2>/dev/null || echo /etc/nginx/conf.d)"

    # Discover domains from /var/www/ directories
    local domains=()
    while IFS= read -r d; do
        local dom
        dom="$(basename "$d")"
        # Skip non-domain directories
        [[ "$dom" == html || "$dom" == lost+found || "$dom" == cgi-bin ]] && continue
        domains+=("$dom")
    done < <(find /var/www -mindepth 1 -maxdepth 1 -type d | sort)

    if [[ "${#domains[@]}" -eq 0 ]]; then
        info "No domains found in /var/www/"
        info "Deploy one with: install domain.com php"
        return 0
    fi

    # Header
    printf '  %b%-30s %-6s %-10s %-12s %-18s %s%b\n' \
        "$_CLR_BOLD" \
        "Domain" "Mode" "PHP" "SSL" "Services" "Disk" \
        "$_CLR_RESET"
    printf '  %s\n' "$(printf '─%.0s' {1..90})"

    local total_domains=0
    for dom in "${domains[@]}"; do
        _list_domain_row "$dom" "$conf_dir"
        total_domains=$(( total_domains + 1 ))
    done

    echo
    printf '  %b%d domain(s) found%b\n' "$_CLR_DIM" "$total_domains" "$_CLR_RESET"
    echo
    info "For details: install status domain.com"
    info "For full diagnostic: install diagnose domain.com"
}

_list_domain_row() {
    local dom="$1"
    local conf_dir="$2"
    local site_root="/var/www/${dom}"

    # Mode — detect by WordPress presence
    local mode="php"
    [[ -f "${site_root}/public/wp-includes/version.php" ]] && mode="wp"

    # PHP version — read from FPM pool file
    local php_ver="-"
    local pool_file
    for pool_dir in /etc/php/*/fpm/pool.d /etc/php-fpm.d; do
        if [[ -f "${pool_dir}/${dom}.conf" ]]; then
            php_ver="$(grep -oP 'php\K[0-9.]+' <<< "$pool_dir" | head -1)"
            [[ -z "$php_ver" ]] && php_ver="?"
            break
        fi
    done

    # SSL status + expiry
    local ssl_status="✗ none"
    local cert="/etc/letsencrypt/live/${dom}/fullchain.pem"
    if [[ -f "$cert" ]]; then
        local exp_epoch now_epoch days
        exp_epoch="$(openssl x509 -noout -enddate -in "$cert" 2>/dev/null \
            | cut -d= -f2 | xargs -I{} date -d '{}' +%s 2>/dev/null || echo 0)"
        now_epoch="$(date +%s)"
        days=$(( (exp_epoch - now_epoch) / 86400 ))
        if (( days > 14 )); then
            ssl_status="✓ ${days}d"
        elif (( days > 0 )); then
            ssl_status="⚠ ${days}d"
        else
            ssl_status="✗ expired"
        fi
    fi

    # Services — nginx, php-fpm, db
    local svc_str=""
    systemctl is-active nginx    &>/dev/null && svc_str+="nginx "
    systemctl is-active mariadb  &>/dev/null && svc_str+="db "
    local php_svc="php${php_ver}-fpm"
    systemctl is-active "$php_svc" &>/dev/null \
        || systemctl is-active php-fpm &>/dev/null \
        && svc_str+="php "

    # Disk usage
    local disk
    disk="$(du -sh "${site_root}" 2>/dev/null | cut -f1 || echo "?")"

    # Color by SSL status
    local col="$_CLR_RESET"
    [[ "$ssl_status" == *"✗"* ]] && col="$_CLR_YELLOW"
    [[ "$ssl_status" == *"expired"* ]] && col="$_CLR_LRED"

    printf '  %b%-30s %-6s %-10s %-12s %-18s %s%b\n' \
        "$col" \
        "$dom" "$mode" "$php_ver" "$ssl_status" "${svc_str:-none}" "$disk" \
        "$_CLR_RESET"
}
