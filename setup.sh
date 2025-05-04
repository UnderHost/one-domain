#!/bin/bash

# *****************************************************************************
# *                                                                           *
# *                          one-domain setup - optimized                     *
# *                                                                           *
# *                                                                           *
# *     _    _ _   _ _____  ______ _____  _    _  ____   _____ _______        *
# *    | |  | | \ | |  __ \|  ____|  __ \| |  | |/ __ \ / ____|__   __|       *
# *    | |  | |  \| | |  | | |__  | |__) | |__| | |  | | (___    | |          *
# *    | |  | | . ` | |  | |  __| |  _  /|  __  | |  | |\___ \   | |          *
# *    | |__| | |\  | |__| | |____| | \ \| |  | | |__| |____) |  | |          *
# *     \____/|_| \_|_____/|______|_|  \_\_|  |_|\____/|_____/   |_|          *
# *                                                                           *
# *                                                                           *
# *                                                                           *
# *                                                                           *
# *   2025 UnderHost.com                                                      *
# *   This script is licensed under the terms of the GNU General Public       *
# *   License version 2, as published by the Free Software Foundation.        *
# *                                                                           *
# *****************************************************************************

# UnderHost.com Server Setup Script
# To run: curl -sL https://backup.underhost.com/mirror/setup/uhsetup.sh | sudo bash -s -- -d example.com -m mysql_root_pass -db database_name -du database_user -dp database_pass -fu ftp_user -fp ftp_pass

# Initialize variables
backup=false
main_domain=""
mysql_root_pass=""
db_name=""
db_user=""
db_pass=""
ftp_user=""
ftp_pass=""

# Parse command line arguments
while getopts "bd:m:db:du:dp:fu:fp:" opt; do
    case $opt in
        b) backup=true ;;
        d) main_domain="$OPTARG" ;;
        m) mysql_root_pass="$OPTARG" ;;
        db) db_name="$OPTARG" ;;
        du) db_user="$OPTARG" ;;
        dp) db_pass="$OPTARG" ;;
        fu) ftp_user="$OPTARG" ;;
        fp) ftp_pass="$OPTARG" ;;
        *) echo "Usage: $0 [-b] -d domain.com -m mysql_root_pass -db database_name -du database_user -dp database_pass -fu ftp_user -fp ftp_pass"
           exit 1 ;;
    esac
done

# Verify required parameters
if [ -z "$main_domain" ]; then
    echo "Error: Main domain is required"
    echo "Usage: $0 [-b] -d domain.com -m mysql_root_pass -db database_name -du database_user -dp database_pass -fu ftp_user -fp ftp_pass"
    exit 1
fi

# Set defaults for optional parameters
[ -z "$mysql_root_pass" ] && mysql_root_pass=$(openssl rand -base64 16)
[ -z "$db_name" ] && db_name="${main_domain//./_}_db"
[ -z "$db_user" ] && db_user="${main_domain//./_}_user"
[ -z "$db_pass" ] && db_pass=$(openssl rand -base64 12)
[ -z "$ftp_user" ] && ftp_user="${main_domain//./_}_ftp"
[ -z "$ftp_pass" ] && ftp_pass=$(openssl rand -base64 12)

# Backup existing configurations if requested
if [ "$backup" = true ]; then
    echo "Backing up existing configurations..."
    backup_dir="/root/backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    [ -f /etc/nginx/nginx.conf ] && cp /etc/nginx/nginx.conf "$backup_dir/"
    [ -f /etc/my.cnf ] && cp /etc/my.cnf "$backup_dir/"
    [ -f /etc/my.cnf.d/server.cnf ] && cp /etc/my.cnf.d/server.cnf "$backup_dir/"
    [ -f /etc/php-fpm.d/www.conf ] && cp /etc/php-fpm.d/www.conf "$backup_dir/"
    [ -f /usr/local/lsws/conf/httpd_config.conf ] && cp /usr/local/lsws/conf/httpd_config.conf "$backup_dir/"
    
    echo "Backups created in $backup_dir"
fi

# Function to install packages
install_packages() {
    if [[ $(command -v dnf) ]]; then
        # AlmaLinux/CentOS/RHEL
        dnf -y update
        dnf -y install epel-release
        dnf -y install nginx mariadb mariadb-server php-fpm php-mysqlnd php-gd php-xml php-mbstring php-zip php-bcmath php-json php-curl php-opcache vsftpd certbot python3-certbot-nginx
        systemctl enable nginx mariadb php-fpm vsftpd
        systemctl start nginx mariadb php-fpm vsftpd
    elif [[ $(command -v apt) ]]; then
        # Debian/Ubuntu
        apt-get update
        apt-get -y install nginx mariadb-server php-fpm php-mysql php-gd php-xml php-mbstring php-zip php-bcmath php-json php-curl php-opcache vsftpd certbot python3-certbot-nginx
        systemctl enable nginx mariadb php-fpm vsftpd
        systemctl start nginx mariadb php-fpm vsftpd
    else
        echo "Unsupported OS"
        exit 1
    fi
}

# Install required packages
echo "Installing required packages..."
install_packages

# Configure firewall
echo "Configuring firewall..."
if [[ $(command -v firewall-cmd) ]]; then
    firewall-cmd --permanent --add-service={http,https,ftp,mysql}
    firewall-cmd --reload
elif [[ $(command -v ufw) ]]; then
    ufw allow 'Nginx Full'
    ufw allow 'OpenSSH'
    ufw allow '20/tcp'
    ufw allow '21/tcp'
    ufw allow '990/tcp'
    ufw allow '40000:50000/tcp'
    echo "y" | ufw enable
fi

# Configure MySQL
echo "Configuring MySQL..."
mysql_secure_installation <<EOF
y
$mysql_root_pass
$mysql_root_pass
y
y
y
y
EOF

# Create database and user
echo "Creating database and user..."
mysql -u root -p"$mysql_root_pass" <<MYSQL_SCRIPT
CREATE DATABASE $db_name;
CREATE USER '$db_user'@'localhost' IDENTIFIED BY '$db_pass';
GRANT ALL PRIVILEGES ON $db_name.* TO '$db_user'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

# Create FTP user
echo "Creating FTP user..."
useradd -m -d /var/www/$main_domain -s /bin/bash $ftp_user
echo "$ftp_user:$ftp_pass" | chpasswd
chown -R $ftp_user:$ftp_user /var/www/$main_domain
chmod -R 755 /var/www/$main_domain

# Configure Nginx
echo "Configuring Nginx for $main_domain..."
cat > /etc/nginx/conf.d/$main_domain.conf <<NGINX_CONFIG
server {
    listen 80;
    server_name $main_domain www.$main_domain;
    root /var/www/$main_domain;
    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_pass unix:/var/run/php-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }

    location ~ /\.ht {
        deny all;
    }
}
NGINX_CONFIG

# Create web directory and PHP info file
echo "Creating web directory and PHP info file..."
mkdir -p /var/www/$main_domain
cat > /var/www/$main_domain/info.php <<PHPINFO
<?php phpinfo(); ?>
PHPINFO
chown -R $ftp_user:$ftp_user /var/www/$main_domain
chmod -R 755 /var/www/$main_domain

# Obtain SSL certificate
echo "Obtaining SSL certificate for $main_domain..."
certbot --nginx -d $main_domain -d www.$main_domain --non-interactive --agree-tos --email admin@$main_domain --redirect

# Install ionCube Loader
echo "Installing ionCube Loader..."
php_version=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
wget https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz -O /tmp/ioncube.tar.gz
tar -xzf /tmp/ioncube.tar.gz -C /tmp/
ioncube_dir=$(find /tmp/ -maxdepth 1 -name "ioncube_*" -type d)
php_extension_dir=$(php -r "echo ini_get('extension_dir');")
cp "$ioncube_dir/ioncube_loader_lin_$php_version.so" "$php_extension_dir/"

if [[ $(command -v dnf) ]]; then
    echo "zend_extension=$php_extension_dir/ioncube_loader_lin_$php_version.so" > /etc/php.d/00-ioncube.ini
elif [[ $(command -v apt) ]]; then
    echo "zend_extension=$php_extension_dir/ioncube_loader_lin_$php_version.so" > /etc/php/$php_version/mods-available/ioncube.ini
    phpenmod ioncube
fi

# Optimize server configurations
echo "Optimizing server configurations..."
cpu_cores=$(nproc)
total_ram=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
available_ram=$((total_ram / 1024))

# Nginx optimization
sed -i "s/worker_processes auto/worker_processes $cpu_cores;/" /etc/nginx/nginx.conf
sed -i "s/worker_connections [0-9]\+/worker_connections $((cpu_cores * 1024))/" /etc/nginx/nginx.conf

# PHP-FPM optimization
sed -i "s/^pm = .*/pm = dynamic/" /etc/php-fpm.d/www.conf
sed -i "s/^pm.max_children = .*/pm.max_children = $((available_ram / 50))/" /etc/php-fpm.d/www.conf
sed -i "s/^pm.start_servers = .*/pm.start_servers = $((cpu_cores * 2))/" /etc/php-fpm.d/www.conf
sed -i "s/^pm.min_spare_servers = .*/pm.min_spare_servers = $cpu_cores/" /etc/php-fpm.d/www.conf
sed -i "s/^pm.max_spare_servers = .*/pm.max_spare_servers = $((cpu_cores * 2))/" /etc/php-fpm.d/www.conf

# MariaDB optimization
cat >> /etc/my.cnf.d/server.cnf <<MYSQL_OPTIMIZATION
[mysqld]
innodb_buffer_pool_size = ${available_ram}M
innodb_log_file_size = 64M
innodb_flush_method = O_DIRECT
innodb_flush_log_at_trx_commit = 2
query_cache_type = 1
query_cache_size = 32M
max_connections = 100
MYSQL_OPTIMIZATION

# Restart services
echo "Restarting services..."
systemctl restart nginx mariadb php-fpm vsftpd

# Save login information
echo "Saving login information to /root/login_info.txt..."
cat > /root/login_info.txt <<LOGIN_INFO
UnderHost.com Server Setup Complete
==================================

Domain: $main_domain
Web Root: /var/www/$main_domain

MySQL Information:
- Root Password: $mysql_root_pass
- Database Name: $db_name
- Database User: $db_user
- Database Password: $db_pass

FTP Information:
- FTP User: $ftp_user
- FTP Password: $ftp_pass
- FTP Directory: /var/www/$main_domain

PHP Info: http://$main_domain/info.php

Server optimized for:
- CPU Cores: $cpu_cores
- Available RAM: ${available_ram}MB

Next Steps:
1. Upload your website files to /var/www/$main_domain
2. Consider running: curl -sL https://backup.underhost.com/mirror/upgrade/uh.sh | bash
3. Remove info.php after setup: rm /var/www/$main_domain/info.php
LOGIN_INFO

echo "Setup completed successfully!"
echo "Review login information in /root/login_info.txt"
