#!/bin/bash

# UnderHost Server Upgrade Script - Modernized 2025
# Version: 3.0
# Description: Comprehensive server security, optimization, and maintenance tool

set -euo pipefail  # Exit on error, undefined variables, pipe failures

# Script metadata
SCRIPT_VERSION="2025.3.0"
SUPPORTED_OS=("almalinux" "rocky" "centos" "ubuntu" "debian")

# Ensure script is run as root
if [ "$(id -u)" != "0" ]; then
   echo -e "\033[31mError: This script must be run as root\033[0m" >&2
   exit 1
fi

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a /var/log/underhost-upgrade.log
}

info() { log "INFO" "${BLUE}$*${NC}"; }
success() { log "SUCCESS" "${GREEN}$*${NC}"; }
warning() { log "WARNING" "${YELLOW}$*${NC}"; }
error() { log "ERROR" "${RED}$*${NC}"; }

# Detect OS and version
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_NAME=$NAME
        OS_VERSION=$VERSION_ID
    else
        error "Unable to detect OS"
        exit 1
    fi
    
    if [[ ! " ${SUPPORTED_OS[@]} " =~ " ${OS} " ]]; then
        error "Unsupported OS: $OS. Supported: ${SUPPORTED_OS[*]}"
        exit 1
    fi
}

# Backup configuration
backup_config() {
    local config_file=$1
    local backup_dir="/root/underhost_backups/$(date +%Y%m%d_%H%M%S)"
    
    if [ -f "$config_file" ]; then
        mkdir -p "$backup_dir"
        cp "$config_file" "$backup_dir/"
        info "Backed up $config_file to $backup_dir"
    fi
}

# Initial system update
update_system() {
    info "Starting comprehensive system update..."
    
    case $OS in
        almalinux|rocky|centos)
            dnf update -y && dnf upgrade -y
            dnf autoremove -y
            ;;
        ubuntu|debian)
            apt-get update && apt-get upgrade -y && apt-get dist-upgrade -y
            apt-get autoremove -y && apt-get autoclean
            ;;
    esac
    
    # Update firmware if available
    if command -v fwupdmgr &> /dev/null; then
        info "Checking for firmware updates..."
        fwupdmgr refresh
        fwupdmgr update
    fi
    
    success "System update completed"
}

# Security audit function
security_audit() {
    info "Running security audit..."
    
    local audit_file="/root/security_audit_$(date +%Y%m%d).txt"
    
    cat > "$audit_file" << AUDIT_HEADER
UnderHost Security Audit Report
Generated: $(date)
System: $OS_NAME $OS_VERSION

AUDIT_HEADER

    # Check for failed login attempts
    echo -e "\n=== FAILED LOGIN ATTEMPTS ===" >> "$audit_file"
    lastb | head -20 >> "$audit_file"
    
    # Check open ports
    echo -e "\n=== OPEN PORTS ===" >> "$audit_file"
    ss -tuln >> "$audit_file"
    
    # Check sudo access
    echo -e "\n=== USERS WITH SUDO ACCESS ===" >> "$audit_file"
    grep -Po '^sudo.+:\K.*$' /etc/group >> "$audit_file"
    
    # Check for world-writable files
    echo -e "\n=== WORLD-WRITABLE FILES ===" >> "$audit_file"
    find / -xdev -type f -perm -0002 2>/dev/null | head -50 >> "$audit_file"
    
    success "Security audit saved to $audit_file"
}

# SSH Configuration Submenu
ssh_menu() {
    while true; do
        clear
        echo -e "${YELLOW}================================${NC}"
        echo -e "${YELLOW}        SSH Configuration        ${NC}"
        echo -e "${YELLOW}================================${NC}"
        echo -e "1. ${BLUE}Change SSH Port${NC}"
        echo -e "2. ${BLUE}Disable Root Login${NC}"
        echo -e "3. ${BLUE}Enable Key Authentication Only${NC}"
        echo -e "4. ${BLUE}Set Idle Timeout${NC}"
        echo -e "5. ${BLUE}Restrict SSH Users${NC}"
        echo -e "6. ${BLUE}Configure Two-Factor Authentication${NC}"
        echo -e "7. ${BLUE}View SSH Security Status${NC}"
        echo -e "8. ${BLUE}Backup SSH Configuration${NC}"
        echo -e "b. ${RED}Back to Main Menu${NC}"
        echo ""
        read -p "$(echo -e ${YELLOW}"Enter your choice: "${NC})" ssh_choice
        
        case "$ssh_choice" in
            1) change_ssh_port ;;
            2) disable_root_login ;;
            3) enable_key_auth ;;
            4) set_ssh_timeout ;;
            5) restrict_ssh_users ;;
            6) configure_ssh_2fa ;;
            7) view_ssh_status ;;
            8) backup_ssh_config ;;
            b) break ;;
            *) echo -e "${RED}Invalid option${NC}"; sleep 1 ;;
        esac
        
        if [ "$ssh_choice" != "b" ]; then
            read -n 1 -s -r -p "$(echo -e ${YELLOW}"Press any key to continue..."${NC})"
        fi
    done
}

# Enhanced SSH port change
change_ssh_port() {
    info "Changing SSH port..."
    backup_config "/etc/ssh/sshd_config"
    
    current_port=$(grep -E "^Port" /etc/ssh/sshd_config | awk '{print $2}')
    current_port=${current_port:-22}
    
    echo -e "${YELLOW}Current SSH port: ${BLUE}$current_port${NC}"
    
    while true; do
        read -p "Enter new SSH port (1024-65535): " new_port
        if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1024 ] || [ "$new_port" -gt 65535 ]; then
            echo -e "${RED}Invalid port number. Must be between 1024-65535${NC}"
            continue
        fi
        
        if ss -tuln | grep -q ":$new_port "; then
            echo -e "${RED}Port $new_port is already in use${NC}"
            continue
        fi
        
        break
    done
    
    # Update SSH config
    if grep -q "^Port" /etc/ssh/sshd_config; then
        sed -i "s/^Port.*/Port $new_port/" /etc/ssh/sshd_config
    else
        echo "Port $new_port" >> /etc/ssh/sshd_config
    fi
    
    # Update firewall
    if command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --remove-service=ssh
        firewall-cmd --permanent --add-port=$new_port/tcp
        firewall-cmd --reload
        success "Firewalld updated for port $new_port"
    elif command -v ufw &> /dev/null; then
        ufw deny 22/tcp
        ufw allow $new_port/tcp
        ufw reload
        success "UFW updated for port $new_port"
    fi
    
    # Update SELinux if enabled
    if command -v semanage &> /dev/null; then
        semanage port -a -t ssh_port_t -p tcp $new_port
    fi
    
    systemctl restart sshd
    success "SSH port changed to $new_port"
    warning "IMPORTANT: Test SSH connection on port $new_port before closing this session!"
}

disable_root_login() {
    info "Disabling root SSH login..."
    backup_config "/etc/ssh/sshd_config"
    
    sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
    systemctl restart sshd
    success "Root SSH login disabled"
}

enable_key_auth() {
    info "Enabling SSH key authentication only..."
    backup_config "/etc/ssh/sshd_config"
    
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
    sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
    systemctl restart sshd
    success "SSH key authentication enabled, password login disabled"
}

set_ssh_timeout() {
    info "Setting SSH idle timeout..."
    backup_config "/etc/ssh/sshd_config"
    
    local timeout=${1:-300}
    
    sed -i 's/^#*ClientAliveInterval.*/ClientAliveInterval 300/' /etc/ssh/sshd_config
    sed -i 's/^#*ClientAliveCountMax.*/ClientAliveCountMax 2/' /etc/ssh/sshd_config
    systemctl restart sshd
    success "SSH idle timeout set to 5 minutes"
}

restrict_ssh_users() {
    info "Restricting SSH users..."
    backup_config "/etc/ssh/sshd_config"
    
    read -p "Enter allowed SSH users (comma-separated): " ssh_users
    if [ -n "$ssh_users" ]; then
        echo "AllowUsers ${ssh_users//,/ }" >> /etc/ssh/sshd_config
        systemctl restart sshd
        success "SSH access restricted to: $ssh_users"
    else
        error "No users specified"
    fi
}

configure_ssh_2fa() {
    info "Configuring SSH Two-Factor Authentication..."
    
    case $OS in
        almalinux|rocky|centos)
            dnf install -y google-authenticator qrencode
            ;;
        ubuntu|debian)
            apt-get install -y libpam-google-authenticator qrencode
            ;;
    esac
    
    # Configure PAM
    backup_config "/etc/pam.d/sshd"
    echo "auth required pam_google_authenticator.so" >> /etc/pam.d/sshd
    
    # Configure SSHd
    backup_config "/etc/ssh/sshd_config"
    sed -i 's/^#*ChallengeResponseAuthentication.*/ChallengeResponseAuthentication yes/' /etc/ssh/sshd_config
    sed -i 's/^#*UsePAM.*/UsePAM yes/' /etc/ssh/sshd_config
    
    systemctl restart sshd
    success "SSH 2FA configured. Users must run 'google-authenticator' to set up."
}

view_ssh_status() {
    info "Current SSH Security Status:"
    echo -e "${CYAN}SSH Port:${NC} $(grep -E "^Port" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' || echo '22')"
    echo -e "${CYAN}Root Login:${NC} $(grep -E "^PermitRootLogin" /etc/ssh/sshd_config 2>/dev/null | tail -1 | awk '{print $2}' || echo 'yes')"
    echo -e "${CYAN}Password Auth:${NC} $(grep -E "^PasswordAuthentication" /etc/ssh/sshd_config 2>/dev/null | tail -1 | awk '{print $2}' || echo 'yes')"
    echo -e "${CYAN}Key Auth:${NC} $(grep -E "^PubkeyAuthentication" /etc/ssh/sshd_config 2>/dev/null | tail -1 | awk '{print $2}' || echo 'yes')"
    echo -e "${CYAN}Allowed Users:${NC} $(grep -E "^AllowUsers" /etc/ssh/sshd_config 2>/dev/null | cut -d' ' -f2- || echo 'All')"
    
    # Show recent SSH connections
    echo -e "\n${CYAN}Recent SSH connections:${NC}"
    last -10 | grep ssh
}

backup_ssh_config() {
    local backup_dir="/root/ssh_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    cp /etc/ssh/sshd_config "$backup_dir/"
    cp /etc/pam.d/sshd "$backup_dir/" 2>/dev/null || true
    
    # Backup SSH keys
    cp -r /etc/ssh/ssh_host_* "$backup_dir/" 2>/dev/null || true
    
    success "SSH configuration backed up to $backup_dir"
}

# Firewall Management
configure_firewall() {
    info "Configuring firewall..."
    
    if command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-service={http,https,ftp,mysql}
        firewall-cmd --permanent --remove-service=ssh 2>/dev/null || true
        firewall-cmd --permanent --add-port=2222/tcp  # Example custom SSH port
        firewall-cmd --reload
        success "Firewalld configured"
        
    elif command -v ufw &> /dev/null; then
        ufw reset
        ufw allow 'Nginx Full'
        ufw allow 'OpenSSH'
        ufw allow 20/tcp
        ufw allow 21/tcp
        ufw allow 990/tcp
        ufw allow '40000:50000/tcp'
        ufw allow mysql
        echo "y" | ufw enable
        success "UFW configured"
    else
        error "No supported firewall manager found"
    fi
}

# Intrusion Prevention
setup_intrusion_prevention() {
    info "Setting up intrusion prevention..."
    
    # Install and configure Fail2Ban
    case $OS in
        almalinux|rocky|centos)
            dnf install -y fail2ban
            ;;
        ubuntu|debian)
            apt-get install -y fail2ban
            ;;
    esac
    
    # Configure Fail2Ban
    cat > /etc/fail2ban/jail.local << FAIL2BAN_CONFIG
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
backend = auto

[sshd]
enabled = true
port = ssh
logpath = /var/log/secure
maxretry = 3

[sshd-ddos]
enabled = true
port = ssh
logpath = /var/log/secure
maxretry = 5

[nginx-http-auth]
enabled = true
filter = nginx-http-auth
port = http,https
logpath = /var/log/nginx/error.log

[nginx-botsearch]
enabled = true
port = http,https
logpath = /var/log/nginx/access.log
maxretry = 10
FAIL2BAN_CONFIG

    systemctl enable fail2ban --now
    success "Fail2Ban intrusion prevention configured"
}

# Performance Optimization
optimize_performance() {
    info "Optimizing system performance..."
    
    # Kernel optimization
    cat >> /etc/sysctl.conf << SYSCTL_OPTIMizations

# UnderHost Performance Optimizations
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 16384 16777216
net.ipv4.tcp_congestion_control = cubic
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_max_syn_backlog = 3240000
net.core.somaxconn = 3240000
net.ipv4.tcp_max_tw_buckets = 1440000
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
SYSCTL_OPTIMizations

    sysctl -p
    
    # Configure swap if needed
    if [ ! -f /swapfile ]; then
        info "Creating swap file..."
        dd if=/dev/zero of=/swapfile bs=1024 count=2097152
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi
    
    success "System performance optimized"
}

# Security Enhancements
enhance_security() {
    info "Applying security enhancements..."
    
    # Harden sysctl settings
    cat >> /etc/sysctl.conf << SYSCTL_SECURITY

# UnderHost Security Hardening
net.ipv4.ip_forward = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.tcp_syncookies = 1
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
kernel.exec-shield = 1
kernel.randomize_va_space = 2
SYSCTL_SECURITY

    sysctl -p
    
    # Install and configure AIDE (file integrity checker)
    case $OS in
        almalinux|rocky|centos)
            dnf install -y aide
            ;;
        ubuntu|debian)
            apt-get install -y aide
            ;;
    esac
    
    aide --init
    mv /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz
    
    success "Security enhancements applied"
}

# Automatic Maintenance
setup_automatic_maintenance() {
    info "Setting up automatic maintenance..."
    
    # Create daily maintenance script
    cat > /usr/local/bin/underhost-maintenance.sh << 'MAINTENANCE_SCRIPT'
#!/bin/bash
# UnderHost Automatic Maintenance Script

echo "$(date): Starting automatic maintenance" >> /var/log/underhost-maintenance.log

# Update package lists
if command -v dnf &> /dev/null; then
    dnf update -y --refresh
elif command -v apt &> /dev/null; then
    apt-get update && apt-get upgrade -y
fi

# Clean up temporary files
find /tmp -type f -atime +7 -delete
find /var/tmp -type f -atime +7 -delete

# Rotate logs
logrotate -f /etc/logrotate.conf

# Update AIDE database
if command -v aide &> /dev/null; then
    aide --update
    mv /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz
fi

# Backup important configurations
tar -czf /root/backups/config-backup-$(date +%Y%m%d).tar.gz /etc/ssh/sshd_config /etc/fail2ban/jail.local /etc/nginx/nginx.conf 2>/dev/null || true

echo "$(date): Automatic maintenance completed" >> /var/log/underhost-maintenance.log
MAINTENANCE_SCRIPT

    chmod +x /usr/local/bin/underhost-maintenance.sh
    
    # Add to crontab
    (crontab -l 2>/dev/null; echo "0 2 * * * /usr/local/bin/underhost-maintenance.sh") | crontab -
    
    success "Automatic maintenance configured (runs daily at 2 AM)"
}

# Run all recommended upgrades
run_all_upgrades() {
    info "Starting comprehensive server upgrade..."
    
    update_system
    security_audit
    configure_firewall
    setup_intrusion_prevention
    optimize_performance
    enhance_security
    setup_automatic_maintenance
    
    success "All recommended upgrades completed"
    info "Review security audit report in /root/security_audit_*.txt"
}

# Container Security (New Feature)
setup_container_security() {
    info "Setting up container security..."
    
    if command -v docker &> /dev/null; then
        # Configure Docker daemon securely
        mkdir -p /etc/docker
        cat > /etc/docker/daemon.json << DOCKER_CONFIG
{
    "userns-remap": "default",
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "live-restore": true,
    "userland-proxy": false
}
DOCKER_CONFIG
        
        systemctl restart docker
        success "Docker security configured"
    else
        info "Docker not installed, skipping container security"
    fi
}

# Web Application Firewall (New Feature)
setup_waf() {
    info "Setting up Web Application Firewall..."
    
    if [ -f /etc/nginx/nginx.conf ]; then
        # Download and configure ModSecurity
        case $OS in
            almalinux|rocky|centos)
                dnf install -y mod_security mod_security_crs
                ;;
            ubuntu|debian)
                apt-get install -y libapache2-mod-security2 modsecurity-crs
                ;;
        esac
        
        # Configure ModSecurity
        if [ -f /etc/nginx/conf.d/modsecurity.conf ]; then
            sed -i 's/SecRuleEngine DetectionOnly/SecRuleEngine On/' /etc/nginx/conf.d/modsecurity.conf
            systemctl reload nginx
            success "WAF (ModSecurity) configured and enabled"
        fi
    else
        warning "Nginx not found, skipping WAF setup"
    fi
}

# Main menu
show_menu() {
    clear
    echo -e "${YELLOW}=========================================${NC}"
    echo -e "${YELLOW}    UnderHost Server Upgrade Menu       ${NC}"
    echo -e "${YELLOW}           Version $SCRIPT_VERSION           ${NC}"
    echo -e "${YELLOW}=========================================${NC}"
    echo -e "1.  ${BLUE}Change SSH Configuration${NC}"
    echo -e "2.  ${BLUE}Firewall Setup${NC}"
    echo -e "3.  ${BLUE}Intrusion Prevention${NC}"
    echo -e "4.  ${BLUE}Performance Optimization${NC}"
    echo -e "5.  ${BLUE}Security Enhancements${NC}"
    echo -e "6.  ${BLUE}Automatic Maintenance${NC}"
    echo -e "7.  ${GREEN}Run Security Audit${NC}"
    echo -e "8.  ${PURPLE}Container Security${NC}"
    echo -e "9.  ${PURPLE}Web Application Firewall${NC}"
    echo -e "10. ${CYAN}Run All Recommended Upgrades${NC}"
    echo -e "11. ${RED}Emergency Lockdown${NC}"
    echo -e "q.  ${RED}Quit${NC}"
    echo ""
}

# Emergency Lockdown (New Feature)
emergency_lockdown() {
    warning "INITIATING EMERGENCY LOCKDOWN PROCEDURE"
    read -p "Are you sure? This will disable all non-essential services (y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        info "Lockdown cancelled"
        return
    fi
    
    info "Starting emergency lockdown..."
    
    # Block all incoming traffic except SSH
    if command -v iptables &> /dev/null; then
        iptables -F
        iptables -P INPUT DROP
        iptables -P FORWARD DROP
        iptables -A INPUT -i lo -j ACCEPT
        iptables -A INPUT -p tcp --dport 22 -j ACCEPT
        iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
        success "Firewall locked down"
    fi
    
    # Stop non-essential services
    systemctl stop nginx 2>/dev/null || true
    systemctl stop mysql 2>/dev/null || true
    systemctl stop php-fpm 2>/dev/null || true
    systemctl stop vsftpd 2>/dev/null || true
    
    # Disable root login if enabled
    sed -i 's/^PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
    systemctl restart sshd
    
    warning "EMERGENCY LOCKDOWN COMPLETE"
    warning "Only SSH access is available. Review system immediately."
}

# Main execution
main() {
    detect_os
    info "Starting UnderHost Server Upgrade v$SCRIPT_VERSION on $OS_NAME $OS_VERSION"
    
    # Create log directory
    mkdir -p /var/log/underhost
    
    # Initial system update
    update_system
    
    while true; do
        show_menu
        read -p "$(echo -e ${YELLOW}"Enter your choice [1-11,q]: "${NC})" choice
        
        case "$choice" in
            1) ssh_menu ;;
            2) configure_firewall ;;
            3) setup_intrusion_prevention ;;
            4) optimize_performance ;;
            5) enhance_security ;;
            6) setup_automatic_maintenance ;;
            7) security_audit ;;
            8) setup_container_security ;;
            9) setup_waf ;;
            10) run_all_upgrades ;;
            11) emergency_lockdown ;;
            q|Q) 
                echo -e "${GREEN}Exiting UnderHost Upgrade Script${NC}"
                exit 0
                ;;
            *) 
                echo -e "${RED}Invalid option, please try again${NC}"
                sleep 1
                ;;
        esac
        
        if [ "$choice" != "q" ] && [ "$choice" != "Q" ]; then
            echo ""
            read -n 1 -s -r -p "$(echo -e ${YELLOW}"Press any key to continue..."${NC})"
        fi
    done
}

# Error handling
trap 'error "Script interrupted"; exit 1' INT TERM

# Start main execution
main "$@"
