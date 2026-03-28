#!/usr/bin/env bash
# =============================================================================
#  UnderHost One-Domain — Self-Update Module
#  modules/selfupdate.sh
# =============================================================================

[[ -n "${_UH_SELFUPDATE_LOADED:-}" ]] && return 0
_UH_SELFUPDATE_LOADED=1

_GITHUB_RAW="https://raw.githubusercontent.com/UnderHost/one-domain/main"
_GITHUB_API="https://api.github.com/repos/UnderHost/one-domain/commits/main"

selfupdate_run() {
    step "Checking for updates"

    # Fetch latest commit SHA from GitHub API
    local latest_sha
    latest_sha="$(curl -fsSL --max-time 10 "$_GITHUB_API" 2>/dev/null \
        | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['sha'][:8])" 2>/dev/null \
        || echo "unknown")"

    info "Current version: v${UNDERHOST_VERSION}"
    info "Latest commit:   ${latest_sha}"

    if ! prompt_yn 'Download and apply the latest version?' 'y'; then
        info "Update skipped."
        return
    fi

    local tmp_dir
    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "${tmp_dir}"' EXIT

    # Download updated install script
    local new_install="${tmp_dir}/install"
    if ! curl -fsSL --max-time 30 \
            "${_GITHUB_RAW}/install" -o "$new_install"; then
        die "Could not download update from ${_GITHUB_RAW}/install"
    fi

    # Basic sanity check — must be a bash script
    if ! head -1 "$new_install" | grep -q 'bash'; then
        die "Downloaded file does not look like a bash script — aborting update"
    fi

    # Compare checksums
    local current_sum new_sum
    current_sum="$(sha256sum "${SCRIPT_DIR}/install" 2>/dev/null | awk '{print $1}')"
    new_sum="$(sha256sum "$new_install" | awk '{print $1}')"

    if [[ "$current_sum" == "$new_sum" ]]; then
        ok "Already up to date — no changes applied"
        return
    fi

    # Back up current install
    local backup="${SCRIPT_DIR}/install.bak.$(date +%Y%m%d_%H%M%S)"
    cp "${SCRIPT_DIR}/install" "$backup"
    ok "Current install backed up to: ${backup}"

    # Replace install script
    chmod +x "$new_install"
    mv "$new_install" "${SCRIPT_DIR}/install"
    ok "install script updated"

    # Download and update lib/ and modules/
    _selfupdate_fetch_dir "lib"
    _selfupdate_fetch_dir "modules"

    ok "Self-update complete. New version is active."
    info "Run 'install version' to confirm the new version."
}

_selfupdate_fetch_dir() {
    local dir="$1"
    local api_url="https://api.github.com/repos/UnderHost/one-domain/contents/${dir}"

    # Get file list from GitHub API
    local files
    files="$(curl -fsSL --max-time 15 "$api_url" 2>/dev/null \
        | python3 -c "
import sys, json
items = json.load(sys.stdin)
for item in items:
    if item.get('type') == 'file':
        print(item['name'])
" 2>/dev/null || true)"

    if [[ -z "$files" ]]; then
        warn "Could not fetch file list for ${dir}/ — skipping"
        return
    fi

    local file
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        local dest="${SCRIPT_DIR}/${dir}/${file}"
        local tmp_file
        tmp_file="$(mktemp)"

        if curl -fsSL --max-time 20 \
                "${_GITHUB_RAW}/${dir}/${file}" -o "$tmp_file" 2>/dev/null; then
            # Only replace if changed
            local old_sum new_sum
            old_sum="$(sha256sum "$dest" 2>/dev/null | awk '{print $1}')"
            new_sum="$(sha256sum "$tmp_file" | awk '{print $1}')"
            if [[ "$old_sum" != "$new_sum" ]]; then
                cp "$tmp_file" "$dest"
                ok "Updated: ${dir}/${file}"
            fi
        else
            warn "Could not update ${dir}/${file}"
        fi
        rm -f "$tmp_file"
    done <<< "$files"
}
