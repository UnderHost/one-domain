# UnderHost One-Domain Setup Script

This script automates the process of setting up a single domain on a VPS or dedicated server running CentOS, Debian, or Ubuntu. It installs and configures the necessary software, creates a domain, and sets up a database and FTP user for the domain.

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

```bash
curl -sL https://backup.underhost.com/mirror/setup/uhsetup.sh | sudo bash
```

To create a backup of the existing configurations before running the script, use the -b flag:

```bash
curl -sL https://backup.underhost.com/mirror/setup/uhsetup.sh | sudo bash -s -- -b
```

## License
### This script is released under the GNU General Public License v3.0 or later.


