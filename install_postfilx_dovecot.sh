#!/bin/bash

# Cài đặt các gói cần thiết
dnf install -y postfix dovecot cyrus-sasl cyrus-sasl-plain cyrus-sasl-md5 cyrus-sasl-sql s-nail bind-utils openssl swaks || { echo "Cài đặt gói thất bại"; exit 1; }

# Cấu hình Postfix
postconf -e "myhostname = rocketsmtp.site" \
         "mydomain = rocketsmtp.site" \
         "myorigin = \$mydomain" \
         "inet_interfaces = all" \
         "inet_protocols = all" \
         "mydestination = \$myhostname, localhost.\$mydomain, localhost, \$mydomain" \
         "mynetworks = 127.0.0.0/8, 103.176.20.154" \
         "home_mailbox = Maildir/" \
         "smtpd_banner = \$myhostname ESMTP" \
         "smtpd_use_tls = yes" \
         "smtpd_tls_security_level = may" \
         "smtpd_sasl_auth_enable = yes" \
         "smtpd_sasl_type = cyrus" \
         "smtpd_sasl_path = smtpd" \
         "smtpd_sasl_local_domain = rocketsmtp.site" \
         "smtpd_sasl_security_options = noanonymous" \
         "broken_sasl_auth_clients = yes" \
         "smtpd_relay_restrictions = permit_mynetworks, permit_sasl_authenticated, defer_unauth_destination" \
         "smtpd_recipient_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_unauth_destination"

# Tạo chứng chỉ tự ký
mkdir -p /etc/ssl/certs /etc/ssl/private
openssl req -new -x509 -days 365 -nodes \
    -out /etc/ssl/certs/postfix.pem \
    -keyout /etc/ssl/private/postfix.key \
    -subj "/CN=rocketsmtp.site" || { echo "Tạo chứng chỉ thất bại"; exit 1; }
chmod 600 /etc/ssl/private/postfix.key
postconf -e "smtpd_tls_cert_file = /etc/ssl/certs/postfix.pem" \
         "smtpd_tls_key_file = /etc/ssl/private/postfix.key"

# Cấu hình SASL
cat <<EOF > /etc/sasl2/smtpd.conf
pwcheck_method: auxprop
auxprop_plugin: sasldb
mech_list: PLAIN LOGIN
EOF
chmod 640 /etc/sasl2/smtpd.conf
chown postfix:postfix /etc/sasl2/smtpd.conf

# Cấu hình Dovecot
sed -i 's/^#disable_plaintext_auth = yes/disable_plaintext_auth = no/' /etc/dovecot/conf.d/10-auth.conf
sed -i 's/^#mail_location =/mail_location = maildir:~\/Maildir/' /etc/dovecot/conf.d/10-mail.conf
sed -i 's/^#ssl = yes/ssl = no/' /etc/dovecot/conf.d/10-ssl.conf
echo "auth_mechanisms = plain login" >> /etc/dovecot/conf.d/10-auth.conf

# Tạo người dùng thử nghiệm
useradd -m -s /sbin/nologin testuser || { echo "Tạo user thất bại"; exit 1; }
echo "testuser:Test@123" | chpasswd
mkdir -p /home/testuser/Maildir
chown -R testuser:testuser /home/testuser/Maildir

# Cấu hình SASL password
echo "Test@123" | saslpasswd2 -c -u rocketsmtp.site -a smtp testuser
chown postfix:postfix /etc/sasl2/sasldb2
chmod 600 /etc/sasl2/sasldb2

# Khởi động dịch vụ
systemctl enable --now postfix dovecot saslauthd || { echo "Khởi động dịch vụ thất bại"; exit 1; }
systemctl restart postfix dovecot saslauthd

# Cấu hình tường lửa
firewall-cmd --add-service=smtp --permanent
firewall-cmd --add-service=imap --permanent
firewall-cmd --add-service=pop3 --permanent
firewall-cmd --reload

#!/bin/bash

# Script nối tiếp để cài đặt Roundcube sau khi đã cài Postfix và Dovecot
# Giả định: Script trước đã cài Postfix, Dovecot, SASL, và tạo user testuser

# Cập nhật hệ thống
dnf update -y || { echo "Cập nhật hệ thống thất bại"; exit 1; }

# Cài đặt EPEL và các công cụ cơ bản
dnf install -y epel-release nano telnet bind-utils tar wget sed || { echo "Cài đặt công cụ thất bại"; exit 1; }

# Cài đặt Apache
dnf install -y httpd || { echo "Cài đặt Apache thất bại"; exit 1; }
systemctl enable --now httpd

# Cài đặt MariaDB
dnf install -y mariadb-server || { echo "Cài đặt MariaDB thất bại"; exit 1; }
systemctl enable --now mariadb

# Bảo mật MariaDB
MYSQL_ROOT_PASSWORD="Tnt@510510"
mysql_secure_installation <<EOF || { echo "Bảo mật MariaDB thất bại"; exit 1; }

y
$MYSQL_ROOT_PASSWORD
$MYSQL_ROOT_PASSWORD
n
y
y
y
EOF

# Cài đặt PHP 8.3 từ Remi repository
dnf install -y https://rpms.remirepo.net/enterprise/remi-release-9.rpm
dnf module enable php:remi-8.3 -y
dnf install -y php83-php php83-php-mysqlnd php83-php-gd php83-php-imap php83-php-ldap php83-php-pear php83-php-xml php83-php-mbstring php83-php-intl php83-php-zip || { echo "Cài đặt PHP thất bại"; exit 1; }
systemctl restart httpd

# Tạo cơ sở dữ liệu và người dùng cho Roundcube
DB_NAME="roundcubemail"
DB_USER="roundcubeuser"
DB_PASS="roundcubepass"
mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "DROP DATABASE IF EXISTS $DB_NAME;"
mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "CREATE DATABASE $DB_NAME;" || { echo "Tạo database thất bại"; exit 1; }
mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "FLUSH PRIVILEGES;"

# Tải và cài đặt Roundcube
cd /var/www/html
wget -q https://github.com/roundcube/roundcubemail/releases/download/1.5.0/roundcubemail-1.5.0-complete.tar.gz || { echo "Tải Roundcube thất bại"; exit 1; }
tar -xvf roundcubemail-1.5.0-complete.tar.gz
mv roundcubemail-1.5.0 roundcube
chown -R apache:apache /var/www/html/roundcube
chmod -R 755 /var/www/html/roundcube

# Cấu hình Roundcube
cd /var/www/html/roundcube
cp config/config.inc.php.sample config/config.inc.php
sed -i "s|\$config\['db_dsnw'\] = '.*';|\$config\['db_dsnw'\] = 'mysql://$DB_USER:$DB_PASS@localhost/$DB_NAME';|" config/config.inc.php
sed -i "s|\$config\['default_host'\] = '.*';|\$config\['default_host'\] = 'rocketsmtp.site';|" config/config.inc.php
sed -i "s|\$config\['smtp_server'\] = '.*';|\$config\['smtp_server'\] = 'rocketsmtp.site';|" config/config.inc.php
sed -i "s|\$config\['smtp_user'\] = '.*';|\$config\['smtp_user'\] = '%u';|" config/config.inc.php
sed -i "s|\$config\['smtp_pass'\] = '.*';|\$config\['smtp_pass'\] = '%p';|" config/config.inc.php
sed -i "s|\$config\['imap_auth_type'\] = .*;|\$config\['imap_auth_type'\] = 'PLAIN';|" config/config.inc.php

# Khởi tạo cơ sở dữ liệu Roundcube
mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < /var/www/html/roundcube/SQL/mysql.initial.sql || { echo "Khởi tạo database Roundcube thất bại"; exit 1; }

# Cấu hình Apache cho Roundcube
cat <<EOF > /etc/httpd/conf.d/roundcube.conf
Alias /roundcube /var/www/html/roundcube
<Directory /var/www/html/roundcube>
    Options -Indexes
    AllowOverride All
    Require all granted
</Directory>
EOF
systemctl restart httpd

# Tích hợp SSL từ script trước cho Dovecot
sed -i 's|^ssl =.*|ssl = yes|' /etc/dovecot/conf.d/10-ssl.conf
sed -i 's|^ssl_cert =.*|ssl_cert = </etc/ssl/certs/postfix.pem|' /etc/dovecot/conf.d/10-ssl.conf
sed -i 's|^ssl_key =.*|ssl_key = </etc/ssl/private/postfix.key|' /etc/dovecot/conf.d/10-ssl.conf
systemctl restart dovecot

# Mở port trên firewall
firewall-cmd --add-service=http --permanent
firewall-cmd --add-port=143/tcp --permanent  # IMAP
firewall-cmd --reload

# Kiểm tra trạng thái dịch vụ
echo "Kiểm tra trạng thái dịch vụ:"
systemctl status postfix dovecot httpd

# Hoàn tất
echo "Cài đặt Roundcube hoàn tất!"
echo "Truy cập: http://103.176.20.154/roundcube"
echo "Đăng nhập với: testuser / Test@123"
echo "Kiểm tra log nếu có lỗi: /var/log/dovecot.log và /var/www/html/roundcube/logs/errors.log"

echo "Cài đặt hoàn tất. Kiểm tra trạng thái dịch vụ:"
systemctl status postfix dovecot saslauthd
