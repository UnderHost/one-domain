#!/bin/bash

# UnderHost Server Upgrade Script
# Version: 2.0
# Description: Comprehensive server security and optimization tool

# Ensure script is run as root
if [ "$(id -u)" != "0" ]; then
   echo -e "\033[31mError: This script must be run as root\033[0m" >&2
   exit 1
fi

# Detect OS and version
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$NAME
    OS_VERSION=$VERSION_ID
else
    echo -e "\033[31mError: Unable to detect OS\033[0m" >&2
    exit 1
fi

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a /var/log/underhost-upgrade.log
}

# Initial system update
update_system() {
    log "${BLUE}Starting system update...${NC}"
    if [[ "$OS" =~ "AlmaLinux" || "$OS" =~ "CentOS" ]]; then
        dnf update -y && dnf upgrade -y
    elif [[ "$OS" =~ "Ubuntu" || "$OS" =~ "Debian" ]]; then
        apt-get update && apt-get upgrade -y && apt-get dist-upgrade -y
    fi
    log "${GREEN}System update completed${NC}"
}

# Main menu
show_menu() {
  clear
  echo -e "${YELLOW}===================================${NC}"
  echo -e "${YELLOW}  UnderHost Server Upgrade Menu  ${NC}"
  echo -e "${YELLOW}===================================${NC}"
  echo -e "1. ${BLUE}Change SSH Configuration${NC}"
  echo -e "2. ${BLUE}Firewall Setup${NC}"
  echo -e "3. ${BLUE}Intrusion Prevention${NC}"
  echo -e "4. ${BLUE}Email Security${NC}"
  echo -e "5. ${BLUE}Network Hardening${NC}"
  echo -e "6. ${BLUE}System Services Management${NC}"
  echo -e "7. ${BLUE}Performance Optimization${NC}"
  echo -e "8. ${BLUE}Security Enhancements${NC}"
  echo -e "9. ${BLUE}Automatic Maintenance${NC}"
  echo -e "10. ${BLUE}Run All Recommended Upgrades${NC}"
  echo -e "q. ${RED}Quit${NC}"
  echo ""
  echo -e "${YELLOW}Enter your choice [1-10,q]:${NC} "
}

# SSH Configuration Submenu
ssh_menu() {
  clear
  echo -e "${YELLOW}========================${NC}"
  echo -e "${YELLOW}  SSH Configuration  ${NC}"
  echo -e "${YELLOW}========================${NC}"
  echo -e "1. Change SSH Port"
  echo -e "2. Disable Root Login"
  echo -e "3. Enable Key Authentication Only"
  echo -e "4. Set Idle Timeout"
  echo -e "5. Restrict SSH Users"
  echo -e "b. Back to Main Menu"
  echo ""
  echo -e "${YELLOW}Enter your choice:${NC} "
}

# Function to change SSH port
change_ssh_port() {
  current_port=$(grep -E "^Port" /etc/ssh/sshd_config | awk '{print $2}')
  echo -e "${YELLOW}Current SSH port: ${BLUE}$current_port${NC}"
  
  read -p "Enter new SSH port (1024-65535): " new_port
  if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1024 ] || [ "$new_port" -gt 65535 ]; then
    echo -e "${RED}Invalid port number${NC}"
    return 1
  fi
  
  # Check if port is in use
  if ss -tuln | grep -q ":$new_port "; then
    echo -e "${RED}Port $new_port is already in use${NC}"
    return 1
  fi
  
  # Update SSH config
  sed -i "s/^#*Port .*/Port $new_port/" /etc/ssh/sshd_config
  
  # Update firewall
  if command -v firewall-cmd &> /dev/null; then
    firewall-cmd --permanent --remove-service=ssh
    firewall-cmd --permanent --add-port=$new_port/tcp
    firewall-cmd --reload
  elif command -v ufw &> /dev/null; then
    ufw deny 22/tcp
    ufw allow $new_port/tcp
    ufw reload
  fi
  
  systemctl restart sshd
  echo -e "${GREEN}SSH port changed to $new_port${NC}"
  echo -e "${YELLOW}IMPORTANT: Test new SSH connection before closing this session!${NC}"
}

# Main execution
update_system

while true; do
  show_menu
  read -r choice
  case "$choice" in
    1) 
      while true; do
        ssh_menu
        read -r ssh_choice
        case "$ssh_choice" in
          1) change_ssh_port ;;
          2) disable_root_login ;;
          3) enable_key_auth ;;
          4) set_ssh_timeout ;;
          5) restrict_ssh_users ;;
          b) break ;;
          *) echo -e "${RED}Invalid option${NC}" ;;
        esac
        read -n 1 -s -r -p "Press any key to continue..."
      done
      ;;
    2) configure_firewall ;;
    3) setup_intrusion_prevention ;;
    4) enhance_email_security ;;
    5) harden_network ;;
    6) manage_services ;;
    7) optimize_performance ;;
    8) enhance_security ;;
    9) setup_automatic_maintenance ;;
    10) run_all_upgrades ;;
    q|Q) 
      echo -e "${GREEN}Exiting UnderHost Upgrade Script${NC}"
      exit 0
      ;;
    *) 
      echo -e "${RED}Invalid option, please try again${NC}"
      sleep 1
      ;;
  esac
done
