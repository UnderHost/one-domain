# Troubleshooting Guide

Common issues and how to resolve them.

---

## SSL Certificate Fails

**Symptom:** Certbot fails with a challenge error.

**Cause:** DNS must point to this server *before* requesting a certificate.

**Fix:**
```bash
# Check what your domain resolves to
dig +short yourdomain.com
dig +short www.yourdomain.com

# Check this server's public IP
curl -4 https://api.ipify.org

# Once DNS matches, request manually
certbot --nginx -d yourdomain.com -d www.yourdomain.com --email you@yourdomain.com
```

---

## Nginx Fails to Start

**Symptom:** `systemctl status nginx` shows failed state.

**Fix:**
```bash
# Test configuration
nginx -t

# View recent errors
journalctl -u nginx --no-pager -n 50

# Common causes:
# 1. Syntax error in vhost — check /etc/nginx/conf.d/yourdomain.com.conf
# 2. Port 80/443 already in use — check: ss -tlnp | grep :80
# 3. Missing SSL cert path in vhost — provision SSL first, or comment out ssl lines
```

---

## PHP-FPM Not Responding (502 Bad Gateway)

**Symptom:** Site returns 502 Bad Gateway.

**Fix:**
```bash
# Check service status (replace 8.3 with your PHP version)
systemctl status php8.3-fpm

# Check socket exists
ls -la /run/php/

# Check pool config
cat /etc/php/8.3/fpm/pool.d/yourdomain.com.conf

# Restart PHP-FPM
systemctl restart php8.3-fpm

# Check logs
tail -50 /var/log/php-fpm/yourdomain.com.error.log
```

---

## MariaDB Connection Refused

**Fix:**
```bash
systemctl status mariadb
systemctl restart mariadb

# Connect as root (socket auth)
mysql

# Check databases
mysql -e "SHOW DATABASES;"

# Test domain DB connection
mysql -u yourdomain_usr -p yourdomain_db
```

---

## WordPress: 500 Internal Server Error

**Common causes and fixes:**

```bash
# Check PHP error log
tail -50 /var/log/php-fpm/yourdomain.com.error.log

# Check Nginx error log
tail -50 /var/log/nginx/yourdomain.com.error.log

# Fix file permissions
./install wp-reset-perms yourdomain.com

# Check wp-config.php database credentials
grep -E 'DB_NAME|DB_USER|DB_HOST' /var/www/yourdomain.com/public/wp-config.php

# Disable plugins (rename plugins folder temporarily)
mv /var/www/yourdomain.com/public/wp-content/plugins \
   /var/www/yourdomain.com/public/wp-content/plugins.bak
```

---

## Fail2Ban Banning Legitimate IPs

```bash
# Check jail status
fail2ban-client status

# Check which jail banned an IP
fail2ban-client status sshd

# Unban an IP
fail2ban-client set sshd unbanip 1.2.3.4

# Check your own IP
curl https://api.ipify.org

# Whitelist your IP permanently (edit jail.local)
nano /etc/fail2ban/jail.local
# Add to [DEFAULT]: ignoreip = 127.0.0.1/8 ::1 YOUR.IP.HERE
systemctl reload fail2ban
```

---

## SSL Certificate Expiry Warning

```bash
# Check expiry date
certbot certificates

# Test auto-renewal
certbot renew --dry-run

# Force renewal
certbot renew --cert-name yourdomain.com --force-renewal

# Check renewal timer
systemctl status certbot.timer
```

---

## Installer Fails Partway Through

```bash
# View the full install log
cat /var/log/underhost_install.log

# Run the built-in diagnostic tool
./install diagnose yourdomain.com

# Use the repair wizard
./install repair yourdomain.com
```

---

## File Upload Fails (WordPress)

**Symptom:** Media uploads return an error.

**Fix:**
```bash
# Check PHP upload limits
php -r "echo ini_get('upload_max_filesize');"

# Permissions on uploads directory
ls -la /var/www/yourdomain.com/public/wp-content/uploads/

# Fix permissions
SYS_USER=$(ls -ld /var/www/yourdomain.com | awk '{print $3}')
chown -R "${SYS_USER}:${SYS_USER}" /var/www/yourdomain.com/public/wp-content/uploads
chmod 755 /var/www/yourdomain.com/public/wp-content/uploads
```

---

## Redis Not Connecting (WordPress)

```bash
# Check Redis is running
systemctl status redis-server  # Debian/Ubuntu
systemctl status redis          # AlmaLinux

# Test socket
redis-cli -s /run/redis/redis.sock ping

# Check plugin status
wp --path=/var/www/yourdomain.com/public redis status --allow-root
wp --path=/var/www/yourdomain.com/public redis enable --allow-root
```

---

## FTP Login Fails

```bash
# vsftpd status
systemctl status vsftpd

# Check vsftpd log
tail -50 /var/log/vsftpd.log

# Verify FTP user exists and has correct home
id ftpusername
grep ftpusername /etc/passwd

# Check chroot permissions — chroot dir must be root:root, not writable
ls -ld /var/www/yourdomain.com

# If using FTPS, ensure SSL cert exists
ls -la /etc/letsencrypt/live/yourdomain.com/
```

---

## Complete Health Check

Run the built-in tools for a full picture:

```bash
./install status   yourdomain.com   # Quick health check
./install diagnose yourdomain.com   # Detailed diagnostic report
./install logs     yourdomain.com   # Live Nginx log tail
```
