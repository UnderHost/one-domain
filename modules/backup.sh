#!/usr/bin/env bash
# =============================================================================
#  UnderHost One-Domain — Backup & Restore Module
#  modules/backup.sh
# =============================================================================
# Commands:
#   backup_domain          install backup <domain>
#   backup_schedule        install backup-auto <domain>
#   backup_restore         install restore <domain>
#   backup_list            install backup-list <domain>
#   backup_prune           called internally by timer
# =============================================================================

[[ -n "${_UH_BACKUP_LOADED:-}" ]] && return 0
_UH_BACKUP_LOADED=1

# Defaults — override via /etc/underhost/defaults.conf or ~/.one-domain.conf
BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/underhost}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-14}"
BACKUP_REMOTE_DEST="${BACKUP_REMOTE_DEST:-}"  # rsync:user@host:/path  OR  rclone:remote:bucket

# ---------------------------------------------------------------------------
# On-demand full backup — files + database
# ---------------------------------------------------------------------------
backup_domain() {
    local dom="${1:-$DOMAIN}"
    [[ -z "$dom" ]] && die "Usage: install backup domain.com"
    _validate_domain "$dom"

    local site_root="/var/www/${dom}"
    [[ ! -d "$site_root" ]] && die "Site root not found: ${site_root}"

    local slug ts backup_dir archive_path db_dump
    slug="$(slug_from_domain "$dom")"
    ts="$(date +%Y%m%d_%H%M%S)"
    backup_dir="${BACKUP_ROOT}/${dom}"
    archive_path="${backup_dir}/${slug}_${ts}.tar.gz"
    db_dump="${backup_dir}/${slug}_${ts}.sql.gz"

    step "Creating backup for ${dom}"
    mkdir -p "$backup_dir"
    chmod 700 "$backup_dir"

    # 1 — Database dump
    local db_name="${slug}_db"
    if mysql -e "USE \`${db_name}\`;" 2>/dev/null; then
        info "Dumping database: ${db_name}"
        if mysqldump --defaults-extra-file=/root/.my.cnf \
                "$db_name" 2>/dev/null | gzip -9 > "$db_dump"; then
            chmod 600 "$db_dump"
            ok "Database backup: ${db_dump} ($(du -sh "$db_dump" | cut -f1))"
        else
            warn "Database dump failed — skipping DB backup"
            rm -f "$db_dump"
        fi
    else
        info "No database '${db_name}' found — skipping DB backup"
    fi

    # 2 — Site files
    info "Archiving site files: ${site_root}"
    tar -czf "$archive_path" \
        --exclude="${site_root}/tmp" \
        --exclude="${site_root}/logs" \
        -C /var/www "$dom" 2>/dev/null
    chmod 600 "$archive_path"
    ok "Files backup: ${archive_path} ($(du -sh "$archive_path" | cut -f1))"

    # 3 — Remote sync (optional)
    if [[ -n "$BACKUP_REMOTE_DEST" ]]; then
        _backup_remote_sync "$backup_dir" "$dom"
    fi

    # 4 — Prune old backups
    backup_prune "$dom"

    ok "Backup complete for ${dom}"
    info "Location: ${backup_dir}"
}

# ---------------------------------------------------------------------------
# List available backups for a domain
# ---------------------------------------------------------------------------
backup_list() {
    local dom="${1:-}"
    [[ -z "$dom" ]] && die "Usage: install backup-list domain.com"

    local backup_dir="${BACKUP_ROOT}/${dom}"
    if [[ ! -d "$backup_dir" ]]; then
        info "No backups found for ${dom}"
        return 0
    fi

    step "Available backups for ${dom}"
    echo
    printf '  %-50s  %s\n' "File" "Size"
    printf '  %s\n' "$(printf '─%.0s' {1..60})"

    local found=0
    while IFS= read -r f; do
        printf '  %-50s  %s\n' "$(basename "$f")" "$(du -sh "$f" | cut -f1)"
        found=$(( found + 1 ))
    done < <(find "$backup_dir" -maxdepth 1 -type f \( -name '*.tar.gz' -o -name '*.sql.gz' \) | sort -r)

    echo
    [[ "$found" -eq 0 ]] && info "No backup archives found in ${backup_dir}"
    info "Retention: ${BACKUP_RETENTION_DAYS} days  |  Location: ${backup_dir}"
}

# ---------------------------------------------------------------------------
# Interactive restore from a backup archive
# ---------------------------------------------------------------------------
backup_restore() {
    local dom="${1:-}"
    [[ -z "$dom" ]] && die "Usage: install restore domain.com"
    _validate_domain "$dom"

    local backup_dir="${BACKUP_ROOT}/${dom}"
    [[ ! -d "$backup_dir" ]] && die "No backups found for ${dom} in ${backup_dir}"

    step "Restore wizard for ${dom}"

    # Collect available archives
    local archives=()
    while IFS= read -r f; do
        archives+=("$(basename "$f")")
    done < <(find "$backup_dir" -maxdepth 1 -name '*.tar.gz' -type f | sort -r)

    [[ "${#archives[@]}" -eq 0 ]] && die "No file archives found in ${backup_dir}"

    local chosen
    chosen="$(prompt_select 'Select backup to restore:' "${archives[@]}")"
    local archive_path="${backup_dir}/${chosen}"

    warn "This will OVERWRITE /var/www/${dom} with the selected backup."
    prompt_yn "Proceed with restore?" "n" || die "Restore cancelled."

    # Restore files
    step "Restoring files from ${chosen}"
    local site_parent="/var/www"
    local site_root="/var/www/${dom}"

    # Move current to safety first
    local safe_dir="/var/www/${dom}_pre_restore_$(date +%Y%m%d_%H%M%S)"
    [[ -d "$site_root" ]] && mv "$site_root" "$safe_dir" && info "Existing site moved to: ${safe_dir}"

    tar -xzf "$archive_path" -C "$site_parent" 2>/dev/null
    ok "Files restored to: ${site_root}"

    # Look for matching DB dump (same timestamp)
    local ts_part
    ts_part="$(basename "$chosen" .tar.gz | grep -oP '\d{8}_\d{6}' || true)"
    local slug
    slug="$(slug_from_domain "$dom")"
    local db_dump="${backup_dir}/${slug}_${ts_part}.sql.gz"

    if [[ -f "$db_dump" ]]; then
        if prompt_yn "Matching database backup found — restore it too?" "y"; then
            local db_name="${slug}_db"
            info "Restoring database: ${db_name}"
            zcat "$db_dump" | mysql "$db_name" 2>/dev/null \
                && ok "Database restored: ${db_name}" \
                || warn "Database restore failed — restore manually from ${db_dump}"
        fi
    else
        info "No matching database backup found for this archive timestamp"
    fi

    # Fix ownership
    local sys_user
    sys_user="$(slug_from_domain "$dom" | cut -c1-16)_web"
    id "$sys_user" &>/dev/null && chown -R "${sys_user}:${sys_user}" "$site_root"

    svc_reload nginx 2>/dev/null || true

    ok "Restore complete for ${dom}"
    info "Pre-restore files saved at: ${safe_dir}"
}

# ---------------------------------------------------------------------------
# Install systemd timer for automatic scheduled backups
# ---------------------------------------------------------------------------
backup_schedule() {
    local dom="${1:-$DOMAIN}"
    [[ -z "$dom" ]] && die "Usage: install backup-auto domain.com"

    local schedule="${BACKUP_SCHEDULE:-daily}"   # daily | weekly
    local slug
    slug="$(slug_from_domain "$dom")"
    local unit_name="underhost-backup-${slug}"

    step "Installing scheduled backup for ${dom} (${schedule})"

    # Write backup script
    local script_path="/usr/local/sbin/uh_backup_${slug}.sh"
    cat > "$script_path" <<SCRIPT
#!/usr/bin/env bash
# Auto-generated by UnderHost One-Domain installer
# Domain: ${dom}
set -euo pipefail
SCRIPT_DIR="${SCRIPT_DIR}"
source "\${SCRIPT_DIR}/lib/core.sh"
source "\${SCRIPT_DIR}/modules/backup.sh"
BACKUP_ROOT="${BACKUP_ROOT}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS}"
BACKUP_REMOTE_DEST="${BACKUP_REMOTE_DEST}"
LOG_FILE="/var/log/underhost_backup_${slug}.log"
_init_log
backup_domain "${dom}"
SCRIPT
    chmod 700 "$script_path"

    # Systemd service unit
    cat > "/etc/systemd/system/${unit_name}.service" <<UNIT
[Unit]
Description=UnderHost backup — ${dom}
After=network.target mariadb.service

[Service]
Type=oneshot
ExecStart=${script_path}
StandardOutput=journal
StandardError=journal
UNIT

    # Systemd timer unit
    local on_calendar="daily"
    [[ "$schedule" == "weekly" ]] && on_calendar="weekly"

    cat > "/etc/systemd/system/${unit_name}.timer" <<TIMER
[Unit]
Description=UnderHost backup timer — ${dom}

[Timer]
OnCalendar=${on_calendar}
RandomizedDelaySec=1800
Persistent=true

[Install]
WantedBy=timers.target
TIMER

    systemctl daemon-reload
    systemctl enable --now "${unit_name}.timer" 2>/dev/null
    ok "Backup timer installed: ${unit_name}.timer (${schedule})"
    info "Manual run: systemctl start ${unit_name}.service"
    info "View logs:  journalctl -u ${unit_name}.service -n 50"
}

# ---------------------------------------------------------------------------
# Prune backups older than BACKUP_RETENTION_DAYS
# ---------------------------------------------------------------------------
backup_prune() {
    local dom="${1:-$DOMAIN}"
    local backup_dir="${BACKUP_ROOT}/${dom}"
    [[ ! -d "$backup_dir" ]] && return 0

    local pruned=0
    while IFS= read -r old; do
        rm -f "$old"
        pruned=$(( pruned + 1 ))
    done < <(find "$backup_dir" -maxdepth 1 -type f \
        \( -name '*.tar.gz' -o -name '*.sql.gz' \) \
        -mtime "+${BACKUP_RETENTION_DAYS}" 2>/dev/null)

    [[ "$pruned" -gt 0 ]] && ok "Pruned ${pruned} old backup(s) (>${BACKUP_RETENTION_DAYS} days)"
}

# ---------------------------------------------------------------------------
# Remote sync — rsync or rclone
# ---------------------------------------------------------------------------
_backup_remote_sync() {
    local src_dir="$1"
    local dom="$2"

    if [[ "$BACKUP_REMOTE_DEST" == rsync:* ]]; then
        local dest="${BACKUP_REMOTE_DEST#rsync:}"
        if command -v rsync &>/dev/null; then
            rsync -az --quiet "${src_dir}/" "${dest}/${dom}/" 2>/dev/null \
                && ok "Synced to remote: ${dest}/${dom}" \
                || warn "Remote rsync failed — check BACKUP_REMOTE_DEST"
        else
            warn "rsync not installed — skipping remote sync"
        fi

    elif [[ "$BACKUP_REMOTE_DEST" == rclone:* ]]; then
        local dest="${BACKUP_REMOTE_DEST#rclone:}"
        if command -v rclone &>/dev/null; then
            rclone copy "$src_dir" "${dest}/${dom}" --quiet 2>/dev/null \
                && ok "Synced to rclone: ${dest}/${dom}" \
                || warn "rclone sync failed — check BACKUP_REMOTE_DEST and rclone config"
        else
            warn "rclone not installed — skipping remote sync"
            info "Install rclone: https://rclone.org/install/"
        fi
    fi
}
