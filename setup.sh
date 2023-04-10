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
# *   2023 UnderHost.com                                                      *
# *   This script is licensed under the terms of the GNU General Public       *
# *   License version 2, as published by the Free Software Foundation.        *
# *                                                                           *
# *****************************************************************************

# Check if the script should create a backup

while getopts "b" opt; do
    case $opt in
        b)
            backup=true
            ;;
        *)
            echo "Invalid option. Usage: $0 [-b]"
            exit 1
            ;;
    esac
done

# Backup existing configurations if the backup flag is set
if [ "$backup" = true ]; then
    echo "Backing up existing configurations..."
    backup_dir="/root/backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    if [[ -f /etc/nginx/nginx.conf ]]; then
        cp /etc/nginx/nginx.conf "$backup_dir/nginx.conf"
    fi
    
    if [[ -f /etc/my.cnf.d/optimizations.cnf ]]; then
        cp /etc/my.cnf.d/optimizations.cnf "$backup_dir/optimizations.cnf"
    fi
    
    if [[ -f /etc/php-fpm.d/www.conf ]]; then
        cp /etc/php-fpm.d/www.conf "$backup_dir/www.conf"
    fi
    
    echo "Configurations have been backed up to $backup_dir"
fi

# Check the operating system and install required packages
if [[ $(command -v yum) ]]; then
    # CentOS
    yum -y update
    yum -y install epel-release
    yum -y install nginx mariadb mariadb-server php-fpm php-mysqlnd
    systemctl enable nginx mariadb php-fpm
    systemctl start nginx mariadb php-fpm
    
    # Install OpenLiteSpeed and PHP LSAPI
    yum -y install openlitespeed lsphp80 lsphp80-common lsphp80-mysqlnd lsphp80-gd lsphp80-process lsphp80-xml lsphp80-pdo lsphp80-imap lsphp80-mbstring lsphp80-bcmath lsphp80-json
    systemctl enable lsws
    systemctl start lsws
elif [[ $(command -v apt) ]]; then
    # Debian or Ubuntu
    apt-get update
    apt-get -y install nginx mariadb-server php-fpm php-mysql
    systemctl enable nginx mariadb php-fpm
    systemctl start nginx mariadb php-fpm
    
    # Install OpenLiteSpeed and PHP LSAPI
    wget -O - http://rpms.litespeedtech.com/debian/enable_lst_debain_repo.sh | bash
    apt-get update
    apt-get -y install openlitespeed lsphp80 lsphp80-common lsphp80-mysql lsphp80-gd lsphp80-process lsphp80-xml lsphp80-pdo lsphp80-imap lsphp80-mbstring lsphp80-bcmath lsphp80-json
    systemctl enable lsws
    systemctl start lsws
else
    echo "Operating system not supported."
    exit 1
fi

# Install and configure FTP server
if [[ $(command -v yum) ]]; then
    # CentOS
    yum -y install vsftpd
    systemctl enable vsftpd
    systemctl start vsftpd
elif [[ $(command -v apt) ]]; then
    # Debian or Ubuntu
    apt-get -y install vsftpd
    systemctl enable vsftpd
    systemctl start vsftpd
fi

# Install PHP 8+Fast-CGI Process Manager
if [[ $(command -v yum) ]]; then
    # CentOS
    yum -y install https://rpms.remirepo.net/enterprise/remi-release-7.rpm
    yum -y install yum-utils
    yum-config-manager --enable remi-php80
    yum -y install php php-cli php-fpm php-mysqlnd
    systemctl enable php-fpm
    systemctl start php-fpm
elif [[ $(command -v apt) ]]; then
    # Debian or Ubuntu
    apt-get -y install software-properties-common
    add-apt-repository ppa:ondrej/php
    apt-get update
    apt-get -y install php8.0-fpm php8.0-mysql
    systemctl enable php8.0-fpm
    systemctl start php8.0-fpm
fi

# Install common PHP extensions
echo "Installing common PHP extensions..."
if [[ $(command -v yum) ]]; then
    # CentOS
    yum -y install php-gd php-xml php-mbstring php-zip php-bcmath php-json php-curl php-opcache
elif [[ $(command -v apt) ]]; then
    # Debian or Ubuntu
    apt-get -y install php-gd php-xml php-mbstring php-zip php-bcmath php-json php-curl php-opcache
fi

if [[ $(command -v firewall-cmd) ]]; then
    # CentOS
    firewall-cmd --zone=public --add-service=http --permanent
    firewall-cmd --zone=public --add-service=https --permanent
    firewall-cmd --zone=public --add-service=mysql --permanent
    firewall-cmd --zone=public --add-service=ftp --permanent
    firewall-cmd --reload
elif [[ $(command -v ufw) ]]; then
    # Debian or Ubuntu
    ufw allow 'Nginx Full'
    ufw allow 'MariaDB'
    ufw allow 'OpenSSH'
    ufw allow '20/tcp'
    ufw allow '21/tcp'
    ufw allow '990/tcp'
    ufw allow '40000:50000/tcp'
    echo "y" | ufw enable
fi

# Install Certbot and configure SSL/TLS for Nginx
echo "Installing Certbot and configuring SSL/TLS..."
if [[ $(command -v yum) ]]; then
    # CentOS
    yum -y install certbot python3-certbot-nginx
elif [[ $(command -v apt) ]]; then
    # Debian or Ubuntu
    apt-get -y install certbot python3-certbot-nginx
fi

certbot --nginx -d $main_domain --non-interactive --agree-tos --email your@email.com --redirect

# Install ionCube Loader
echo "Installing ionCube Loader..."
php_version=$(php -r "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;")
ioncube_url="https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_x86-64.tar.gz"
wget $ioncube_url -O /tmp/ioncube_loaders.tar.gz
tar -zxvf /tmp/ioncube_loaders.tar.gz -C /tmp/
ioncube_dir=$(find /tmp/ -name "ioncube_*" -type d)
cp $ioncube_dir/ioncube_loader_lin_$php_version.so /usr/lib64/php/modules/
cat << EOF > /etc/php.d/00-ioncube.ini
zend_extension = /usr/lib64/php/modules/ioncube_loader_lin_$php_version.so
EOF

# Check server specs and optimize Nginx configuration and PHP settings
cpu_cores=$(grep -c ^processor /proc/cpuinfo)
ram_mb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
max_worker_processes=$((cpu_cores*2))
sed -i "s/worker_processes auto/worker_processes $max_worker_processes/g" /etc/nginx/nginx.conf
sed -i "s/worker_connections 1024/worker_connections $(($cpu_cores*1024))/g" /etc/nginx/nginx.conf
sed -i "s/keepalive_timeout 65/keepalive_timeout 5/g" /etc/nginx/nginx.conf
sed -i "s/^# server_tokens off;/server_tokens off;/g" /etc/nginx/nginx.conf
sed -i "s/memory_limit = .*/memory_limit = $(($ram_mb/8))M/" /etc/php-fpm.d/www.conf
sed -i "s/pm.max_children = .*/pm.max_children = $max_worker_processes/" /etc/php-fpm.d/www.conf
sed -i "s/pm.start_servers = .*/pm.start_servers = $(($max_worker_processes/2))/" /etc/php-fpm.d/www.conf
sed -i "s/pm.min_spare_servers = .*/pm.min_spare_servers = $(($max_worker_processes/4))/" /etc/php-fpm.d/www.conf
sed -i "s/pm.max_spare_servers = .*/pm.max_spare_servers = $(($max_worker_processes/2))/" /etc/php-fpm.d/www.conf

# Optimize PHP configuration
echo "Optimizing PHP configuration..."
cat << EOF > /etc/php.d/custom.ini
memory_limit = $(($ram_mb/8))M
max_execution_time = 300
max_input_time = 120
post_max_size = 784M
upload_max_filesize = 2048M
date.timezone = UTC
EOF

# Optimize MariaDB configuration
cat << 'EOF' > /etc/my.cnf.d/optimizations.cnf
[mysqld]
performance-schema = off
innodb_buffer_pool_size = $(($ram_mb/2))K
EOF

# Restart services
systemctl restart nginx mariadb php-fpm

# Create main domain and database
echo "Enter main domain:"
read main_domain
echo "Enter MySQL root password:"
read -s mysql_root_password
echo "Enter the name for the new MySQL database:"
read db_name
mysql -u root -p$mysql_root_password -e "CREATE DATABASE IF NOT EXISTS $db_name"
echo "Enter MySQL user for $main_domain:"
read mysql_user
echo "Enter password for $mysql_user:"
read -s mysql_user_password
mysql -u root -p$mysql_root_password -e "CREATE USER '$mysql_user'@'localhost' IDENTIFIED BY '$mysql_user_password'"
mysql -u root -p$mysql_root_password -e "GRANT ALL PRIVILEGES ON $db_name.* TO '$mysql_user'@'localhost'"

# Create FTP user and directory for main domain
echo "Enter FTP username for $main_domain:"
read ftp_user
echo "Enter password for $ftp_user:"
read -s ftp_password
mkdir -p /var/www/$main_domain/html
chown -R $ftp_user:$ftp_user /var/www/$main_domain/html
echo -e "$ftp_user\n$ftp_password" >> /etc/vsftpd/virtual_users.txt
db_load -T -t hash -f /etc/vsftpd/virtual_users.txt /etc/vsftpd/virtual_users.db

# Create PHP info file
echo "<?php phpinfo(); ?>" > /var/www/$main_domain/html/info.php

# Get path to public_html directory
public_html=$(grep "^$main_domain:" /etc/userdomains | awk '{print "/home/"$2"/public_html"}')

# Create text file with login information
echo -e "Domain: $main_domain\nPublic HTML Directory: /var/www/$main_domain/html\nMySQL Database: $db_name\nMySQL User: $mysql_user\nMySQL Password: $mysql_user_password\nFTP User: $ftp_user\nFTP Password: $ftp_password" > /root/login_info.txt

echo "UnderHost.com one-domain setup, domain configuration and optimization completed successfully. Login information saved to /root/login_info.txt."

echo "Use this command to further optimize and secure your new machine: curl -sL https://backup.underhost.com/mirror/upgrade/uh.sh | sudo bash"
