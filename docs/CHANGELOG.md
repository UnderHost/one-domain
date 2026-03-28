# Changelog

All notable changes to UnderHost One-Domain are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).  
Versioning follows `YYYY.MINOR.PATCH`.

---

## [Unreleased]

---

## [2026.3.0] — 2026-03-28

### Security
- Hardened `mysqldump` backup: now uses `--defaults-extra-file=/root/.my.cnf` to prevent root password exposure on the process list
- Added PHP version validation against supported list before any package operations — prevents arbitrary string injection into package names
- Unified `hardening.sh` and removed orphaned `harden.sh` (double-source risk eliminated)
- Added `kernel.kptr_restrict=2` and `kernel.dmesg_restrict=1` to sysctl hardening
- PHP APT repository now uses `signed-by=` keyring files instead of deprecated `apt-key`
- Nginx vhost now includes `limit_req_zone` for wp-login.php rate limiting
- Added Fail2Ban filter for `nginx-limit-req` (tracks rate-limited requests)
- SFTP chroot setup validates `sshd -t` before reloading to prevent sshd misconfiguration

### Fixed
- PHP-FPM service name fallback on Debian/Ubuntu was wrong (`php-fpm` → `phpX.Y-fpm`)
- Module loader now aborts with a clear fatal error if a required module is missing, rather than continuing with a warning (incomplete installs were silently broken)
- `_resolve_defaults()` now pre-generates all staging and FTP credentials so they are available even if modules run in isolation

### Added
- `lib/core.sh`: double-source guard, tty-aware color output (no escape codes in pipes/logs), `write_file()` atomic write helper, `_validate_email()`, `svc_enable_start()`, `svc_reload()`
- `lib/wpcli.sh`: WP-CLI helper library moved from `modules/` — includes SHA-512 checksum verification on download
- `modules/os.sh`: `_version_gte()` for proper version comparison; `os_mariadb_conf()` path resolver; explicit AlmaLinux 10 support
- `modules/packages.sh`: `pkg_install_composer()` with checksum verification
- `modules/status.sh`: SSL certificate expiry days shown in health output
- `modules/diagnose.sh`: PHP-FPM error log tail included in diagnostic output
- `modules/selfupdate.sh`: SHA-256 checksum comparison before applying updates
- `modules/uninstall.sh`: double confirmation (domain name must be typed) before destructive removal
- `modules/summary.sh`: color-coded security checklist in post-install terminal output
- `.shellcheckrc`: project-level ShellCheck configuration
- `.editorconfig`: consistent indentation across editors
- `CONTRIBUTING.md`: contribution guide with code standards, testing checklist, and commit format
- `SECURITY.md`: vulnerability disclosure policy and security design notes
- `.github/workflows/shellcheck.yml`: CI linting on push/PR plus repository structure validation
- `configs/examples/nginx-vhost.conf.example`: reference vhost configuration
- `configs/examples/php-fpm-pool.conf.example`: reference PHP-FPM pool configuration
- `install version` / `--version` command

### Changed
- `modules/os.sh`: dropped all legacy CentOS 7/8, Ubuntu 20/22, Debian 11, Rocky Linux support paths
- `modules/packages.sh`: REMI PHP repo pinned per AlmaLinux major version (9 vs 10)
- `modules/nginx.sh`: added `server_tokens off` injection, HTTP/2 via `http2 on` directive (nginx 1.25.1+ syntax), improved gzip and FastCGI buffer settings
- `modules/php.sh`: default `www.conf` pool disabled on install (security: prevents www-data running globally)
- `modules/database.sh`: MariaDB tuning block uses idempotency marker to prevent duplicate entries
- `modules/redis.sh`: Unix socket configured for PHP communication (faster than TCP loopback); domain system user and nginx user added to redis group
- `modules/ssl.sh`: OCSP stapling enabled via `--staple-ocsp` certbot flag; deploy hook ensures Nginx reloads after renewal
- `modules/staging.sh`: `X-Robots-Tag: noindex` set at HTTP header level (not just meta tag) for search engine isolation
- `modules/wordpress.sh`: WP-CLI uses SHA-512 checksum verification; `readme.html` and `license.txt` removed to reduce version fingerprinting
- `modules/ftp.sh`: vsftpd TLS ciphers hardened; SFTP chroot validates sshd config before applying
- README: license badge corrected from GPLv2 to GPL-3.0

### Removed
- `modules/harden.sh` — duplicate of `modules/hardening.sh`, caused double-source risk
- `config/` directory — duplicate/ambiguous, superseded by `configs/`

---

## [2026.2.0] — 2026-02-01

### Added
- Initial public release with full modular architecture
- Support for Ubuntu 24.04, Debian 12, AlmaLinux 9
- PHP-mode and WordPress-mode deployment
- Interactive wizard (`--interactive`, `--basic`, `--advanced`)
- Let's Encrypt SSL with auto-renewal
- Fail2Ban with SSH and Nginx jails
- Redis object cache support
- WordPress staging environment
- FTP with TLS (vsftpd) and SFTP-only modes
- Post-install summary with credential report
- Maintenance commands: `status`, `diagnose`, `repair`, `logs`, `ssl-renew-test`
- WordPress tools: `wp-reset-perms`, `wp-clone`, `export-report`, `staging-push`, `staging-pull`
- `backup`, `uninstall`, `update` commands
- Performance tuning based on server RAM and CPU count
- Swap file creation for low-RAM servers
- SSH, kernel, and MariaDB hardening
- `--dry-run` mode

---

[Unreleased]: https://github.com/UnderHost/one-domain/compare/v2026.3.0...HEAD
[2026.3.0]: https://github.com/UnderHost/one-domain/compare/v2026.2.0...v2026.3.0
[2026.2.0]: https://github.com/UnderHost/one-domain/releases/tag/v2026.2.0

---

## [2026.4.0] — 2026-03-28

### Added — New Commands
- `install info` — shows installer version, OS, hardware, software versions, service status, and external connectivity
- `install list` — lists all domains managed by the installer on the current server with SSL expiry, mode, PHP version, and disk usage
- `install check-deps` — pre-flight checker for required tools, package manager health, external endpoint connectivity, and system readiness
- `install audit [domain]` — read-only security baseline audit with colour-coded pass/fail/warn checklist (system, Nginx, MariaDB, PHP, WordPress, SSL)
- `install apply <domain>` — idempotent re-application of Nginx vhost, PHP-FPM pool, and hardening without touching data
- `install backup <domain>` — on-demand full backup: compressed site files archive + gzipped database dump, with automatic pruning
- `install backup-auto <domain>` — installs a systemd service + timer for scheduled automatic backups (daily or weekly)
- `install restore <domain>` — interactive restore wizard: lists available backups, confirms before overwriting, restores files and database, fixes ownership
- `install backup-list <domain>` — lists available backup archives with sizes and timestamps
- `install wp-update-all <domain>` — updates WordPress core, all plugins, and all themes with a pre-update backup
- `--no-auto-updates` flag — skip automatic OS security update configuration
- `--backup-dest DEST` flag — remote backup destination (`rsync:` or `rclone:` prefix)
- `--backup-retention DAYS` flag — days to retain backup archives (default: 14)

### Added — New Modules
- `modules/backup.sh` — full backup, restore, schedule, list, prune, and optional remote sync (rsync/rclone)
- `modules/info.sh` — server environment display with connectivity checks
- `modules/list.sh` — managed domain discovery from `/var/www/` cross-referenced with Nginx and SSL
- `modules/audit.sh` — security baseline checker with 30+ checks across system, Nginx, MariaDB, PHP, and per-domain
- `modules/checkdeps.sh` — pre-flight tool availability, package manager health, DNS, port, and connectivity checks

### Added — Config File Support
- `/etc/underhost/defaults.conf` and `~/.one-domain.conf` — optional config files for setting project-wide defaults
- `configs/defaults.conf.example` — fully commented example config with all supported variables
- New global vars: `BACKUP_ROOT`, `BACKUP_RETENTION_DAYS`, `BACKUP_REMOTE_DEST`, `BACKUP_SCHEDULE`, `ENABLE_AUTO_UPDATES`

### Added — Features in Existing Modules
- `modules/hardening.sh`: `hardening_auto_updates()` — installs `unattended-upgrades` (Debian/Ubuntu) or `dnf-automatic` (AlmaLinux), security-only, no auto-reboot
- `modules/hardening.sh`: `hardening_install_ssh_key()` — adds SSH public key to `authorized_keys`, optionally disables password auth with sshd validation
- `modules/php.sh`: OPcache JIT enabled (`opcache.jit=tracing`, `opcache.jit_buffer_size=64M`) for PHP 8.0+ — 10–30% CPU improvement
- `modules/nginx.sh`: HTTP/3 QUIC support — detects Nginx ≥ 1.25.1 and adds `listen 443 quic` and `Alt-Svc` header automatically
- `modules/wordpress.sh`: `wp_install_system_cron()` — replaces unreliable `wp-cron.php` with a real system cron job; sets `DISABLE_WP_CRON=true`
- `modules/wordpress.sh`: `wp_update_all()` — pre-backup + core + plugin + theme update in one command
- `modules/prompts.sh`: Step 8 — SSH key install prompt in advanced wizard
- `modules/prompts.sh`: Step 8 — auto OS updates toggle in advanced wizard (9 steps total, up from 7)
- `install`: `_print_plan()` now shows `Auto OS updates` row
- `install`: `ENABLE_AUTO_UPDATES` wired through hardening_apply — applies on every fresh install

### Changed
- `install` version bump: `2026.3.0` → `2026.4.0`
- Module loader now references `_REQUIRED_MODULES` array (includes all 5 new modules)
- `install list` uses exact `_REQUIRED_MODULES` list in CI validation
- `.github/workflows/shellcheck.yml` updated to validate all 5 new modules are present and not deprecated
- `_backup_configs()` in `install` uses `--defaults-extra-file=/root/.my.cnf` (inherited fix from 2026.3.0)

### Security
- Automatic OS security updates now configured by default on every fresh install (`--no-auto-updates` to skip)
- SSH public key can be installed interactively during wizard — password auth optionally disabled post-key-install
- `audit` module detects and reports on 30+ security baseline items without making any changes
- `backup_domain` creates archives with mode `600`; backup directory set to mode `700`

---

[2026.4.0]: https://github.com/UnderHost/one-domain/compare/v2026.3.0...v2026.4.0
