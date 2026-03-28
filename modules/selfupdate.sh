#!/usr/bin/env bash
# =============================================================================
#  modules/selfupdate.sh — Self-update UnderHost installer from GitHub
#
#  Usage:  install update
#          install self-update
#          install --self-update
# =============================================================================

UNDERHOST_REPO_URL="${UNDERHOST_REPO_URL:-https://github.com/underhost/underhost/archive/refs/heads/main.tar.gz}"
UNDERHOST_RAW_BASE="${UNDERHOST_RAW_BASE:-https://raw.githubusercontent.com/underhost/underhost/main}"

selfupdate_run() {
    section_banner "UnderHost Self-Update"
    info "Current version: ${UNDERHOST_VERSION:-unknown}"
    info "Update source:   ${UNDERHOST_REPO_URL}"
    echo

    # Check connectivity
    if ! curl --silent --max-time 10 --head "${UNDERHOST_RAW_BASE}/install" \
            -o /dev/null -w "%{http_code}" | grep -q "^200"; then
        die "Cannot reach GitHub. Check your network connection."
    fi

    # Check for remote version
    local remote_version
    remote_version="$(curl --silent --max-time 10 \
        "${UNDERHOST_RAW_BASE}/install" \
        | grep -oP 'UNDERHOST_VERSION="\K[^"]+' | head -1 || echo "unknown")"

    info "Latest version: ${remote_version}"

    if [[ "$remote_version" == "${UNDERHOST_VERSION:-}" ]]; then
        ok "Already up to date (${UNDERHOST_VERSION})."
        return 0
    fi

    prompt_yn "Update from ${UNDERHOST_VERSION:-unknown} to ${remote_version}?" "y" \
        || { info "Update cancelled."; return 0; }

    local install_dir
    install_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

    local backup_dir="/root/underhost_backup_$(date +%Y%m%d_%H%M%S)"
    step "Backing up current installer to ${backup_dir}"
    cp -r "$install_dir" "$backup_dir"
    ok "Backup saved to ${backup_dir}"

    step "Downloading latest release"
    local tmp_dir
    tmp_dir="$(mktemp -d)"
    curl --fail --silent --location "${UNDERHOST_REPO_URL}" -o "${tmp_dir}/latest.tar.gz" \
        || die "Download failed. The release archive may not be available."

    tar -xzf "${tmp_dir}/latest.tar.gz" -C "${tmp_dir}" \
        || die "Failed to extract downloaded archive."

    # Find the extracted directory (varies: underhost-main, underhost-2026.x.x, etc.)
    local extracted_dir
    extracted_dir="$(find "${tmp_dir}" -mindepth 1 -maxdepth 1 -type d | head -1)"
    [[ -z "$extracted_dir" ]] && die "No directory found in downloaded archive."

    step "Installing updated files"
    # Copy files — preserve any local config overrides in config/
    rsync -a --delete \
        --exclude 'config/custom*.conf' \
        --exclude '*.bak' \
        "${extracted_dir}/" "${install_dir}/" \
        || die "Failed to copy updated files."

    chmod +x "${install_dir}/install"

    rm -rf "$tmp_dir"
    ok "Update complete — now at version ${remote_version}"
    info "Backup of previous version: ${backup_dir}"
}
