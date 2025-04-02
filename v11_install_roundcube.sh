#!/bin/bash

# Script cài đặt và cấu hình Roundcube trên AlmaLinux 9.3
# Đảm bảo đăng nhập, gửi và nhận mail thành công qua https://rocketsmtp.site

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
# Tùy chọn SSL_TYPE (1 = tự ký, khác 1 = Let's Encrypt)
SSL_TYPE=1  # Giá trị mặc định, thay đổi trước khi chạy nếu cần

# Bước 1: Cài đặt các gói cần thiết
dnf install -y epel-release
dnf install -y httpd mod_ssl php php-fpm php-mysqlnd php-gd php-mbstring php-xml php-intl php-zip \
    mariadb-server dovecot postfix telnet nano bind-utils tar firewalld s-nail wget certbot python3-certbot-apache openssl

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

# Bước 4: Cấu hình SSL
if [ "$SSL_TYPE" -eq 1 ]; then
    echo "Tạo chứng chỉ SSL tự ký..."
    mkdir -p /etc/ssl/private
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/ssl/private/${DOMAIN}.key \
        -out /etc/ssl/private/${DOMAIN}.crt \
        -subj "/C=VN/ST=HCM/L=HCM/O=Local/OU=IT/CN=${DOMAIN}"
    SSL_CERT="/etc/ssl/private/${DOMAIN}.crt"
    SSL_KEY="/etc/ssl/private/${DOMAIN}.key"
else
    echo "Sử dụng Let's Encrypt để lấy chứng chỉ SSL..."
    if [ ! -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]; then
        systemctl stop httpd
        certbot certonly --standalone -d ${DOMAIN} --non-interactive --agree-tos --email ericphan28@gmail.com
        systemctl start httpd
    fi
    if [ ! -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]; then
        echo "Lỗi: Chứng chỉ SSL không được tạo. Kiểm tra log /var/log/letsencrypt/letsencrypt.log"
        exit 1
    fi
    SSL_CERT="/etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
    SSL_KEY="/etc/letsencrypt/live/${DOMAIN}/privkey.pem"
fi

# Bước 5: Cấu hình Postfix
CONFIG_FILE="/etc/postfix/main.cf"
[ ! -f "$CONFIG_FILE" ] && echo "Error: $CONFIG_FILE not found" && exit 1
sed -i "s|^myhostname =.*|myhostname = ${DOMAIN}|" "$CONFIG_FILE" || echo "myhostname = ${DOMAIN}" >> "$CONFIG_FILE"
sed -i "s|^mydomain =.*|mydomain = ${DOMAIN}|" "$CONFIG_FILE" || echo "mydomain = ${DOMAIN}" >> "$CONFIG_FILE"
sed -i "s|^myorigin =.*|myorigin = \$mydomain|" "$CONFIG_FILE" || echo "myorigin = \$mydomain" >> "$CONFIG_FILE"
sed -i "s|^inet_interfaces =.*|inet_interfaces = all|" "$CONFIG_FILE" || echo "inet_interfaces = all" >> "$CONFIG_FILE"
sed -i "s|^mydestination =.*|mydestination = \$myhostname, localhost.\$mydomain, localhost, ${DOMAIN}|" "$CONFIG_FILE" || echo "mydestination = \$myhostname, localhost.\$mydomain, localhost, ${DOMAIN}" >> "$CONFIG_FILE"
sed -i "s|^mynetworks =.*|mynetworks = 127.0.0.0/8, 103.176.20.154/32|" "$CONFIG_FILE" || echo "mynetworks = 127.0.0.0/8, 103.176.20.154/32" >> "$CONFIG_FILE"
# Cải tiến: Xóa và thêm dòng SASL để xử lý #, khoảng trắng, tab
sed -i "/^[ \t]*#*smtpd_sasl_type =/d" "$CONFIG_FILE"
echo "smtpd_sasl_type = dovecot" >> "$CONFIG_FILE"
sed -i "/^[ \t]*#*smtpd_sasl_path =/d" "$CONFIG_FILE"
echo "smtpd_sasl_path = private/auth" >> "$CONFIG_FILE"
sed -i "/^[ \t]*#*smtpd_sasl_auth_enable =/d" "$CONFIG_FILE"
echo "smtpd_sasl_auth_enable = yes" >> "$CONFIG_FILE"
sed -i "s|^smtpd_tls_cert_file =.*|smtpd_tls_cert_file = ${SSL_CERT}|" "$CONFIG_FILE" || echo "smtpd_tls_cert_file = ${SSL_CERT}" >> "$CONFIG_FILE"
sed -i "s|^smtpd_tls_key_file =.*|smtpd_tls_key_file = ${SSL_KEY}|" "$CONFIG_FILE" || echo "smtpd_tls_key_file = ${SSL_KEY}" >> "$CONFIG_FILE"
sed -i "s|^smtpd_tls_security_level =.*|smtpd_tls_security_level = may|" "$CONFIG_FILE" || echo "smtpd_tls_security_level = may" >> "$CONFIG_FILE"
sed -i "s|^smtp_tls_security_level =.*|smtp_tls_security_level = may|" "$CONFIG_FILE" || echo "smtp_tls_security_level = may" >> "$CONFIG_FILE"
echo "home_mailbox = Maildir/" >> "$CONFIG_FILE"
echo "local_recipient_maps = unix:passwd.byname" >> "$CONFIG_FILE"
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
ssl_cert = <${SSL_CERT}
ssl_key = <${SSL_KEY}
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
mkdir -p /home/${MAIL_USER}/Maildir/{cur,new,tmp}
chown -R ${MAIL_USER}:${MAIL_USER} /home/${MAIL_USER}/Maildir
chmod -R 700 /home/${MAIL_USER}/Maildir

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
    SSLCertificateFile ${SSL_CERT}
    SSLCertificateKeyFile ${SSL_KEY}
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

# Bước 13: Khởi động lại dịch vụ và kiểm tra lỗi
systemctl restart httpd || { echo "Lỗi khởi động httpd. Xem chi tiết:"; systemctl status httpd; journalctl -xeu httpd.service; exit 1; }
systemctl restart php-fpm || { echo "Lỗi khởi động php-fpm. Xem chi tiết:"; systemctl status php-fpm; journalctl -xeu php-fpm.service; exit 1; }
systemctl restart dovecot || { echo "Lỗi khởi động dovecot. Xem chi tiết:"; systemctl status dovecot; journalctl -xeu dovecot.service; exit 1; }
systemctl restart postfix || { echo "Lỗi khởi động postfix. Xem chi tiết:"; systemctl status postfix; journalctl -xeu postfix.service; exit 1; }

# Bước 14: Xóa file tạm
rm -f /tmp/roundcubemail-${ROUNDCUBE_VERSION}-complete.tar.gz

# Thêm lại: Thông báo hoàn tất và hướng dẫn kiểm tra log
echo "Cấu hình hoàn tất! Truy cập https://${DOMAIN} để đăng nhập với ${MAIL_USER}@${DOMAIN} / ${MAIL_PASS}"
echo "Kiểm tra log nếu có lỗi:"
echo "  tail -n 50 ${WEBROOT}/logs/errors.log"
echo "  tail -n 50 /var/log/maillog"
