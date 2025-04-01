#!/bin/bash

# Script cài đặt và cấu hình Roundcube trên AlmaLinux 9.3
# Đảm bảo đăng nhập thành công qua https://rocketsmtp.site

# Biến cấu hình
ROUNDCUBE_VERSION="1.6.7"
DOMAIN="rocketsmtp.site"
WEBROOT="/var/www/html/roundcube"
DB_NAME="roundcube_db"
DB_USER="roundcube_user"
DB_PASS="roundcube_pass123"
MAIL_USER="mailuser"
MAIL_PASS="pss123"
ROOT_DB_PASS="rootpass123"

# Bước 1: Cài đặt các gói cần thiết
dnf install -y epel-release
dnf install -y httpd mod_ssl php php-fpm php-mysqlnd php-gd php-mbstring php-xml php-intl php-zip \
    mariadb-server dovecot postfix telnet nano bind-utils tar firewalld s-nail wget certbot python3-certbot-apache

# Bước 2: Kích hoạt và khởi động dịch vụ
systemctl enable httpd --now
systemctl enable php-fpm --now
systemctl enable mariadb --now
systemctl enable dovecot --now
systemctl enable postfix --now
systemctl enable firewalld --now

# Bước 3: Mở port firewall
firewall-cmd --add-port={25,587,465,143,110,993,995,80,443}/tcp --permanent
firewall-cmd --reload

# Bước 4: Cấu hình SSL với Certbot (tắt Apache tạm thời nếu cần)
if [ ! -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]; then
    systemctl stop httpd
    certbot certonly --standalone -d ${DOMAIN} --non-interactive --agree-tos --email ericphan28@gmail.com
    systemctl start httpd
fi

# Bước 5: Cấu hình Postfix
CONFIG_FILE="/etc/postfix/main.cf"
[ ! -f "$CONFIG_FILE" ] && echo "Error: $CONFIG_FILE not found" && exit 1
sed -i "s|^myhostname =.*|myhostname = ${DOMAIN}|" "$CONFIG_FILE" || echo "myhostname = ${DOMAIN}" >> "$CONFIG_FILE"
sed -i "s|^mydomain =.*|mydomain = ${DOMAIN}|" "$CONFIG_FILE" || echo "mydomain = ${DOMAIN}" >> "$CONFIG_FILE"
sed -i "s|^myorigin =.*|myorigin = \$mydomain|" "$CONFIG_FILE" || echo "myorigin = \$mydomain" >> "$CONFIG_FILE"
sed -i "s|^inet_interfaces =.*|inet_interfaces = all|" "$CONFIG_FILE" || echo "inet_interfaces = all" >> "$CONFIG_FILE"
sed -i "s|^mydestination =.*|mydestination = \$myhostname, localhost.\$mydomain, localhost|" "$CONFIG_FILE" || echo "mydestination = \$myhostname, localhost.\$mydomain, localhost" >> "$CONFIG_FILE"
sed -i "s|^mynetworks =.*|mynetworks = 127.0.0.0/8, 103.176.20.154/32|" "$CONFIG_FILE" || echo "mynetworks = 127.0.0.0/8, 103.176.20.154/32" >> "$CONFIG_FILE"
sed -i "s|^smtpd_sasl_type =.*|smtpd_sasl_type = dovecot|" "$CONFIG_FILE" || echo "smtpd_sasl_type = dovecot" >> "$CONFIG_FILE"
sed -i "s|^smtpd_sasl_path =.*|smtpd_sasl_path = private/auth|" "$CONFIG_FILE" || echo "smtpd_sasl_path = private/auth" >> "$CONFIG_FILE"
sed -i "s|^smtpd_sasl_auth_enable =.*|smtpd_sasl_auth_enable = yes|" "$CONFIG_FILE" || echo "smtpd_sasl_auth_enable = yes" >> "$CONFIG_FILE"
sed -i "s|^smtpd_tls_cert_file =.*|smtpd_tls_cert_file = /etc/letsencrypt/live/${DOMAIN}/fullchain.pem|" "$CONFIG_FILE" || echo "smtpd_tls_cert_file = /etc/letsencrypt/live/${DOMAIN}/fullchain.pem" >> "$CONFIG_FILE"
sed -i "s|^smtpd_tls_key_file =.*|smtpd_tls_key_file = /etc/letsencrypt/live/${DOMAIN}/privkey.pem|" "$CONFIG_FILE" || echo "smtpd_tls_key_file = /etc/letsencrypt/live/${DOMAIN}/privkey.pem" >> "$CONFIG_FILE"
sed -i "s|^smtpd_tls_security_level =.*|smtpd_tls_security_level = may|" "$CONFIG_FILE" || echo "smtpd_tls_security_level = may" >> "$CONFIG_FILE"
sed -i "s|^smtp_tls_security_level =.*|smtp_tls_security_level = may|" "$CONFIG_FILE" || echo "smtp_tls_security_level = may" >> "$CONFIG_FILE"
echo "submission inet n - n - - smtpd" >> /etc/postfix/master.cf
echo "smtps inet n - n - - smtpd" >> /etc/postfix/master.cf
echo "  -o smtpd_tls_wrappermode=yes" >> /etc/postfix/master.cf

# Bước 6: Cấu hình Dovecot
cat > /etc/dovecot/conf.d/10-auth.conf <<EOF
disable_plaintext_auth = yes
auth_mechanisms = plain
auth_username_format = %u
passdb {
  driver = passwd-file
  args = /etc/dovecot/users
}
userdb {
  driver = passwd-file
  args = /etc/dovecot/users
}
auth_debug = yes
auth_verbose = yes
EOF

cat > /etc/dovecot/users <<EOF
${MAIL_USER}@${DOMAIN}:{PLAIN}${MAIL_PASS}:1000:1000::/home/${MAIL_USER}
EOF
chmod 600 /etc/dovecot/users
chown dovecot:dovecot /etc/dovecot/users

cat > /etc/dovecot/conf.d/10-ssl.conf <<EOF
ssl = required
ssl_cert = </etc/letsencrypt/live/${DOMAIN}/fullchain.pem
ssl_key = </etc/letsencrypt/live/${DOMAIN}/privkey.pem
ssl_cipher_list = PROFILE=SYSTEM
EOF

cat > /etc/dovecot/conf.d/10-mail.conf <<EOF
mail_location = maildir:~/Maildir
namespace inbox {
  inbox = yes
  location =
  mailbox Drafts {
    special_use = \Drafts
  }
  mailbox Junk {
    special_use = \Junk
  }
  mailbox Sent {
    special_use = \Sent
  }
  mailbox "Sent Messages" {
    special_use = \Sent
  }
  mailbox Trash {
    special_use = \Trash
  }
  prefix =
}
EOF

cat > /etc/dovecot/conf.d/10-master.conf <<EOF
service imap-login {
  inet_listener imap {
    port = 143
  }
  inet_listener imaps {
    port = 993
    ssl = yes
  }
}
service pop3-login {
  inet_listener pop3 {
    port = 110
  }
  inet_listener pop3s {
    port = 995
    ssl = yes
  }
}
service auth {
  unix_listener /var/spool/postfix/private/auth {
    mode = 0660
    user = postfix
    group = postfix
  }
}
EOF

# Bước 7: Tạo user mailuser
useradd -m ${MAIL_USER} -s /sbin/nologin || true
echo "${MAIL_USER}:${MAIL_PASS}" | chpasswd

# Bước 8: Cấu hình PHP-FPM
sed -i "s|listen = .*|listen = /run/php-fpm/www.sock|" /etc/php-fpm.d/www.conf
sed -i "s|;listen.owner = .*|listen.owner = apache|" /etc/php-fpm.d/www.conf
sed -i "s|;listen.group = .*|listen.group = apache|" /etc/php-fpm.d/www.conf
sed -i "s|;listen.mode = .*|listen.mode = 0660|" /etc/php-fpm.d/www.conf

# Bước 9: Cài đặt Roundcube
wget https://github.com/roundcube/roundcubemail/releases/download/${ROUNDCUBE_VERSION}/roundcubemail-${ROUNDCUBE_VERSION}-complete.tar.gz -P /tmp
tar -xzf /tmp/roundcubemail-${ROUNDCUBE_VERSION}-complete.tar.gz -C /tmp
mv /tmp/roundcubemail-${ROUNDCUBE_VERSION} ${WEBROOT}
chown -R apache:apache ${WEBROOT}
chmod -R 755 ${WEBROOT}
mkdir -p ${WEBROOT}/logs
chown apache:apache ${WEBROOT}/logs
chmod 755 ${WEBROOT}/logs

# Bước 10: Cấu hình Apache VirtualHost
cat > /etc/httpd/conf.d/roundcube.conf <<EOF
<VirtualHost *:80>
    ServerName ${DOMAIN}
    Redirect permanent / https://${DOMAIN}/
</VirtualHost>
<VirtualHost *:443>
    ServerName ${DOMAIN}
    DocumentRoot ${WEBROOT}
    SSLEngine on
    SSLCertificateFile /etc/letsencrypt/live/${DOMAIN}/fullchain.pem
    SSLCertificateKeyFile /etc/letsencrypt/live/${DOMAIN}/privkey.pem
    <Directory ${WEBROOT}>
        Options -Indexes
        AllowOverride All
        Require all granted
        DirectoryIndex index.php
    </Directory>
    <FilesMatch "\.php$">
        SetHandler "proxy:unix:/run/php-fpm/www.sock|fcgi://localhost"
    </FilesMatch>
</VirtualHost>
EOF

# Bước 11: Cấu hình MariaDB
mysql -u root -p${ROOT_DB_PASS} -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME};" || echo "Error: Cannot create database. Check root password."
mysql -u root -p${ROOT_DB_PASS} -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
mysql -u root -p${ROOT_DB_PASS} -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';"
mysql -u root -p${ROOT_DB_PASS} -e "FLUSH PRIVILEGES;"
mysql -u ${DB_USER} -p${DB_PASS} ${DB_NAME} < ${WEBROOT}/SQL/mysql.initial.sql

# Bước 12: Cấu hình Roundcube
cp ${WEBROOT}/config/config.inc.php.sample ${WEBROOT}/config/config.inc.php
sed -i "s|\$config\['db_dsnw'\] = .*|\$config['db_dsnw'] = 'mysql://${DB_USER}:${DB_PASS}@localhost/${DB_NAME}';|" ${WEBROOT}/config/config.inc.php
sed -i "s|\$config\['default_host'\] = .*|\$config['default_host'] = 'localhost';|" ${WEBROOT}/config/config.inc.php
sed -i "s|\$config\['smtp_host'\] = .*|\$config['smtp_host'] = 'localhost:587';|" ${WEBROOT}/config/config.inc.php
sed -i "s|\$config\['smtp_user'\] = .*|\$config['smtp_user'] = '%u';|" ${WEBROOT}/config/config.inc.php
sed -i "s|\$config\['smtp_pass'\] = .*|\$config['smtp_pass'] = '%p';|" ${WEBROOT}/config/config.inc.php
sed -i "/\$config\['db_dsnw'\]/a \$config['log_driver'] = 'file';\n\$config['log_dir'] = '${WEBROOT}/logs/';" ${WEBROOT}/config/config.inc.php
chown apache:apache ${WEBROOT}/config/config.inc.php
chmod 644 ${WEBROOT}/config/config.inc.php

# Bước 13: Khởi động lại dịch vụ
systemctl restart httpd
systemctl restart php-fpm
systemctl restart dovecot
systemctl restart postfix

# Bước 14: Xóa file tạm
rm -f /tmp/roundcubemail-${ROUNDCUBE_VERSION}-complete.tar.gz

echo "Cấu hình hoàn tất! Truy cập https://${DOMAIN} để đăng nhập với ${MAIL_USER}@${DOMAIN} / ${MAIL_PASS}"
echo "Kiểm tra log nếu có lỗi:"
echo "  tail -n 50 ${WEBROOT}/logs/errors.log"
echo "  tail -n 50 /var/log/maillog"
