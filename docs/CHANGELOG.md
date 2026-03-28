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
