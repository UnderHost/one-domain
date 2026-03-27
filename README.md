# UnderHost One-Domain Installer

**A production-grade, single-domain deployment tool for PHP and WordPress.**

[![License: GPLv2](https://img.shields.io/badge/License-GPLv2-blue.svg)](LICENSE)
[![UnderHost](https://img.shields.io/badge/by-UnderHost.com-orange)](https://underhost.com)

---

## Overview

`install` provisions a complete, hardened, performance-tuned web server for a single domain in minutes. It supports both plain PHP sites and full WordPress deployments, with an optional guided interactive wizard for first-time users.

**What gets deployed:**

- **Nginx** — production-optimized, HTTP/2, security headers, gzip
- **PHP-FPM** — isolated per-domain pool, tuned OPcache
- **MariaDB** — secured, RAM-tuned, dedicated database and user
- **Let's Encrypt SSL** — automatic provisioning and renewal
- **Firewall** — UFW or firewalld configured automatically
- **Fail2Ban** — SSH and Nginx brute-force protection
- **Redis** *(optional)* — localhost-only, memory-limited
- **WordPress** *(wp mode)* — latest core, WP-CLI, hardened wp-config.php, random table prefix, salts
- **Staging** *(optional)* — cloned WP environment, noindex, HTTP auth, separate database

---

## Supported Operating Systems

| OS | Versions |
|----|----------|
| AlmaLinux | 9, 10 |
| Ubuntu | 24.04, 25.xx |
| Debian | 12, 13 |

> All other distributions (CentOS, Rocky, RHEL, older Ubuntu/Debian) are **not supported**.

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
sudo ./install --interactive        # Full wizard (recommended for first use)
sudo ./install --interactive --basic   # Wizard with essential questions only
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
| `--basic` | Wizard: essential questions only | advanced |
| `--advanced` | Wizard: ask everything | ✓ |
| `--dry-run` | Print plan, make no changes | — |
| `--force` | Skip confirmation prompts | — |
| `--backup` | Back up existing configs first | — |
| `--php-version VERSION` | PHP version to install | `8.3` |
| `--ssl-email EMAIL` | Email for Let's Encrypt | `admin@domain` |
| `--admin-email EMAIL` | Admin/contact email | same as ssl-email |
| `--with-redis` | Enable Redis object cache | — |
| `--with-db` | Create a database | ✓ |
| `--no-db` | Skip database creation | — |
| `--with-staging` | Create WordPress staging environment | — |
| `--with-ftp` | Enable FTP with TLS (vsftpd) | — |
| `--with-sftp-only` | Enable SFTP file access | — |
| `--with-phpmyadmin` | Install phpMyAdmin *(see security note)* | — |
| `--help` | Show help | — |

---

## What Gets Installed

### PHP Mode (`install domain.com php`)

| Component | Details |
|-----------|---------|
| Nginx | Latest stable, HTTP/2, security headers, gzip |
| PHP-FPM | Isolated per-domain pool, tuned OPcache |
| MariaDB | Secured installation, dedicated DB + user |
| SSL | Let's Encrypt via Certbot, auto-renewal |
| Firewall | HTTP/HTTPS/SSH opened, all else denied |
| Fail2Ban | SSH + Nginx jail rules |
| System user | Isolated system user per domain |
| Placeholder | `index.php` removed after your files are uploaded |

### WordPress Mode (`install domain.com wp`)

Everything in PHP mode, plus:

| Component | Details |
|-----------|---------|
| WordPress core | Latest stable, downloaded from wordpress.org |
| WP-CLI | Installed at `/usr/local/bin/wp` |
| wp-config.php | Hardened: salts, random table prefix, debug off, SSL forced |
| Permissions | Owner:group set correctly, uploads writable |
| Hardening | `DISALLOW_FILE_EDIT`, xmlrpc.php blocked, sensitive files denied |
| Auto-updates | Minor and security releases enabled by default |
| Redis cache | Optional — redis-cache plugin installed and activated |

---

## Interactive Wizard

Run `./install --interactive` for a step-by-step guided setup.

### Basic mode
Asks only the essential questions. Recommended defaults are applied for everything else.

```
? Target domain: example.com
? What do you want to install? PHP / WordPress
? PHP version? 8.3 / 8.4
? Email for SSL notices: you@example.com
? Create a database? [Y/n]
? Proceed with installation? [Y/n]
```

### Advanced mode (default)
Asks every available option including:
- Canonical domain (www vs non-www)
- Redis, Fail2Ban, firewall choices
- WordPress title, admin credentials
- Staging environment setup
- FTP/SFTP access method
- Image optimisation packages
- phpMyAdmin (with security warning)
- Swap and performance tuning

---

## WordPress Staging

Create an isolated staging environment alongside production:

```bash
sudo ./install domain.com wp --with-staging
```

Or choose during the interactive wizard (Step 5).

### What staging creates:

- `staging.domain.com` subdomain *(or `/staging` subdir)*
- Separate MariaDB database
- Cloned WordPress files and database
- URL replacement (production → staging URLs)
- **noindex** headers to prevent search engine indexing
- **HTTP Basic Auth** — password-protected access
- SSL certificate provisioned automatically
- Nginx configuration with isolation

### Staging credentials

Displayed in the post-install summary and saved to `/root/underhost_domain_*.txt`.

---

## FTP / SFTP File Access

### SFTP (recommended)

```bash
sudo ./install domain.com php --with-sftp-only
```

- Uses SSH port — no extra ports needed
- Chrooted to site directory
- Dedicated system user created
- Connect with any SFTP client: `sftp user@domain.com`

### FTP with TLS

```bash
sudo ./install domain.com php --with-ftp
```

> ⚠️ **Security warning:** FTP transmits credentials over the network. FTP with TLS (FTPS) encrypts the session but requires additional firewall ports (21, 40000–50000). Use SFTP unless your workflow requires FTP specifically.

- vsftpd installed with `ssl_enable=YES`
- `force_local_logins_ssl=YES` enforced
- Anonymous access disabled
- Chrooted to site root

### No file access

Default. SSH/SFTP is available to root and sudoers as normal.

---

## Security Features

- **Per-domain system user** — PHP-FPM runs as an isolated user, not `www-data` globally
- **Nginx security headers** — X-Frame-Options, CST, Referrer-Policy, HSTS, Permissions-Policy
- **Hidden files blocked** — `.env`, `.git`, `.htpasswd`, config files denied
- **WordPress-specific rules** — xmlrpc.php blocked, PHP execution denied in uploads
- **Fail2Ban jails** — SSH, Nginx HTTP auth, Nginx bot search
- **SSH hardening** — root login restricted to key-only, idle timeouts, MaxAuthTries
- **Kernel hardening** — syncookies, rp_filter, ICMP broadcast, redirect protection
- **SSL-only** — TLS 1.2/1.3, HSTS, OCSP stapling, session tickets disabled
- **MariaDB** — anonymous users removed, remote root disabled, test DB dropped
- **Redis** — bound to `127.0.0.1` only, max memory enforced, `allkeys-lru` eviction
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
| MariaDB buffer pool | Scaled from 64 MB to 1 GB |
| Swap | Added automatically on servers < 2 GB RAM |

Tuning is skipped if `TUNE_SERVICES=false` or if `--basic` mode is used with default acceptance.

---

## Post-Installation

### File locations

| Path | Purpose |
|------|---------|
| `/var/www/domain.com/` | Document root |
| `/etc/nginx/conf.d/domain.com.conf` | Nginx vhost |
| `/etc/php/8.3/fpm/pool.d/domain.com.conf` | PHP-FPM pool (Debian/Ubuntu) |
| `/etc/php-fpm.d/domain.com.conf` | PHP-FPM pool (AlmaLinux) |
| `/etc/letsencrypt/live/domain.com/` | SSL certificates |
| `/var/log/nginx/domain.com*.log` | Nginx access/error logs |
| `/var/log/php-fpm/domain.com*.log` | PHP-FPM logs |
| `/root/underhost_domain_TIMESTAMP.txt` | Credentials report |
| `/var/log/underhost_install.log` | Full install log |

### Credentials report

A credential file is saved to `/root/underhost_<domain>_<timestamp>.txt` with permissions `600`. It contains all generated passwords, paths, and next steps. **Keep this file secure.**

### SSL renewal

Certbot installs a systemd timer automatically. Renewal is fully automatic. A deploy hook reloads Nginx after each renewal:

```
/etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
```

Test renewal:
```bash
certbot renew --dry-run
```

---

## Troubleshooting

### SSL certificate fails

DNS must point to this server before requesting a certificate. Verify:
```bash
dig +short domain.com
dig +short www.domain.com
```

Request manually after DNS propagates:
```bash
certbot --nginx -d domain.com -d www.domain.com --email you@domain.com
```

### Nginx fails to start

Test configuration:
```bash
nginx -t
journalctl -u nginx --no-pager -n 50
```

### PHP-FPM not responding

Check the socket exists and the pool is running:
```bash
systemctl status php8.3-fpm
ls -la /run/php/
```

### MariaDB connection refused

```bash
systemctl status mariadb
mysql -u root -p
```

### Fail2Ban banning legitimate IPs

```bash
fail2ban-client status
fail2ban-client set sshd unbanip 1.2.3.4
```

---

## Maintenance

### Update WordPress core
```bash
wp --path=/var/www/domain.com core update
```

### Update WordPress plugins
```bash
wp --path=/var/www/domain.com plugin update --all
```

### Rotate SSL certificates manually
```bash
certbot renew
```

### View live logs
```bash
tail -f /var/log/nginx/domain.com.access.log
tail -f /var/log/php-fpm/domain.com.error.log
```

### Restart all services
```bash
systemctl restart nginx mariadb php8.3-fpm
```

---

## Security Notes

1. **Change passwords** generated by the installer if you share the report file.
2. **Do not expose phpMyAdmin publicly.** If installed, protect it with IP allowlisting or a reverse proxy with auth.
3. **Keep all software updated** — OS packages, PHP, WordPress core, and plugins.
4. **Monitor logs** regularly at `/var/log/nginx/` and `/var/log/fail2ban.log`.
5. **Backups** — configure a backup strategy. The installer does not configure persistent backups automatically.
6. **FTP** — prefer SFTP over FTP in all production scenarios.
7. **Remove `info.php`** if you create one for testing. It exposes server information.

---

## Project Structure

```
.
├── install                  # Main entry point
├── lib/
│   └── core.sh              # Colors, logging, prompts, utilities
├── modules/
│   ├── os.sh                # OS detection and path resolution
│   ├── prompts.sh           # Interactive wizard
│   ├── packages.sh          # Package installation
│   ├── firewall.sh          # UFW / firewalld
│   ├── nginx.sh             # Virtual host configuration
│   ├── php.sh               # PHP-FPM pool + OPcache
│   ├── database.sh          # MariaDB setup and tuning
│   ├── redis.sh             # Redis configuration
│   ├── ssl.sh               # Let's Encrypt / Certbot
│   ├── ftp.sh               # FTP/SFTP access
│   ├── wordpress.sh         # WordPress installation
│   ├── staging.sh           # WordPress staging environment
│   ├── hardening.sh         # Security hardening
│   ├── optimize.sh          # Performance tuning
│   └── summary.sh           # Post-install summary
└── docs/
    └── CHANGELOG.md
```

---

## About UnderHost

[UnderHost.com](https://underhost.com) provides affordable, high-performance VPS, cloud, and dedicated servers with optional server management.

- 🔒 DDoS-protected infrastructure
- ⚡ NVMe storage
- 🌍 Multiple locations
- 🛠️ 24/7 support

---

## License

GNU General Public License v2.0 — see [LICENSE](LICENSE).
