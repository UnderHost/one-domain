# UnderHost One-Domain Installer

**A production-grade, single-domain deployment tool for PHP and WordPress**

[![License: GPL-3.0](https://img.shields.io/badge/License-GPL--3.0-blue.svg)](LICENSE)
[![UnderHost](https://img.shields.io/badge/by-UnderHost.com-orange)](https://underhost.com)

---

## Overview

`install` provisions a complete, hardened, performance-tuned web server for a single domain in minutes. It supports both plain PHP sites and full WordPress deployments, with an optional guided interactive wizard for first-time users.

**What gets deployed:**

- **Nginx** — production-optimized, HTTP/2, security headers, gzip, rate limiting
- **PHP-FPM** — isolated per-domain pool, tuned OPcache, restricted `open_basedir`
- **MariaDB** — secured, RAM-tuned, dedicated database and user
- **Let's Encrypt SSL** — automatic provisioning with OCSP stapling and TLS 1.2/1.3
- **Firewall** — UFW (Debian/Ubuntu) or firewalld (AlmaLinux) configured automatically
- **Fail2Ban** — SSH, Nginx HTTP auth, Nginx bot search, and rate-limit jails
- **Redis** *(optional)* — localhost-only via Unix socket, memory-limited, `allkeys-lru`
- **WordPress** *(wp mode)* — latest core, WP-CLI with checksum verification, hardened `wp-config.php`, random table prefix, salts
- **Staging** *(optional)* — cloned WP environment, `noindex` at header level, HTTP Basic Auth, separate database

---

## Supported Operating Systems

| OS | Versions |
|----|---------|
| AlmaLinux | 9, 10 |
| Ubuntu | 24.04, 25.xx |
| Debian | 12, 13 |

> All other distributions (CentOS, Rocky Linux, RHEL, older Ubuntu/Debian) are **not supported**.

---

## Quick Start

```bash
# Download
curl -sL https://raw.githubusercontent.com/UnderHost/one-domain/main/install -o install
chmod +x install

# Deploy a PHP site
sudo ./install domain.com php

# Deploy WordPress
sudo ./install domain.com wp

# Full interactive wizard
sudo ./install --interactive
```

---

## Usage

### Simple command mode

```bash
sudo ./install <domain> php     # PHP website stack
sudo ./install <domain> wp      # WordPress + PHP stack
```

### Interactive wizard

```bash
sudo ./install --interactive          # Full wizard (recommended for first use)
sudo ./install --interactive --basic  # Wizard with essential questions only
```

### Flag-based mode

```bash
sudo ./install domain.com php \
  --php-version 8.4 \
  --ssl-email you@domain.com \
  --with-redis \
  --no-db

sudo ./install domain.com wp \
  --with-redis \
  --with-staging \
  --ssl-email you@domain.com \
  --admin-email admin@domain.com
```

---

## All Flags

| Flag | Description | Default |
|------|-------------|---------|
| `--interactive` | Run the guided wizard | — |
| `--basic` | Wizard: essential questions only | — |
| `--advanced` | Wizard: all questions | ✓ |
| `--dry-run` | Print plan, make no changes | — |
| `--force` | Skip confirmation prompts | — |
| `--backup` | Back up existing configs before install | — |
| `--php-version VERSION` | PHP version: 8.1 / 8.2 / 8.3 / 8.4 | `8.3` |
| `--ssl-email EMAIL` | Email for Let's Encrypt | `admin@domain` |
| `--admin-email EMAIL` | Admin/contact email | same as ssl-email |
| `--with-redis` | Enable Redis object cache | — |
| `--with-db` | Create a database | ✓ |
| `--no-db` | Skip database creation | — |
| `--with-staging` | Create WordPress staging environment | — |
| `--with-ftp` | Enable FTP with TLS (vsftpd) | — |
| `--with-sftp-only` | Enable SFTP file access | — |
| `--with-phpmyadmin` | Install phpMyAdmin *(see security note)* | — |
| `--no-firewall` | Skip firewall configuration | — |
| `--no-fail2ban` | Skip Fail2Ban setup | — |
| `--no-swap` | Skip swap file creation | — |
| `--no-tune` | Skip performance tuning | — |
| `--help` | Show help | — |
| `--version` | Show installer version | — |

---

## What Gets Installed

### PHP Mode (`install domain.com php`)

| Component | Details |
|-----------|---------|
| Nginx | Latest stable, HTTP/2, security headers, rate limiting |
| PHP-FPM | Isolated per-domain pool, tuned OPcache, `open_basedir` |
| MariaDB | Secured, dedicated DB + user, RAM-tuned |
| SSL | Let's Encrypt via Certbot, OCSP stapling, auto-renewal |
| Firewall | HTTP/HTTPS/SSH opened, all else denied |
| Fail2Ban | SSH + Nginx jails |
| System user | Isolated system user per domain |

### WordPress Mode (`install domain.com wp`)

Everything in PHP mode, plus:

| Component | Details |
|-----------|---------|
| WordPress core | Latest stable, downloaded from wordpress.org |
| WP-CLI | Installed at `/usr/local/bin/wp`, SHA-512 checksum verified |
| wp-config.php | Hardened: salts, random table prefix, debug off, SSL forced |
| Permissions | Owner:group set correctly, uploads writable |
| Hardening | `DISALLOW_FILE_EDIT`, xmlrpc.php blocked, PHP denied in uploads |
| Auto-updates | Minor and security releases enabled by default |
| Redis cache | Optional — redis-cache plugin installed and activated |

---

## Interactive Wizard

Run `./install --interactive` for a step-by-step guided setup.

### Basic mode (`--basic`)

Asks only the essential questions. Recommended defaults applied for everything else.

```
? Target domain: example.com
? What do you want to install? PHP / WordPress
? PHP version? 8.3 / 8.4
? Email for SSL notices: you@example.com
? Create a database? [Y/n]
? Proceed with installation? [Y/n]
```

### Advanced mode (default)

All options including Redis, staging, FTP/SFTP, image optimisation, swap, performance tuning.

---

## WordPress Staging

```bash
sudo ./install domain.com wp --with-staging
```

Creates:

- `staging.domain.com` subdomain with its own Nginx vhost
- Separate MariaDB database
- Cloned WordPress files and database
- URL replacement (production → staging URLs)
- `X-Robots-Tag: noindex` at HTTP header level
- HTTP Basic Auth password protection
- SSL certificate provisioned automatically

Staging credentials are displayed in the post-install summary and saved to `/root/underhost_<domain>_*.txt`.

---

## FTP / SFTP File Access

### SFTP (recommended)

```bash
sudo ./install domain.com php --with-sftp-only
```

- Uses SSH port — no extra firewall ports needed
- Chrooted to site directory via `sshd_config` `Match User` block
- `sftp user@domain.com` from any SFTP client

### FTP with TLS

```bash
sudo ./install domain.com php --with-ftp
```

> ⚠️ **Security note:** SFTP is preferred. FTP with TLS (FTPS) requires additional firewall ports (21, 40000–50000). Use SFTP unless your workflow requires FTP specifically.

- vsftpd with `ssl_enable=YES`, `force_local_logins_ssl=YES`
- Anonymous access disabled, chrooted to site root
- Let's Encrypt certificate used for TLS

---

## Maintenance Commands

```bash
# Health check
sudo ./install status    domain.com

# Detailed diagnostic report
sudo ./install diagnose  domain.com

# Interactive repair wizard
sudo ./install repair    domain.com

# Live Nginx log
sudo ./install logs      domain.com

# SSL renewal dry-run
sudo ./install ssl-renew-test domain.com

# Back up configs and databases
sudo ./install backup    domain.com
```

## WordPress Commands

```bash
# Fix broken file permissions
sudo ./install wp-reset-perms domain.com

# Clone a WordPress install
sudo ./install wp-clone source.com dest.com

# Generate a customer report
sudo ./install export-report domain.com

# Push staging → production
sudo ./install staging-push domain.com

# Refresh staging from production
sudo ./install staging-pull domain.com
```

## Security & Performance

```bash
# Apply security hardening only
sudo ./install harden   domain.com

# Apply performance tuning only
sudo ./install optimize domain.com
```

## Management

```bash
# Remove a domain deployment
sudo ./install uninstall domain.com

# Update the installer from GitHub
sudo ./install update

# Show installer version
sudo ./install version
```

---

## Security Features

- **Per-domain system user** — PHP-FPM runs as an isolated user, not `www-data` globally
- **`open_basedir`** — PHP restricted to site root, `/tmp`, and PHP shared libraries
- **Nginx security headers** — X-Frame-Options, CSP, Referrer-Policy, HSTS with preload, Permissions-Policy
- **Hidden files blocked** — `.env`, `.git`, `.htpasswd`, config files denied via Nginx
- **WordPress-specific rules** — xmlrpc.php blocked, PHP execution denied in uploads, readme.html removed
- **Login rate limiting** — `limit_req_zone` on wp-login.php
- **Fail2Ban jails** — SSH, Nginx HTTP auth, Nginx bot search, Nginx rate-limit
- **SSH hardening** — root login restricted to key-only, `MaxAuthTries=4`, idle timeout, verbose logging
- **Kernel hardening** — SYN cookies, rp_filter, ICMP broadcast, redirect protection, `kptr_restrict=2`
- **SSL** — TLS 1.2/1.3 only, HSTS with preload, OCSP stapling, session tickets disabled
- **MariaDB** — anonymous users removed, remote root disabled, test DB dropped, `/root/.my.cnf` for safe `mysqldump`
- **Redis** — bound to `127.0.0.1` via Unix socket, max memory enforced, `allkeys-lru` eviction
- **FTP** — SSL enforced if enabled, anonymous disabled, chrooted, security warning shown

---

## Performance Tuning

Services are automatically tuned based on detected RAM and CPU:

| Resource | Tuning |
|----------|--------|
| Nginx workers | Set to CPU core count |
| Nginx connections | Scaled by CPU, capped at 4096 |
| PHP-FPM pool | `pm.max_children` = RAM / 40 MB |
| OPcache memory | 128 MB → 256 MB → 512 MB by RAM tier |
| MariaDB buffer pool | 25% of RAM, min 64 MB, max 1 GB |
| Swap | Added automatically on servers < 2 GB RAM |

Tuning is skipped if `--no-tune` is passed or if `--basic` mode is used with default acceptance.

---

## Post-Installation

### File locations

| Path | Purpose |
|------|---------|
| `/var/www/domain.com/public/` | Document root |
| `/etc/nginx/conf.d/domain.com.conf` | Nginx vhost |
| `/etc/php/8.3/fpm/pool.d/domain.com.conf` | PHP-FPM pool (Debian/Ubuntu) |
| `/etc/php-fpm.d/domain.com.conf` | PHP-FPM pool (AlmaLinux) |
| `/etc/letsencrypt/live/domain.com/` | SSL certificates |
| `/var/log/nginx/domain.com*.log` | Nginx access/error logs |
| `/var/log/php-fpm/domain.com*.log` | PHP-FPM logs |
| `/root/underhost_domain_TIMESTAMP.txt` | Credentials report (`600`) |
| `/var/log/underhost_install.log` | Full install log |

### Credentials report

Saved to `/root/underhost_<domain>_<timestamp>.txt` with permissions `600`. Contains all generated passwords, paths, and next steps. Keep this file secure.

### SSL renewal

Certbot installs a systemd timer automatically. A deploy hook reloads Nginx after each renewal:

```
/etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
```

Test renewal: `certbot renew --dry-run`

---

## Troubleshooting

See [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) for common issues and fixes.

Quick reference:

```bash
# Full diagnostic
sudo ./install diagnose domain.com

# Live logs
sudo ./install logs domain.com

# Interactive repair wizard
sudo ./install repair domain.com

# Full install log
cat /var/log/underhost_install.log
```

---

## Project Structure

```
.
├── install                  # Main entry point (executable)
├── lib/
│   ├── core.sh              # Colors, logging, prompts, validators, utilities
│   └── wpcli.sh             # WP-CLI install and helper functions
├── modules/
│   ├── os.sh                # OS detection and path resolution
│   ├── prompts.sh           # Interactive wizard
│   ├── packages.sh          # Package installation (apt/dnf)
│   ├── firewall.sh          # UFW / firewalld
│   ├── nginx.sh             # Nginx vhost configuration
│   ├── php.sh               # PHP-FPM pool + OPcache
│   ├── database.sh          # MariaDB setup and tuning
│   ├── redis.sh             # Redis configuration
│   ├── ssl.sh               # Let's Encrypt / Certbot
│   ├── ftp.sh               # FTP/SFTP access
│   ├── wordpress.sh         # WordPress installation
│   ├── staging.sh           # WordPress staging environment
│   ├── hardening.sh         # Security hardening (unified)
│   ├── optimize.sh          # Performance tuning
│   ├── summary.sh           # Post-install summary
│   ├── uninstall.sh         # Domain removal
│   ├── status.sh            # Health check
│   ├── diagnose.sh          # Diagnostic report
│   ├── repair.sh            # Interactive repair wizard
│   └── selfupdate.sh        # Self-update from GitHub
├── configs/
│   └── examples/
│       ├── nginx-vhost.conf.example
│       └── php-fpm-pool.conf.example
└── docs/
    ├── CHANGELOG.md
    └── TROUBLESHOOTING.md
```

---

## Security Policy

See [SECURITY.md](SECURITY.md) for the vulnerability disclosure policy.  
Report security issues to: **security@underhost.com**

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for code standards, testing requirements, and the pull request process.

---

## About UnderHost

[UnderHost.com](https://underhost.com) provides affordable, high-performance VPS, cloud, and dedicated servers with optional server management.

- 🔒 DDoS-protected infrastructure
- ⚡ NVMe storage
- 🌍 Multiple locations
- 🛠️ 24/7 support

---

## License

GNU General Public License v3.0 — see [LICENSE](LICENSE).
