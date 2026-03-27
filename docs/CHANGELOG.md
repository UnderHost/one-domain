# Changelog

## 2026.1.0 — Major Architecture Rebuild

### Breaking Changes
- `setup.sh` replaced by modular `install` entry point
- Usage syntax changed: `install domain.com php|wp`
- Removed CentOS, Rocky, and RHEL support (EOL/out-of-scope)
- Removed Memcached (unnecessary for target use case)
- ionCube no longer auto-installed (opt-in only via manual setup)

### New Features
- `install domain.com php` — PHP website deployment mode
- `install domain.com wp` — WordPress deployment mode
- Full interactive wizard (`--interactive`, `--basic`, `--advanced`)
- Per-domain isolated PHP-FPM pool and system user
- WordPress auto-install via WP-CLI
- WordPress staging environment (subdomain or subdir)
- Redis object cache integration (WP plugin auto-configured)
- SFTP-only mode with SSH chroot
- FTP-TLS (FTPS) via vsftpd with security warnings
- Auto-tuning for Nginx, PHP-FPM, MariaDB, OPcache based on server RAM/CPU
- Swap configuration for low-RAM servers
- Kernel sysctl hardening
- SSH hardening (root key-only, idle timeouts)
- Fail2Ban with Nginx and SSH jails
- Certbot deploy hook for automatic Nginx reload on SSL renewal
- Post-install summary with credential storage
- Dry-run mode (`--dry-run`)

### Bug Fixes
- Fixed: `detect_os()` was called after `validate_inputs()` — `$OS` was unset during validation
- Fixed: SSL config was appended after Nginx server block's closing brace (invalid config)
- Fixed: `mysql_secure_installation` called via heredoc — replaced with direct SQL
- Fixed: vsftpd `ssl_enable=NO` default — now defaults to TLS-required
- Fixed: PHP-FPM socket path hardcoded regardless of OS — now resolved per OS
- Fixed: FTP ports opened in firewall unconditionally — now only when FTP is selected

### Security Improvements
- WordPress: random table prefix, salts generated at install time
- WordPress: `DISALLOW_FILE_EDIT`, debug off, FORCE_SSL_ADMIN
- Nginx: `server_tokens off`, hidden file blocking, sensitive file type denial
- MariaDB: anonymous users, remote root, test database removed via SQL (not broken pipe)
- Redis: bound to 127.0.0.1 only, maxmemory enforced, allkeys-lru policy
- FTP: security warning shown before any FTP option, SFTP always recommended

### Supported OS
- AlmaLinux 9, 10
- Ubuntu 24.04, 25.xx
- Debian 12, 13

## 2025.1.0 — Previous Version

Single-file `setup.sh` with basic PHP stack deployment.
