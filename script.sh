#!/bin/bash

# check root
if [ "$(id -u)" -ne 0 ]; then
	echo "must be root."
	exit 1
fi


if [ -d "/var/log/logwatch" ]; then
	echo "job already done."
	exit 0
fi

mkdir -p /var/log/logwatch

# update upgrade install
apt update && apt upgrade -y && apt install iptables ssh fail2ban logwatch -y

systemctl enable ssh fail2ban

# Réinitialiser les règles
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
iptables -t raw -F
iptables -t raw -X

# Politiques par défaut
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

# Autoriser le trafic sortant
iptables -A OUTPUT -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT

# Autoriser le trafic entrant pour SSH, HTTP et HTTPS
iptables -A INPUT -p tcp --dport 22 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
iptables -A INPUT -p tcp --dport 80 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT

# Autoriser les connexions établies et relatives
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Autoriser le trafic sur l'interface loopback
iptables -A INPUT -i lo -j ACCEPT

# Sauvegarder les règles
iptables-save

tee << eof > /etc/logwatch/conf/logwatch.conf
Output = file
Format = text
LogDir = /var/log/logwatch
eof

# Ajout de la tâche cron pour exécuter logwatch quotidiennement
cronjob="0 0 * * * /usr/sbin/logwatch --output file --logdir /var/log/logwatch --range yesterday --detail high"
(crontab -l 2>/dev/null; echo "$cronjob") | crontab -

echo "Configuration de logwatch et tâche cron ajoutée avec succès."

tee << eof >> /etc/fail2ban/jail.conf

[sshd]
enabled = true
port = ssh
logpath = /var/log/auth.log
maxretry = 5
bantime = 3600

[vsftpd]
enabled = true
port = ftp
logpath = /var/log/vsftpd.log
maxretry = 10
bantime = 3600

[vsftpd-iptables]
enabled  = true
filter   = vsftpd
action   = iptables[name=VSFTPD, port=ftp, protocol=tcp]
logpath  = /var/log/vsftpd.log
maxretry = 20
findtime = 300
bantime  = 3600
eof

systemctl restart fail2ban

echo "Configuration de fail2ban complétée et service redémarré."

