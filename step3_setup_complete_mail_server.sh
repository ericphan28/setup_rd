#!/bin/bash
# Script to install support tools for Roundcube setup on AlmaLinux 9.3

# Refresh package list
dnf makecache
dnf install -y epel-release

# Install tools
dnf install -y telnet
dnf install -y nano
dnf install -y bind-utils
dnf install -y tar
dnf install -y firewalld
dnf install -y s-nail

# Enable and start firewalld
systemctl enable firewalld --now
firewall-cmd --add-port=25/tcp --permanent && firewall-cmd --add-port=587/tcp --permanent && firewall-cmd --add-port=465/tcp --permanent && firewall-cmd --add-port=143/tcp --permanent && firewall-cmd --add-port=110/tcp --permanent && firewall-cmd --add-port=993/tcp --permanent && firewall-cmd --add-port=995/tcp --permanent && firewall-cmd --add-port=80/tcp --permanent && firewall-cmd --add-port=443/tcp --permanent && firewall-cmd --reload

echo "Support tools installation completed!"


#!/bin/bash
# Script to check DNS and SPF records for rocketsmtp.site

echo "Checking DNS and SPF records for rocketsmtp.site..."

# Check A record
echo -e "\n1. A Record (should return 103.176.20.154):"
dig A rocketsmtp.site +short

# Check MX record
echo -e "\n2. MX Record (should return mail server, e.g., mail.rocketsmtp.site):"
dig MX rocketsmtp.site +short

# Check SPF record
echo -e "\n3. SPF Record (should return v=spf1 ip4:103.176.20.154 -all):"
dig TXT rocketsmtp.site +short

# Check PTR record
echo -e "\n4. PTR Record (should return mail.rocketsmtp.site or similar):"
dig -x 103.176.20.154 +short

echo -e "\nNote: For blacklist check, visit https://mxtoolbox.com/blacklists.aspx and enter 103.176.20.154"
echo "Done! Review the output and update DNS records if necessary."


#!/bin/bash
# Script to install and configure Postfix and Dovecot on AlmaLinux 9.3

# Install Postfix and Dovecot
dnf install -y postfix
dnf install -y dovecot

# Configure Postfix
CONFIG_FILE="/etc/postfix/main.cf"
[ ! -f "$CONFIG_FILE" ] && echo "Error: $CONFIG_FILE not found" && exit 1
grep -q "^myhostname =" "$CONFIG_FILE" && sed -i "s/^myhostname =.*/myhostname = rocketsmtp.site/" "$CONFIG_FILE" || echo "myhostname = rocketsmtp.site" >> "$CONFIG_FILE"
grep -q "^mydomain =" "$CONFIG_FILE" && sed -i "s/^mydomain =.*/mydomain = rocketsmtp.site/" "$CONFIG_FILE" || echo "mydomain = rocketsmtp.site" >> "$CONFIG_FILE"
grep -q "^myorigin =" "$CONFIG_FILE" && sed -i "s/^myorigin =.*/myorigin = \$mydomain/" "$CONFIG_FILE" || echo "myorigin = \$mydomain" >> "$CONFIG_FILE"
grep -q "^inet_interfaces =" "$CONFIG_FILE" && sed -i "s/^inet_interfaces =.*/inet_interfaces = all/" "$CONFIG_FILE" || echo "inet_interfaces = all" >> "$CONFIG_FILE"
grep -q "^mydestination =" "$CONFIG_FILE" && sed -i "s/^mydestination =.*/mydestination = \$myhostname, localhost.\$mydomain, localhost/" "$CONFIG_FILE" || echo "mydestination = \$myhostname, localhost.\$mydomain, localhost" >> "$CONFIG_FILE"
grep -q "^mynetworks =" "$CONFIG_FILE" && sed -i "s/^mynetworks =.*/mynetworks = 127.0.0.0\/8, 103.176.20.154\/32/" "$CONFIG_FILE" || echo "mynetworks = 127.0.0.0\/8, 103.176.20.154\/32" >> "$CONFIG_FILE"
grep -q "^smtpd_sasl_type =" "$CONFIG_FILE" && sed -i "s/^smtpd_sasl_type =.*/smtpd_sasl_type = dovecot/" "$CONFIG_FILE" || echo "smtpd_sasl_type = dovecot" >> "$CONFIG_FILE"
grep -q "^smtpd_sasl_path =" "$CONFIG_FILE" && sed -i "s/^smtpd_sasl_path =.*/smtpd_sasl_path = private\/auth/" "$CONFIG_FILE" || echo "smtpd_sasl_path = private\/auth" >> "$CONFIG_FILE"
grep -q "^smtpd_sasl_auth_enable =" "$CONFIG_FILE" && sed -i "s/^smtpd_sasl_auth_enable =.*/smtpd_sasl_auth_enable = yes/" "$CONFIG_FILE" || echo "smtpd_sasl_auth_enable = yes" >> "$CONFIG_FILE"

echo "submission inet n - n - - smtpd" >> /etc/postfix/master.cf

# Configure Dovecot
DOVECOT_CONF="/etc/dovecot/dovecot.conf"
[ ! -f "$DOVECOT_CONF" ] && echo "Error: $DOVECOT_CONF not found" && exit 1
grep -q "^protocols =" "$DOVECOT_CONF" && sed -i "s/^protocols =.*/protocols = imap pop3/" "$DOVECOT_CONF" || echo "protocols = imap pop3" >> "$DOVECOT_CONF"

MAIL_CONF="/etc/dovecot/conf.d/10-mail.conf"
[ ! -f "$MAIL_CONF" ] && echo "Error: $MAIL_CONF not found" && exit 1
grep -q "^mail_location =" "$MAIL_CONF" && sed -i "s/^mail_location =.*/mail_location = maildir:~\/Maildir/" "$MAIL_CONF" || echo "mail_location = maildir:~\/Maildir" >> "$MAIL_CONF"

AUTH_CONF="/etc/dovecot/conf.d/10-auth.conf"
[ ! -f "$AUTH_CONF" ] && echo "Error: $AUTH_CONF not found" && exit 1
grep -q "^disable_plaintext_auth =" "$AUTH_CONF" && sed -i "s/^disable_plaintext_auth =.*/disable_plaintext_auth = yes/" "$AUTH_CONF" || echo "disable_plaintext_auth = yes" >> "$AUTH_CONF"

MASTER_CONF="/etc/dovecot/conf.d/10-master.conf"
[ ! -f "$MASTER_CONF" ] && echo "Error: $MASTER_CONF not found" && exit 1
if ! grep -q "unix_listener /var/spool/postfix/private/auth" "$MASTER_CONF"; then
    sed -i "/^service auth {/a \  unix_listener /var/spool/postfix/private/auth {\n    mode = 0660\n    user = postfix\n    group = postfix\n  }" "$MASTER_CONF"
fi

# Create mailuser
useradd -m mailuser && echo "mailuser:pss123" | chpasswd

# Start services
systemctl enable postfix --now
systemctl enable dovecot --now

echo "Mail server setup completed! Run 'systemctl status postfix' and 'systemctl status dovecot' to verify."


#!/bin/bash
# Script to install and configure SSL for Postfix and Dovecot

# Install Certbot
dnf install -y certbot python3-certbot-nginx

# Obtain SSL certificate
certbot certonly --standalone -d rocketsmtp.site --non-interactive --agree-tos --email ericphan28@gmail.com

# Configure Postfix SSL
echo "smtpd_tls_cert_file = /etc/letsencrypt/live/rocketsmtp.site/fullchain.pem" >> /etc/postfix/main.cf
echo "smtpd_tls_key_file = /etc/letsencrypt/live/rocketsmtp.site/privkey.pem" >> /etc/postfix/main.cf
echo "smtpd_tls_security_level = may" >> /etc/postfix/main.cf
echo "smtp_tls_security_level = may" >> /etc/postfix/main.cf
echo "smtps inet n - n - - smtpd" >> /etc/postfix/master.cf
echo "  -o smtpd_tls_wrappermode=yes" >> /etc/postfix/master.cf
systemctl restart postfix

# Configure Dovecot SSL
sed -i "s|^ssl_cert =.*|ssl_cert = </etc/letsencrypt/live/rocketsmtp.site/fullchain.pem|" /etc/dovecot/conf.d/10-ssl.conf
sed -i "s|^ssl_key =.*|ssl_key = </etc/letsencrypt/live/rocketsmtp.site/privkey.pem|" /etc/dovecot/conf.d/10-ssl.conf
sed -i "s|^ssl =.*|ssl = yes|" /etc/dovecot/conf.d/10-ssl.conf
systemctl restart dovecot

echo "SSL setup completed! Test with:"
echo "  openssl s_client -connect 127.0.0.1:587 -starttls smtp (Postfix)"
echo "  openssl s_client -connect 127.0.0.1:993 (Dovecot)"

