#!/bin/bash

# Check the operating system and install required packages
if [[ $(command -v yum) ]]; then
    # CentOS
    yum -y update
    yum -y install epel-release
    yum -y install nginx mariadb mariadb-server php-fpm php-mysqlnd
    systemctl enable nginx mariadb php-fpm
    systemctl start nginx mariadb php-fpm
elif [[ $(command -v apt) ]]; then
    # Debian or Ubuntu
    apt-get update
    apt-get -y install nginx mariadb-server php-fpm php-mysql
    systemctl enable nginx mariadb php-fpm
    systemctl start nginx mariadb php-fpm
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

Check server specs and optimize Nginx configuration and PHP settings
cpu_cores=$(grep -c ^processor /proc/cpuinfo)
ram_mb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
max_worker_processes=$((cpu_cores2))
sed -i "s/worker_processes auto/worker_processes $max_worker_processes/g" /etc/nginx/nginx.conf
sed -i "s/worker_connections 1024/worker_connections $(($cpu_cores1024))/g" /etc/nginx/nginx.conf
sed -i "s/keepalive_timeout 65/keepalive_timeout 5/g" /etc/nginx/nginx.conf
sed -i "s/^# server_tokens off;/server_tokens off;/g" /etc/nginx/nginx.conf
sed -i "s/memory_limit = ./memory_limit = $(($ram_mb/8))M/" /etc/php-fpm.d/www.conf
sed -i "s/pm.max_children = ./pm.max_children = $max_worker_processes/" /etc/php-fpm.d/www.conf
sed -i "s/pm.start_servers = ./pm.start_servers = $(($max_worker_processes/2))/" /etc/php-fpm.d/www.conf
sed -i "s/pm.min_spare_servers = ./pm.min_spare_servers = $(($max_worker_processes/4))/" /etc/php-fpm.d/www.conf
sed -i "s/pm.max_spare_servers = .*/pm.max_spare_servers = $(($max_worker_processes/2))/" /etc/php-fpm.d/www.conf

Optimize MySQL settings
mysql_tuning_primer_url='https://raw.githubusercontent.com/major/MySQLTuner-perl/master/basic_passwords.txt'
wget $mysql_tuning_primer_url -O /usr/local/sbin/tuning-primer.sh
chmod +x /usr/local/sbin/tuning-primer.sh
/usr/local/sbin/tuning-primer.sh > /etc/mysql/my.cnf
service mysql restart

Create main domain and database
echo "Enter main domain:"
read main_domain
echo "Enter MySQL root password:"
read -s mysql_root_password
mysql -u root -p$mysql_root_password -e "CREATE DATABASE IF NOT EXISTS $main_domain"
echo "Enter MySQL user for $main_domain:"
read mysql_user
echo "Enter password for $mysql_user:"
read -s mysql_user_password
mysql -u root -p$mysql_root_password -e "CREATE USER '$mysql_user'@'localhost' IDENTIFIED BY '$mysql_user_password'"
mysql -u root -p$mysql_root_password -e "GRANT ALL PRIVILEGES ON $main_domain.* TO '$mysql_user'@'localhost'"

Create FTP user and directory for main domain
echo "Enter FTP username for $main_domain:"
read ftp_user
echo "Enter password for $ftp_user:"
read -s ftp_password
mkdir -p /var/www/$main_domain/html
chown -R $ftp_user:$ftp_user /var/www/$main_domain/html
echo -e "$ftp_user\n$ftp_password" >> /etc/vsftpd/virtual_users.txt
db_load -T -t hash -f /etc/vsftpd/virtual_users.txt /etc/vsftpd/virtual_users.db

Get path to public_html directory
public_html=$(grep "^$main_domain:" /etc/userdomains | awk '{print "/home/"$2"/public_html"}')

Create text file with login information
echo -e "Domain: $main_domain\nPublic HTML Directory: /var/www/$main_domain/html\nMySQL User: $mysql_user\nMySQL Password: $mysql_user_password
