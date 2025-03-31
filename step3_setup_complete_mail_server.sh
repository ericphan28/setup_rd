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
sed -i "/smtpd_tls_cert_file = \/etc\/pki\/tls\/certs\/postfix.pem/d" /etc/postfix/main.cf
sed -i "/smtpd_tls_key_file = \/etc\/pki\/tls\/private\/postfix.key/d" /etc/postfix/main.cf
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


#!/bin/bash
# Script to install and configure Apache and PHP for Roundcube

# Install Apache
dnf install -y httpd mod_ssl
systemctl enable httpd --now

sed -i "s|SSLCertificateFile.*|SSLCertificateFile /etc/letsencrypt/live/rocketsmtp.site/fullchain.pem|" /etc/httpd/conf.d/ssl.conf
sed -i "s|SSLCertificateKeyFile.*|SSLCertificateKeyFile /etc/letsencrypt/live/rocketsmtp.site/privkey.pem|" /etc/httpd/conf.d/ssl.conf

systemctl restart httpd

echo "Apache setup completed! Test with:"
echo "  curl http://127.0.0.1 (HTTP)"
echo "  curl https://127.0.0.1 (HTTP)"
echo "  openssl s_client -connect 127.0.0.1:443 (HTTPS)"

dnf install -y php php-fpm php-mysqlnd php-gd php-mbstring php-xml php-intl php-zip

echo "<VirtualHost *:80>
    ServerName rocketsmtp.site
    DocumentRoot /var/www/html
    <Directory /var/www/html>
        Options -Indexes
        AllowOverride All
        Require all granted
        DirectoryIndex index.php
    </Directory>
    <FilesMatch \".php$\">
        SetHandler \"proxy:unix:/run/php-fpm/www.sock|fcgi://localhost\"
    </FilesMatch>
</VirtualHost>
<VirtualHost *:443>
    ServerName rocketsmtp.site
    DocumentRoot /var/www/html
    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/rocketsmtp.site/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/rocketsmtp.site/privkey.pem
    <Directory /var/www/html>
        Options -Indexes
        AllowOverride All
        Require all granted
        DirectoryIndex index.php
    </Directory>
    <FilesMatch \".php$\">
        SetHandler \"proxy:unix:/run/php-fpm/www.sock|fcgi://localhost\"
    </FilesMatch>
</VirtualHost>" > /etc/httpd/conf.d/php.conf

systemctl restart httpd

wget https://github.com/roundcube/roundcubemail/releases/download/1.6.7/roundcubemail-1.6.7-complete.tar.gz -P /tmp
tar -xzf /tmp/roundcubemail-1.6.7-complete.tar.gz -C /tmp
mv /tmp/roundcubemail-1.6.7 /var/www/html/roundcube
chown -R apache:apache /var/www/html/roundcube
chmod -R 755 /var/www/html/roundcube

rm -f /etc/httpd/conf.d/php.conf

echo "<VirtualHost *:80>
    ServerName rocketsmtp.site
    DocumentRoot /var/www/html/roundcube
    <Directory /var/www/html/roundcube>
        Options -Indexes
        AllowOverride All
        Require all granted
        DirectoryIndex index.php
    </Directory>
    <FilesMatch \".php$\">
        SetHandler \"proxy:unix:/run/php-fpm/www.sock|fcgi://localhost\"
    </FilesMatch>
</VirtualHost>
<VirtualHost *:443>
    ServerName rocketsmtp.site
    DocumentRoot /var/www/html/roundcube
    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/rocketsmtp.site/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/rocketsmtp.site/privkey.pem
    <Directory /var/www/html/roundcube>
        Options -Indexes
        AllowOverride All
        Require all granted
        DirectoryIndex index.php
    </Directory>
    <FilesMatch \".php$\">
        SetHandler \"proxy:unix:/run/php-fpm/www.sock|fcgi://localhost\"
    </FilesMatch>
</VirtualHost>" > /etc/httpd/conf.d/roundcube.conf


chown -R apache:apache /var/www/html/roundcube
chmod -R 755 /var/www/html/roundcube
chmod 644 /var/www/html/roundcube/config/config.inc.php




# Install MariaDB
dnf install -y mariadb-server
systemctl enable mariadb --now
echo -e "\nrootpass123\nY\nY\nY\nY\nY" | mysql_secure_installation

# Create database and user
mysql -u root -prootpass123 -e "CREATE DATABASE roundcube_db; CREATE USER 'roundcube_user'@'localhost' IDENTIFIED BY 'roundcube_pass123'; GRANT ALL PRIVILEGES ON roundcube_db.* TO 'roundcube_user'@'localhost'; FLUSH PRIVILEGES;"

# Download and install Roundcube
wget https://github.com/roundcube/roundcubemail/releases/download/1.6.7/roundcubemail-1.6.7-complete.tar.gz -P /tmp
tar -xzf /tmp/roundcubemail-1.6.7-complete.tar.gz -C /tmp
mv /tmp/roundcubemail-1.6.7 /var/www/html/roundcube
chown -R apache:apache /var/www/html/roundcube

# Configure Roundcube
# Sao chép file mẫu
cp /var/www/html/roundcube/config/config.inc.php.sample /var/www/html/roundcube/config/config.inc.php

# Cấu hình database, IMAP, SMTP và log
sed -i "s|$config\['db_dsnw'\] = .*|$config['db_dsnw'] = 'mysql://roundcube_user:roundcube_pass123@localhost/roundcube_db';|" /var/www/html/roundcube/config/config.inc.php
sed -i "s|$config\['default_host'\] = .*|$config['default_host'] = 'localhost';|" /var/www/html/roundcube/config/config.inc.php
sed -i "s|$config\['smtp_host'\] = .*|$config['smtp_host'] = 'localhost:587';|" /var/www/html/roundcube/config/config.inc.php
sed -i "s|$config\['smtp_user'\] = .*|$config['smtp_user'] = '%u';|" /var/www/html/roundcube/config/config.inc.php
sed -i "s|$config\['smtp_pass'\] = .*|$config['smtp_pass'] = '%p';|" /var/www/html/roundcube/config/config.inc.php
sed -i "/$config\['db_dsnw'\]/a \$config['log_driver'] = 'file';\n\$config['log_dir'] = '/var/www/html/roundcube/logs/';" /var/www/html/roundcube/config/config.inc.php

# Đảm bảo quyền file
chown apache:apache /var/www/html/roundcube/config/config.inc.php
chmod 644 /var/www/html/roundcube/config/config.inc.php


# Tạo database và user (nếu chưa có)
mysql -u root -p <<EOF
CREATE DATABASE IF NOT EXISTS roundcube_db;
CREATE USER IF NOT EXISTS 'roundcube_user'@'localhost' IDENTIFIED BY 'roundcube_pass123';
GRANT ALL PRIVILEGES ON roundcube_db.* TO 'roundcube_user'@'localhost';
FLUSH PRIVILEGES;
EXIT;
EOF

# Nhập mật khẩu root khi được yêu cầu (ví dụ: rootpass123)

# Chạy file SQL để tạo bảng
mysql -u roundcube_user -proundcube_pass123 roundcube_db < /var/www/html/roundcube/SQL/mysql.initial.sql

echo "Roundcube setup completed! Access at:"
echo "  https://rocketsmtp.site/roundcube"
echo "Login with: mailuser@rocketsmtp.site / pss123"
