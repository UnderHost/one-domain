# Security Policy

## Supported Versions

Only the latest version of the installer on the `main` branch is actively supported. There are no versioned release branches.

| Version | Supported |
|---------|-----------|
| Latest (`main`) | ✅ Yes |
| Older commits | ❌ No — update with `./install update` |

---

## Reporting a Vulnerability

**Please do not report security vulnerabilities through public GitHub issues.**

If you believe you have found a security vulnerability in the installer or in configurations it produces, please report it privately:

**Email:** security@underhost.com  
**Subject:** `[one-domain] Security vulnerability report`

Include in your report:

1. A description of the vulnerability
2. The component affected (e.g. `modules/hardening.sh`, SSL configuration)
3. Steps to reproduce or a proof of concept
4. The potential impact
5. Any suggested remediation (optional but appreciated)

You will receive an acknowledgement within **72 hours**. We aim to resolve confirmed vulnerabilities within **14 days** for critical issues and **30 days** for others.

We do not currently offer a bug bounty program, but we will credit researchers in the changelog unless you prefer to remain anonymous.

---

## Security Design Notes

The following are intentional design decisions, not vulnerabilities:

- **`PasswordAuthentication yes` in SSH hardening** — The installer leaves SSH password auth enabled because the server owner may not have added their public key yet. After adding your key, disable password auth manually: `sshd_set PasswordAuthentication no` in `/etc/ssh/sshd_config`.

- **`/root/.my.cnf` with no password** — Root MariaDB access uses unix socket authentication on modern MariaDB (no password required for root). The `.my.cnf` file enables safe `mysqldump` usage without exposing credentials on the process list. The file is created with mode `600`.

- **phpMyAdmin** — The `--with-phpmyadmin` flag is provided but marked with a security warning. It is the operator's responsibility to restrict access via IP allowlisting or a reverse proxy with authentication before exposing phpMyAdmin.

- **`DISALLOW_FILE_MODS = false`** in WordPress — Plugin and theme updates via the dashboard are left enabled to allow security updates. File editing (`DISALLOW_FILE_EDIT`) is disabled. Adjust to `true` if you manage updates via WP-CLI or a CI pipeline.

---

## Known Security Limitations

- The installer does not configure automatic OS package updates. Set up `unattended-upgrades` (Debian/Ubuntu) or `dnf-automatic` (AlmaLinux) separately.
- Backups are not configured automatically. The installer prints a reminder, but the operator must implement a backup strategy.
- The installer does not configure monitoring or alerting.
