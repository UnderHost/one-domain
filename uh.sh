#!/bin/bash

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

# 1. Firewall
if [ "$OS" == "CentOS Linux" ]; then
    yum install -y firewalld
    systemctl start firewalld
    systemctl enable firewalld
elif [ "$OS" == "Ubuntu" ] || [ "$OS" == "Debian GNU/Linux" ]; then
    apt-get install -y ufw
    ufw enable
fi

# 2. Close unnecessary ports
if [ "$OS" == "CentOS Linux" ]; then
    firewall-cmd --permanent --add-service=http
    firewall-cmd --permanent --add-service=https
    firewall-cmd --permanent --remove-service=smtp
    firewall-cmd --permanent --remove-service=smtps
    firewall-cmd --permanent --remove-service=pop3
    firewall-cmd --permanent --remove-service=pop3s
    firewall-cmd --permanent --remove-service=imap
    firewall-cmd --permanent --remove-service=imaps
    firewall-cmd --permanent --remove-service=telnet
    firewall-cmd --permanent --remove-service=samba
    firewall-cmd --reload
elif [ "$OS" == "Ubuntu" ] || [ "$OS" == "Debian GNU/Linux" ]; then
    ufw allow http
    ufw allow https
    ufw deny smtp
    ufw deny smtps
    ufw deny pop3
    ufw deny pop3s
    ufw deny imap
    ufw deny imaps
    ufw deny telnet
    ufw deny samba
fi

# 3. Change default listening SSH port
read -p "Enter a new SSH port (default 22): " new_ssh_port
new_ssh_port=${new_ssh_port:-22}
sed -i "s/#Port 22/Port $new_ssh_port/" /etc/ssh/sshd_config
systemctl restart sshd

# 4. Malware AV Scanner
if [ "$OS" == "CentOS Linux" ]; then
    yum install -y clamav clamav-update
    freshclam
elif [ "$OS" == "Ubuntu" ] || [ "$OS" == "Debian GNU/Linux" ]; then
    apt-get install -y clamav clamav-freshclam
    freshclam
fi

#!/bin/bash

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

# 1. Firewall
if [ "$OS" == "CentOS Linux" ]; then
    yum install -y firewalld
    systemctl start firewalld
    systemctl enable firewalld
elif [ "$OS" == "Ubuntu" ] || [ "$OS" == "Debian GNU/Linux" ]; then
    apt-get install -y ufw
    ufw enable
fi

# 2. Close unnecessary ports
if [ "$OS" == "CentOS Linux" ]; then
    firewall-cmd --permanent --add-service=http
    firewall-cmd --permanent --add-service=https
    firewall-cmd --permanent --remove-service=smtp
    firewall-cmd --permanent --remove-service=smtps
    firewall-cmd --permanent --remove-service=pop3
    firewall-cmd --permanent --remove-service=pop3s
    firewall-cmd --permanent --remove-service=imap
    firewall-cmd --permanent --remove-service=imaps
    firewall-cmd --permanent --remove-service=telnet
    firewall-cmd --permanent --remove-service=samba
    firewall-cmd --reload
elif [ "$OS" == "Ubuntu" ] || [ "$OS" == "Debian GNU/Linux" ]; then
    ufw allow http
    ufw allow https
    ufw deny smtp
    ufw deny smtps
    ufw deny pop3
    ufw deny pop3s
    ufw deny imap
    ufw deny imaps
    ufw deny telnet
    ufw deny samba
fi

# 3. Change default listening SSH port
read -p "Enter a new SSH port (default 22): " new_ssh_port
new_ssh_port=${new_ssh_port:-22}
sed -i "s/#Port 22/Port $new_ssh_port/" /etc/ssh/sshd_config
systemctl restart sshd

# 4. Malware AV Scanner
if [ "$OS" == "CentOS Linux" ]; then
    yum install -y clamav clamav-update
    freshclam
elif [ "$OS" == "Ubuntu" ] || [ "$OS" == "Debian GNU/Linux" ]; then
    apt-get install -y clamav clamav-freshclam
    freshclam
fi

# 5. Intrusion Detection Software
if [ "$OS" == "CentOS Linux" ]; then
    yum install -y fail2ban
    systemctl enable fail2ban
    systemctl start fail2ban
elif [ "$OS" == "Ubuntu" ] || [ "$OS" == "Debian GNU/Linux" ]; then
    apt-get install -y fail2ban
    systemctl enable fail2ban
    systemctl start fail2ban
fi

# 6. Brute Force Security
cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
echo "
[sshd]
enabled  = true
port     = $new_ssh_port
filter   = sshd
logpath  = /var/log/auth.log
maxretry = 3
bantime  = 3600
" >> /etc/fail2ban/jail.local
systemctl restart fail2ban

# 7. Spam Filtering - Install SpamAssassin
if [ "$OS" == "CentOS Linux" ]; then
    yum install -y spamassassin
    systemctl enable spamassassin
    systemctl start spamassassin
elif [ "$OS" == "Ubuntu" ] || [ "$OS" == "Debian GNU/Linux" ]; then
    apt-get install -y spamassassin
    systemctl enable spamassassin
    systemctl start spamassassin
fi

# 8. Disable IPV6
echo "net.ipv6.conf.all.disable_ipv6 = 1" >> /etc/sysctl.conf
echo "net.ipv6.conf.default.disable_ipv6 = 1" >> /etc/sysctl.conf
sysctl -p

# 9. Disable Root Logins
sed -i "s/#PermitRootLogin prohibit-password/PermitRootLogin no/" /etc/ssh/sshd_config
systemctl restart sshd


echo "Security and optimization tasks completed."
