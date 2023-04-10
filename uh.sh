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
  echo "7. Optimize OpenLiteSpeed"
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

run_optimize_openlitespeed() {
  echo "Please provide the optimization steps for OpenLiteSpeed."
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
    7) run_optimize_openlitespeed ;;
    q) break ;;
    *) echo "Invalid option, please try again." ;;
  esac
  echo ""
done

echo "Exiting the script."





