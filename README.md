# UnderHost One-Domain Setup Script

This script automates the process of setting up a single domain on a VPS or dedicated server running CentOS, Debian, Ubuntu, or AlmaLinux. It installs and configures the necessary software, creates a domain, and sets up a database and FTP user for the domain.

## 👉 [UnderHost.com](https://underhost.com) - Affordable and Powerful VPS, Cloud, and Dedicated Servers

Looking for a reliable, high-performance hosting solution for your projects? UnderHost offers cheap, powerful VPS, cloud, and dedicated servers with server management and much more. Visit [underhost.com](https://underhost.com) to explore our hosting plans and let us handle the server setup for you!

## Overview

The script performs the following tasks:

1. Checks if a backup flag is set and backs up existing configurations if needed.
2. Installs and configures the required packages, including Nginx, MariaDB, PHP, and OpenLiteSpeed.
3. Installs and configures an FTP server (vsftpd).
4. Installs PHP 8 with FastCGI Process Manager and common PHP extensions.
5. Configures firewalls to allow necessary services.
6. Installs Certbot and configures SSL/TLS for Nginx.
7. Installs ionCube Loader for PHP.
8. Optimizes Nginx, PHP-FPM, and MariaDB settings based on server specifications.
9. Prompts the user to enter the main domain, MySQL root password, database name, MySQL user, and FTP user.
10. Creates the main domain, MySQL database, and FTP user.
11. Creates a PHP info file for the domain.
12. Saves the login information to a text file.

## Installation

To run the script on your server, execute the following command:

```
curl -sL https://backup.underhost.com/mirror/setup/uhsetup.sh | sudo bash -s -- \
  -d yourdomain.com \          # Main domain (required)
  -b \                         # Create backup (optional)
  -m mysql_root_password \     # MySQL root password (optional)
  -db database_name \          # Database name (optional)
  -du database_user \          # Database user (optional)
  -dp database_password \      # Database password (optional)
  -fu ftp_username \           # FTP user (optional)
  -fp ftp_password             # FTP password (optional)
```

To create a backup of the existing configurations before running the script, use the -b flag:

```
curl -sL https://backup.underhost.com/mirror/setup/uhsetup.sh | sudo bash -s -- -d yourdomain.com -b
```

Full custom setup:

```
curl -sL https://backup.underhost.com/mirror/setup/uhsetup.sh | sudo bash -s -- \
  -d yourdomain.com \
  -m SecureRootPass123 \
  -db myapp_db \
  -du myapp_user \
  -dp DBuserPass123 \
  -fu myftpuser \
  -fp FTPuserPass123
```

### Post-Installation

After installation:

1. Upload your website files to `/var/www/yourdomain.com`
2. Consider removing the PHP info file:

   ```
   rm /var/www/yourdomain.com/info.php
   ```

## Notes

- All passwords are stored in `/root/login_info.txt`
- If passwords aren't specified, random secure passwords will be generated
- The script supports:
  - AlmaLinux/RHEL/CentOS
  - Debian/Ubuntu

# BONUS: Server Security & Optimization Script

## Overview
This advanced security script complements `uhsetup.sh` by adding enterprise-grade hardening to your Linux server. It provides:

**Security Enhancements**  
**Intrusion Prevention**  
**Performance Optimizations**  
**Automated Maintenance**

## Key Features

### Security Hardening
- SSH Security (Port change, root login disable)
- Firewall configuration (UFW/Firewalld)
- Fail2Ban installation
- SELinux/AppArmor enforcement
- Kernel hardening

### Performance Tuning
- Redis cache setup
- Network optimization
- Resource limits configuration
- Unnecessary service removal

### Maintenance
- Automatic updates
- Log rotation
- System monitoring

## Supported Distributions
| Distribution | Version Support |
|--------------|-----------------|
| AlmaLinux    | 8.x, 9.x        |
| CentOS       | 7.x, 8.x        |
| Debian       | 10+, 11         |
| Ubuntu       | 20.04 LTS+      |

## Usage

```
wget -qO- https://backup.underhost.com/mirror/upgrade/uh.sh | bash
```

## Advanced Options

# Download first for inspection/review:

```
wget https://backup.underhost.com/mirror/upgrade/uh.sh
chmod +x uh.sh

# Interactive mode (recommended):
./uh.sh

# Non-interactive mode (for automation):
./uh.sh --auto
```

### Important Notes
- ⚠️ Always test SSH connections before closing your current session when changing ports
- ⚠️ Some optimizations may require reboot to take full effect
- ⚠️ Review /root/underhost-report.txt after completion

### Usage Agreement
By executing this script, you acknowledge and agree that:

- **No Warranty**  
   This software is provided "AS IS" without any warranties, expressed or implied, including but not limited to merchantability or fitness for a particular purpose.

## 🛡️ Professional Support Recommended

For mission-critical systems, we strongly recommend:  

**UnderHost Server Management Services**  
✅ **Expert Implementation** - Certified Linux engineers  
✅ **24/7 Monitoring** - Proactive issue prevention  
✅ **Backup Solutions** - Automated & encrypted backups  
✅ **Security Hardening** - Enterprise-grade protection  

👉 **Let the experts handle it**:  
[Get Managed Server Support](https://underhost.com/server-management.php)

*"Focus on your business while we handle your infrastructure"*  
- UnderHost Support Team

###  License (GPLv3+)
```
This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for full details.

You should have received a copy of the license with this software.
If not, see <https://www.gnu.org/licenses/>.
```
