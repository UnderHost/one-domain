#!/bin/bash

OS=$(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"')

# Ensure the script is run as root
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$NAME
else
    echo "Unable to detect OS"
    exit 1
fi

# Update system
if [ "$OS" == "CentOS Linux" ]; then
    yum update -y
elif [ "$OS" == "Ubuntu" ] || [ "$OS" == "Debian GNU/Linux" ]; then
    apt-get update && apt-get upgrade -y
fi

show_menu() {
  echo "===================="
  echo "  Security Menu"
  echo "===================="
  echo "1. Change SSH Listening Port"
  echo "2. Install and Configure Firewall"
  echo "3. Install and Configure Fail2Ban"
  echo "4. Install and Configure SpamAssassin"
  echo "5. Disable IPv6"
  echo "6. Disable Root Logins"
  echo "7. Install and Configure Redis Cache"
  echo "8. Disable Unnecessary Services"
  echo "9. Set up Automatic Updates"
  echo "10. Enable Kernel Hardening Options"
  echo "11. Enable SELinux or AppArmor"
  echo "12. Configure Log Rotation and Monitor Logs"
  echo "13. Optimize Network Settings"
  echo "14. Enable Resource Limits and Process Control"
  echo "q. Quit"
  echo ""
  echo "Enter the number of the action you'd like to perform:"
}

run_change_ssh_port() {
  read -p "Enter the new SSH port: " new_ssh_port
  sed -i "s/^#Port 22/Port $new_ssh_port/" /etc/ssh/sshd_config
  systemctl restart sshd
  echo "SSH port has been changed to $new_ssh_port. Please update your SSH client settings."
}

run_install_configure_firewall() {
  if [[ $OS == "CentOS Linux" ]]; then
    yum install -y firewalld
    systemctl enable firewalld
    systemctl start firewalld
  elif [[ $OS == "Ubuntu" || $OS == "Debian GNU/Linux" ]]; then
    apt-get install -y ufw
    ufw enable
  fi
  echo "Firewall has been installed and configured."
}

run_install_configure_fail2ban() {
  if [[ $OS == "CentOS Linux" ]]; then
    yum install -y epel-release
    yum install -y fail2ban
  elif [[ $OS == "Ubuntu" || $OS == "Debian GNU/Linux" ]]; then
    apt-get install -y fail2ban
  fi
  systemctl enable fail2ban
  systemctl start fail2ban
  echo "Fail2Ban has been installed and configured."
}

run_install_configure_spamassassin() {
  if [[ $OS == "CentOS Linux" ]]; then
    yum install -y spamassassin
  elif [[ $OS == "Ubuntu" || $OS == "Debian GNU/Linux" ]]; then
    apt-get install -y spamassassin
  fi
  systemctl enable spamassassin
  systemctl start spamassassin
  echo "SpamAssassin has been installed and configured."
 }

run_disable_ipv6() {
  echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.conf
  echo "net.ipv6.conf.default.disable_ipv6 = 1" >> /etc/sysctl.conf
  echo "net.ipv6.conf.lo.disable_ipv6 = 1" >> /etc/sysctl.conf
  sysctl -p
  echo "IPv6 has been disabled."
}

run_disable_root_logins() {
  sed -i "s/^#PermitRootLogin .*/PermitRootLogin no/" /etc/ssh/sshd_config
  systemctl restart sshd
  echo "Root logins have been disabled."
}

run_install_configure_redis_cache() {
  if [[ $OS == "CentOS Linux" ]]; then
    yum install -y redis
  elif [[ $OS == "Ubuntu" || $OS == "Debian GNU/Linux" ]]; then
    apt-get install -y redis
  fi
  systemctl enable redis
  systemctl start redis
  echo "Redis Cache has been installed and configured."
}

run_disable_unnecessary_services() {
  if [[ $OS == "CentOS Linux" ]]; then
    systemctl disable postfix
    systemctl disable chronyd
    systemctl disable rpcbind.socket
    systemctl disable rpcbind.target
    systemctl disable nfs-client.target
    systemctl disable rpc-statd-notify.service
    systemctl disable rpc-statd.service
    systemctl disable kdump.service
    systemctl disable cups.service
    systemctl disable cups-browsed.service
    systemctl disable avahi-daemon.socket
    systemctl disable avahi-daemon.service
    echo "The most common unnecessary services have been disabled."
  elif [[ $OS == "Ubuntu" || $OS == "Debian GNU/Linux" ]]; then
    systemctl disable ntp
    systemctl disable cups
    systemctl disable cups-browsed
    systemctl disable avahi-daemon.socket
    systemctl disable avahi-daemon.service
    systemctl disable remote-fs.target
    systemctl disable nfs-client.target
    systemctl disable rpcbind.service
    systemctl disable rpcbind.socket
    systemctl disable exim4
    systemctl disable cron
    echo "The most common unnecessary services have been disabled."
  fi
}

run_setup_automatic_updates() {
  if [[ $OS == "CentOS Linux" ]]; then
    yum install -y yum-cron
    systemctl enable yum-cron
    systemctl start yum-cron
  elif [[ $OS == "Ubuntu" || $OS == "Debian GNU/Linux" ]]; then
    apt-get install -y unattended-upgrades
    dpkg-reconfigure unattended-upgrades
  fi
  echo "Automatic updates have been set up."
}

run_enable_kernel_hardening() {
  echo "kernel.kptr_restrict = 1" >> /etc/sysctl.conf
  echo "kernel.dmesg_restrict = 1" >> /etc/sysctl.conf
  sysctl -p
  echo "Kernel hardening options have been enabled."
}

run_enable_selinux_or_apparmor() {
  if [[ $OS == "CentOS Linux" ]]; then
    setenforce 1
    sed -i 's/^SELINUX=.*$/SELINUX=enforcing/' /etc/selinux/config
    echo "SELinux has been enabled."
  elif [[ $OS == "Ubuntu" || $OS == "Debian GNU/Linux" ]]; then
    apt-get install -y apparmor apparmor-profiles apparmor-utils
    systemctl enable apparmor
    systemctl start apparmor
    echo "AppArmor has been enabled."
  fi
}

run_enable_resource_limits_and_process_control() {
  if [[ $OS == "CentOS Linux" ]]; then
    echo "* hard core 0" >> /etc/security/limits.conf
    echo "root hard nofile 65535" >> /etc/security/limits.conf
    echo "* hard nofile 65535" >> /etc/security/limits.conf
    echo "root soft stack unlimited" >> /etc/security/limits.conf
    echo "* soft stack unlimited" >> /etc/security/limits.conf
    echo "session required pam_limits.so" >> /etc/pam.d/common-session
    echo "fs.file-max = 2097152" >> /etc/sysctl.conf
    sysctl -p
    echo "Resource limits and process control have been enabled."
  elif [[ $OS == "Ubuntu" || $OS == "Debian GNU/Linux" ]]; then
    echo "* hard core 0" >> /etc/security/limits.conf
    echo "root hard nofile 65535" >> /etc/security/limits.conf
    echo "* hard nofile 65535" >> /etc/security/limits.conf
    echo "root soft stack unlimited" >> /etc/security/limits.conf
    echo "* soft stack unlimited" >> /etc/security/limits.conf
    echo "session required pam_limits.so" >> /etc/pam.d/common-session
    echo "fs.file-max = 2097152" >> /etc/sysctl.conf
    sysctl -p
    echo "Resource limits and process control have been enabled."
  fi
}

while true; do
  show_menu
  read -r user_choice
  case "$user_choice" in
    1) run_change_ssh_port ;;
    2) run_install_configure_firewall ;;
    3) run_install_configure_fail2ban ;;
    4) run_install_configure_spamassassin ;;
    5) run_disable_ipv6 ;;
    6) run_disable_root_logins ;;
    7) run_install_configure_redis_cache ;;
    8) run_disable_unnecessary_services ;;
    9) run_setup_automatic_updates ;;
    10) run_enable_kernel_hardening ;;
    11) run_enable_selinux_or_apparmor ;;
    12) run_configure_log_rotation_and_monitoring ;;
    13) run_optimize_network_settings ;;
    14) run_enable_resource_limits_and_process_control ;;
    q) break ;;
    *) echo "Invalid option, please try again." ;;
  esac
  echo ""
done

echo "Exiting the script."

