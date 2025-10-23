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

set -euo pipefail  # Exit on error, undefined variables, pipe failures

# Script metadata
SCRIPT_VERSION="2025.1.0"
SUPPORTED_OS=("almalinux" "rocky" "centos" "ubuntu" "debian")

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Initialize variables
backup=false
main_domain=""
mysql_root_pass=""
db_name=""
db_user=""
db_pass=""
ftp_user=""
ftp_pass=""
enable_redis=false
enable_memcached=false
enable_fail2ban=false
enable_monitoring=false
php_version="8.3"
nodejs_version="20"
skip_prompt=false
log_file="/var/log/underhost_setup.log"

# Logging functions
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$log_file"
}

info() { log "INFO" "${BLUE}$*${NC}"; }
success() { log "SUCCESS" "${GREEN}$*${NC}"; }
warning() { log "WARNING" "${YELLOW}$*${NC}"; }
error() { log "ERROR" "${RED}$*${NC}"; }

# Parse command line arguments
show_help() {
    cat << EOF
UnderHost Server Setup Script v${SCRIPT_VERSION}

Usage: $0 [OPTIONS]

Required:
    -d, --domain DOMAIN        Main domain name (e.g., example.com)

Optional:
    -b, --backup               Enable backup of existing configurations
    -m, --mysql-pass PASS      MySQL root password (auto-generated if not provided)
    --db-name NAME             Database name (auto-generated if not provided)
    --db-user USER             Database user (auto-generated if not provided)
    --db-pass PASS             Database password (auto-generated if not provided)
    --ftp-user USER            FTP user (auto-generated if not provided)
    --ftp-pass PASS            FTP password (auto-generated if not provided)
    
Advanced Options:
    --enable-redis             Install and configure Redis
    --enable-memcached         Install and configure Memcached
    --enable-fail2ban          Install and configure Fail2Ban
    --enable-monitoring        Install monitoring tools (htop, nethogs, etc.)
    --php-version VERSION      PHP version (default: 8.3)
    --nodejs-version VERSION   Node.js version (default: 20)
    --skip-prompt             Skip all confirmation prompts
    --help                    Show this help message

Examples:
    $0 -d example.com --enable-redis --enable-monitoring
    $0 -d example.com -b --php-version 8.4 --skip-prompt

EOF
}

# Parse arguments with long options support
while [[ $# -gt 0 ]]; do
    case $1 in
        -b|--backup) backup=true ;;
        -d|--domain) main_domain="$2"; shift ;;
        -m|--mysql-pass) mysql_root_pass="$2"; shift ;;
        --db-name) db_name="$2"; shift ;;
        --db-user) db_user="$2"; shift ;;
        --db-pass) db_pass="$2"; shift ;;
        --ftp-user) ftp_user="$2"; shift ;;
        --ftp-pass) ftp_pass="$2"; shift ;;
        --enable-redis) enable_redis=true ;;
        --enable-memcached) enable_memcached=true ;;
        --enable-fail2ban) enable_fail2ban=true ;;
        --enable-monitoring) enable_monitoring=true ;;
        --php-version) php_version="$2"; shift ;;
        --nodejs-version) nodejs_version="$2"; shift ;;
        --skip-prompt) skip_prompt=true ;;
        --help) show_help; exit 0 ;;
        *) error "Unknown option: $1"; show_help; exit 1 ;;
    esac
    shift
done

# Verify required parameters
if [ -z "$main_domain" ]; then
    error "Main domain is required"
    show_help
    exit 1
fi

# Validate domain format
validate_domain() {
    local domain_regex="^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z]{2,})+$"
    if [[ ! "$main_domain" =~ $domain_regex ]]; then
        error "Invalid domain format: $main_domain"
        exit 1
    fi
}

validate_domain

# Detect OS and version
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    else
        error "Cannot detect operating system"
        exit 1
    fi
    
    if [[ ! " ${SUPPORTED_OS[@]} " =~ " ${OS} " ]]; then
        error "Unsupported OS: $OS. Supported: ${SUPPORTED_OS[*]}"
        exit 1
    fi
}

# Security validation
validate_inputs() {
    if [ -n "$mysql_root_pass" ] && [ ${#mysql_root_pass} -lt 8 ]; then
        error "MySQL root password must be at least 8 characters"
        exit 1
    fi
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        error "Please run as root"
        exit 1
    fi
}

# Set defaults for optional parameters
set_defaults() {
    [ -z "$mysql_root_pass" ] && mysql_root_pass=$(openssl rand -base64 16)
    [ -z "$db_name" ] && db_name="${main_domain//./_}_db"
    [ -z "$db_user" ] && db_user="${main_domain//./_}_user"
    [ -z "$db_pass" ] && db_pass=$(openssl rand -base64 12)
    [ -z "$ftp_user" ] && ftp_user="${main_domain//./_}_ftp"
    [ -z "$ftp_pass" ] && ftp_pass=$(openssl rand -base64 12)
    
    # Sanitize names
    db_name=$(echo "$db_name" | tr -cd 'a-zA-Z0-9_')
    db_user=$(echo "$db_user" | tr -cd 'a-zA-Z0-9_')
    ftp_user=$(echo "$ftp_user" | tr -cd 'a-zA-Z0-9_')
}

# Backup existing configurations
backup_configs() {
    info "Backing up existing configurations..."
    backup_dir="/root/backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    local config_files=(
        "/etc/nginx/nginx.conf"
        "/etc/my.cnf"
        "/etc/my.cnf.d/server.cnf"
        "/etc/php-fpm.d/www.conf"
        "/usr/local/lsws/conf/httpd_config.conf"
        "/etc/ssh/sshd_config"
        "/etc/fail2ban/jail.local"
    )
    
    for file in "${config_files[@]}"; do
        if [ -f "$file" ]; then
            cp "$file" "$backup_dir/"
            success "Backed up: $file"
        fi
    done
    
    # Backup databases if they exist
    if command -v mysql &> /dev/null; then
        mysqldump --all-databases > "$backup_dir/all_databases.sql" 2>/dev/null || warning "Could not backup all databases"
    fi
    
    success "Backups created in $backup_dir"
}

# Install packages with retry logic
install_packages() {
    local max_retries=3
    local retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        info "Installing packages (attempt $((retry_count + 1))/$max_retries)..."
        
        if [[ $OS == "ubuntu" || $OS == "debian" ]]; then
            apt-get update && apt-get -y install curl wget gnupg && break
        else
            dnf -y update && dnf -y install curl wget && break
        fi
        
        retry_count=$((retry_count + 1))
        warning "Package installation failed, retrying..."
        sleep 5
    done
    
    if [ $retry_count -eq $max_retries ]; then
        error "Failed to install packages after $max_retries attempts"
        exit 1
    fi
}

# Install specific software stacks
install_web_stack() {
    info "Installing web stack..."
    
    case $OS in
        almalinux|rocky|centos)
            dnf -y install epel-release
            dnf -y install nginx mariadb mariadb-server php-fpm php${php_version//./} \
                php-mysqlnd php-gd php-xml php-mbstring php-zip php-bcmath \
                php-json php-curl php-opcache vsftpd certbot python3-certbot-nginx \
                php-redis php-memcached 2>/dev/null || true
            ;;
        ubuntu|debian)
            apt-get -y install nginx mariadb-server php-fpm php-mysql php-gd \
                php-xml php-mbstring php-zip php-bcmath php-json php-curl \
                php-opcache vsftpd certbot python3-certbot-nginx \
                php-redis php-memcached
            ;;
    esac
}

install_additional_services() {
    if [ "$enable_redis" = true ]; then
        info "Installing Redis..."
        case $OS in
            almalinux|rocky|centos) dnf -y install redis ;;
            ubuntu|debian) apt-get -y install redis-server ;;
        esac
        systemctl enable redis --now
    fi
    
    if [ "$enable_memcached" = true ]; then
        info "Installing Memcached..."
        case $OS in
            almalinux|rocky|centos) dnf -y install memcached ;;
            ubuntu|debian) apt-get -y install memcached ;;
        esac
        systemctl enable memcached --now
    fi
    
    if [ "$enable_fail2ban" = true ]; then
        info "Installing Fail2Ban..."
        case $OS in
            almalinux|rocky|centos) dnf -y install fail2ban ;;
            ubuntu|debian) apt-get -y install fail2ban ;;
        esac
        
        # Configure Fail2Ban
        cat > /etc/fail2ban/jail.local << FAIL2BAN_CONFIG
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5

[sshd]
enabled = true

[nginx-http-auth]
enabled = true
FAIL2BAN_CONFIG
        
        systemctl enable fail2ban --now
    fi
    
    if [ "$enable_monitoring" = true ]; then
        info "Installing monitoring tools..."
        case $OS in
            almalinux|rocky|centos)
                dnf -y install htop nethogs iotop nmon sysstat
                ;;
            ubuntu|debian)
                apt-get -y install htop nethogs iotop nmon sysstat
                ;;
        esac
    fi
}

# Configure firewall
configure_firewall() {
    info "Configuring firewall..."
    
    if command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-service={http,https,ftp,mysql}
        [ "$enable_redis" = true ] && firewall-cmd --permanent --add-service=redis
        [ "$enable_memcached" = true ] && firewall-cmd --permanent --add-port=11211/tcp
        firewall-cmd --reload
        success "Firewall configured (firewalld)"
    elif command -v ufw &> /dev/null; then
        ufw allow 'Nginx Full'
        ufw allow 'OpenSSH'
        ufw allow '20/tcp'
        ufw allow '21/tcp'
        ufw allow '990/tcp'
        ufw allow '40000:50000/tcp'
        [ "$enable_redis" = true ] && ufw allow 6379/tcp
        [ "$enable_memcached" = true ] && ufw allow 11211/tcp
        echo "y" | ufw enable
        success "Firewall configured (UFW)"
    else
        warning "No supported firewall manager found"
    fi
}

# Database configuration with secure installation
configure_mysql() {
    info "Configuring MySQL..."
    
    systemctl enable mariadb --now
    
    # Secure installation with expect or heredoc
    mysql_secure_installation <<EOF

y
$mysql_root_pass
$mysql_root_pass
y
y
y
y
EOF

    # Create database and user with validation
    info "Creating database and user..."
    mysql -u root -p"$mysql_root_pass" <<MYSQL_SCRIPT
CREATE DATABASE IF NOT EXISTS \`$db_name\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '$db_user'@'localhost' IDENTIFIED BY '$db_pass';
GRANT ALL PRIVILEGES ON \`$db_name\`.* TO '$db_user'@'localhost';
FLUSH PRIVILEGES;
MYSQL_SCRIPT

    success "Database '$db_name' and user '$db_user' created"
}

# Create FTP user with secure configuration
setup_ftp() {
    info "Setting up FTP user..."
    
    if id "$ftp_user" &>/dev/null; then
        warning "FTP user $ftp_user already exists"
    else
        useradd -m -d "/var/www/$main_domain" -s /bin/bash -c "FTP user for $main_domain" "$ftp_user"
        echo "$ftp_user:$ftp_pass" | chpasswd
    fi
    
    # Secure FTP directory
    mkdir -p "/var/www/$main_domain"
    chown -R "$ftp_user:$ftp_user" "/var/www/$main_domain"
    chmod 755 "/var/www/$main_domain"
    
    # Configure vsftpd securely
    cat > /etc/vsftpd/vsftpd.conf << VSFTPD_CONFIG
listen=YES
local_enable=YES
write_enable=YES
local_umask=022
dirmessage_enable=YES
use_localtime=YES
xferlog_enable=YES
connect_from_port_20=YES
chroot_local_user=YES
secure_chroot_dir=/var/run/vsftpd/empty
pam_service_name=vsftpd
rsa_cert_file=/etc/ssl/certs/ssl-cert-snakeoil.pem
rsa_private_key_file=/etc/ssl/private/ssl-cert-snakeoil.key
ssl_enable=NO
pasv_min_port=40000
pasv_max_port=50000
user_sub_token=$ftp_user
local_root=/var/www/$main_domain
VSFTPD_CONFIG

    systemctl restart vsftpd
    success "FTP user $ftp_user configured"
}

# Modern Nginx configuration with security headers
configure_nginx() {
    info "Configuring Nginx for $main_domain..."
    
    cat > "/etc/nginx/conf.d/$main_domain.conf" << NGINX_CONFIG
server {
    listen 80;
    server_name $main_domain www.$main_domain;
    root /var/www/$main_domain;
    index index.php index.html index.htm;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;

    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css text/xml text/javascript application/javascript application/xml+rss application/json;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_pass unix:/var/run/php/php${php_version}-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_read_timeout 300;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }

    location ~ /\.ht {
        deny all;
    }

    # Cache static assets
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|pdf|txt)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
NGINX_CONFIG

    # Test Nginx configuration
    if nginx -t; then
        systemctl reload nginx
        success "Nginx configuration validated and reloaded"
    else
        error "Nginx configuration test failed"
        exit 1
    fi
}

# SSL certificate with modern configuration
setup_ssl() {
    info "Obtaining SSL certificate for $main_domain..."
    
    if certbot --nginx -d "$main_domain" -d "www.$main_domain" --non-interactive --agree-tos --email "admin@$main_domain" --redirect; then
        success "SSL certificate obtained and configured"
        
        # Add modern SSL configuration
        cat >> "/etc/nginx/conf.d/$main_domain.conf" << SSL_CONFIG

# Modern SSL configuration
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
ssl_prefer_server_ciphers off;
ssl_session_cache shared:SSL:10m;
ssl_session_timeout 1d;
SSL_CONFIG
        
        systemctl reload nginx
    else
        warning "SSL certificate setup failed, continuing without SSL"
    fi
}

# Install and configure ionCube Loader
install_ioncube() {
    info "Installing ionCube Loader..."
    
    local php_extension_dir=$(php -r "echo ini_get('extension_dir');")
    local arch=$(uname -m)
    
    # Determine correct architecture
    case $arch in
        x86_64) arch="x86-64" ;;
        aarch64) arch="aarch64" ;;
        *) warning "Unsupported architecture for ionCube: $arch"; return 1 ;;
    esac
    
    wget -q "https://downloads.ioncube.com/loader_downloads/ioncube_loaders_lin_$arch.tar.gz" -O /tmp/ioncube.tar.gz
    
    if tar -xzf /tmp/ioncube.tar.gz -C /tmp/ 2>/dev/null; then
        local ioncube_dir=$(find /tmp/ -maxdepth 1 -name "ioncube_loader_*" -type d | head -1)
        
        if [ -n "$ioncube_dir" ] && [ -f "$ioncube_dir/ioncube_loader_lin_$php_version.so" ]; then
            cp "$ioncube_dir/ioncube_loader_lin_$php_version.so" "$php_extension_dir/"
            
            case $OS in
                almalinux|rocky|centos)
                    echo "zend_extension=$php_extension_dir/ioncube_loader_lin_$php_version.so" > "/etc/php.d/00-ioncube.ini"
                    ;;
                ubuntu|debian)
                    echo "zend_extension=$php_extension_dir/ioncube_loader_lin_$php_version.so" > "/etc/php/$php_version/mods-available/ioncube.ini"
                    phpenmod ioncube
                    ;;
            esac
            
            success "ionCube Loader installed for PHP $php_version"
        else
            warning "ionCube loader for PHP $php_version not found in the package"
        fi
    else
        warning "Failed to download or extract ionCube loader"
    fi
    
    rm -f /tmp/ioncube.tar.gz
    rm -rf /tmp/ioncube_loader_*
}

# Advanced server optimizations
optimize_server() {
    info "Optimizing server configurations..."
    
    local cpu_cores=$(nproc)
    local total_ram=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
    local available_ram=$((total_ram / 1024))
    
    # Nginx optimization
    sed -i "s/worker_processes auto/worker_processes $cpu_cores;/" /etc/nginx/nginx.conf
    sed -i "s/worker_connections [0-9]\+/worker_connections $((cpu_cores * 1024))/" /etc/nginx/nginx.conf
    
    # PHP-FPM optimization with version detection
    local php_fpm_conf=""
    if [ -f "/etc/php/$php_version/fpm/pool.d/www.conf" ]; then
        php_fpm_conf="/etc/php/$php_version/fpm/pool.d/www.conf"
    elif [ -f "/etc/php-fpm.d/www.conf" ]; then
        php_fpm_conf="/etc/php-fpm.d/www.conf"
    fi
    
    if [ -n "$php_fpm_conf" ]; then
        sed -i "s/^pm = .*/pm = dynamic/" "$php_fpm_conf"
        sed -i "s/^pm.max_children = .*/pm.max_children = $((available_ram / 50))/" "$php_fpm_conf"
        sed -i "s/^pm.start_servers = .*/pm.start_servers = $((cpu_cores * 2))/" "$php_fpm_conf"
        sed -i "s/^pm.min_spare_servers = .*/pm.min_spare_servers = $cpu_cores/" "$php_fpm_conf"
        sed -i "s/^pm.max_spare_servers = .*/pm.max_spare_servers = $((cpu_cores * 2))/" "$php_fpm_conf"
    fi
    
    # MariaDB optimization
    cat >> /etc/my.cnf.d/server.cnf << MYSQL_OPTIMIZATION

# UnderHost Optimizations
[mysqld]
innodb_buffer_pool_size = ${available_ram}M
innodb_log_file_size = 64M
innodb_flush_method = O_DIRECT
innodb_flush_log_at_trx_commit = 2
max_connections = 100
query_cache_type = 0  # Disabled in MySQL 8.0+
MYSQL_OPTIMIZATION

    success "Server optimizations applied"
}

# Create web directory with sample files
setup_web_directory() {
    info "Setting up web directory..."
    
    mkdir -p "/var/www/$main_domain"
    
    # Create a modern index.html
    cat > "/var/www/$main_domain/index.html" << HTML
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Welcome to $main_domain</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; line-height: 1.6; }
        .container { max-width: 800px; margin: 0 auto; }
        .header { background: #f4f4f4; padding: 20px; border-radius: 5px; }
        .info { background: #e7f3ff; padding: 15px; border-left: 4px solid #2196F3; margin: 20px 0; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Welcome to $main_domain</h1>
            <p>Your server has been successfully configured by UnderHost.com</p>
        </div>
        
        <div class="info">
            <h3>Server Information</h3>
            <p><strong>Domain:</strong> $main_domain</p>
            <p><strong>Web Root:</strong> /var/www/$main_domain</p>
            <p><strong>Setup Date:</strong> $(date)</p>
        </div>
        
        <p>Next steps:</p>
        <ul>
            <li>Upload your website files to /var/www/$main_domain</li>
            <li>Configure your database connection</li>
            <li>Remove this file after setup</li>
            <li>Consider running: <code>curl -sL https://backup.underhost.com/mirror/upgrade/uh.sh | bash</code></li>
        </ul>
    </div>
</body>
</html>
HTML

    # Create PHP info file
    cat > "/var/www/$main_domain/info.php" << PHPINFO
<?php 
// Temporary PHP info file - Remove after setup
if (isset(\$_GET['show']) && \$_GET['show'] === 'info') {
    phpinfo();
} else {
    header('Location: /');
    exit;
}
?>
PHPINFO

    # Set proper permissions
    chown -R "$ftp_user:$ftp_user" "/var/www/$main_domain"
    chmod -R 755 "/var/www/$main_domain"
    find "/var/www/$main_domain" -type f -exec chmod 644 {} \;
    
    success "Web directory configured at /var/www/$main_domain"
}

# Generate comprehensive setup report
generate_report() {
    info "Generating setup report..."
    
    local report_file="/root/underhost_setup_${main_domain}_$(date +%Y%m%d).txt"
    
    cat > "$report_file" << REPORT
UnderHost.com Server Setup Report
================================

Generated: $(date)
Script Version: $SCRIPT_VERSION
Domain: $main_domain

SYSTEM INFORMATION
-----------------
OS: $OS $OS_VERSION
CPU Cores: $(nproc)
Total RAM: $(free -h | awk '/Mem:/ {print $2}')
Available RAM: ${available_ram}MB

CREDENTIALS & PATHS
------------------
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

SERVICES STATUS
--------------
$(systemctl is-active nginx 2>/dev/null || echo "Not installed") - Nginx
$(systemctl is-active mariadb 2>/dev/null || echo "Not installed") - MariaDB
$(systemctl is-active php-fpm 2>/dev/null || echo "Not installed") - PHP-FPM
$(systemctl is-active vsftpd 2>/dev/null || echo "Not installed") - VSFTPD
$([ "$enable_redis" = true ] && systemctl is-active redis 2>/dev/null || echo "Not enabled") - Redis
$([ "$enable_memcached" = true ] && systemctl is-active memcached 2>/dev/null || echo "Not enabled") - Memcached
$([ "$enable_fail2ban" = true ] && systemctl is-active fail2ban 2>/dev/null || echo "Not enabled") - Fail2Ban

SECURITY FEATURES
----------------
SSL Certificate: $(if [ -f "/etc/letsencrypt/live/$main_domain/cert.pem" ]; then echo "Installed"; else echo "Not installed"; fi)
Firewall: $(if command -v firewall-cmd &>/dev/null; then echo "firewalld"; elif command -v ufw &>/dev/null; then echo "UFW"; else echo "None"; fi)
Fail2Ban: $([ "$enable_fail2ban" = true ] && echo "Enabled" || echo "Disabled")

NEXT STEPS
----------
1. Upload your website files to /var/www/$main_domain
2. Test your website: https://$main_domain
3. Test PHP info: https://$main_domain/info.php?show=info
4. Remove info.php after setup: rm /var/www/$main_domain/info.php
5. Consider setting up automated backups
6. Monitor server logs regularly

SUPPORT
-------
For support, visit: https://underhost.com/support

IMPORTANT SECURITY NOTES
-----------------------
- Change all passwords regularly
- Keep system and software updated
- Monitor /var/log/ for suspicious activity
- Remove unused services and features
- Configure regular backups

REPORT
------

Setup completed successfully at $(date)
All credentials are saved in: $report_file
Backup location: ${backup_dir:-"No backup created"}

REPORT

    # Set secure permissions on report file
    chmod 600 "$report_file"
    
    success "Detailed report saved to: $report_file"
    echo "$report_file"
}

# Main execution function
main() {
    info "Starting UnderHost Server Setup v$SCRIPT_VERSION"
    info "Domain: $main_domain"
    info "OS: $OS $OS_VERSION"
    
    # Show configuration summary
    if [ "$skip_prompt" = false ]; then
        echo
        info "Configuration Summary:"
        echo "====================="
        echo "Domain: $main_domain"
        echo "Backup: $backup"
        echo "PHP Version: $php_version"
        echo "Redis: $enable_redis"
        echo "Memcached: $enable_memcached"
        echo "Fail2Ban: $enable_fail2ban"
        echo "Monitoring: $enable_monitoring"
        echo
        read -p "Proceed with setup? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "Setup cancelled by user"
            exit 0
        fi
    fi
    
    # Execute setup steps
    [ "$backup" = true ] && backup_configs
    detect_os
    validate_inputs
    set_defaults
    install_packages
    install_web_stack
    install_additional_services
    configure_firewall
    configure_mysql
    setup_ftp
    configure_nginx
    setup_ssl
    install_ioncube
    optimize_server
    setup_web_directory
    
    # Restart services
    info "Restarting services..."
    systemctl restart nginx mariadb php-fpm vsftpd 2>/dev/null || true
    [ "$enable_redis" = true ] && systemctl restart redis 2>/dev/null || true
    [ "$enable_memcached" = true ] && systemctl restart memcached 2>/dev/null || true
    [ "$enable_fail2ban" = true ] && systemctl restart fail2ban 2>/dev/null || true
    
    local report_file=$(generate_report)
    
    success "Setup completed successfully!"
    info "Review the detailed report: $report_file"
    info "Server is ready for use!"
    
    # Display quick access information
    echo
    success "Quick Access:"
    echo "-------------"
    echo "Website: https://$main_domain"
    echo "PHP Info: https://$main_domain/info.php?show=info"
    echo "FTP Host: $main_domain"
    echo "FTP User: $ftp_user"
    echo "MySQL Host: localhost"
    echo "MySQL Database: $db_name"
    echo
    warning "Remember to remove info.php after setup!"
}

# Error handling and cleanup
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        error "Script failed with exit code $exit_code"
        error "Check log file: $log_file"
    fi
}

trap cleanup EXIT

# Initialize logging
mkdir -p "$(dirname "$log_file")"
touch "$log_file"
chmod 600 "$log_file"

# Start main execution
main "$@"
