#!/bin/bash

# Script cài đặt Postfix, Dovecot, Roundcube trên AlmaLinux 9
# Domain: rocketsmtp.site
# IP: 103.176.20.154
# User: mailuser
# Password: pss123
# MySQL Root Password: Tnt@510510

# Cập nhật hệ thống
echo "Đang cập nhật hệ thống..."
sudo dnf update -y

# Cài đặt EPEL
echo "Cài đặt kho EPEL..."
sudo dnf install epel-release -y

# Cài đặt các công cụ cơ bản
echo "Cài đặt các công cụ cơ bản..."
sudo dnf install -y nano telnet bind-utils tar wget sed

# Cài đặt Apache
echo "Cài đặt Apache..."
sudo dnf install -y httpd
sudo systemctl start httpd
sudo systemctl enable httpd

# Cài đặt MariaDB
echo "Cài đặt MariaDB..."
sudo dnf install -y mariadb-server
sudo systemctl start mariadb
sudo systemctl enable mariadb

# Bảo mật MariaDB
echo "Đang bảo mật MariaDB..."
sudo mysql_secure_installation <<EOF

y
Tnt@510510
Tnt@510510
n
y
y
y
EOF

# Cài đặt PHP 8.3 và các module cần thiết
echo "Cài đặt PHP 8.1 và module..."
sudo dnf module enable php:8.3 -y
sudo dnf install -y php83-php php83-php-mysqlnd php83-php-gd php83-php-imap php83-php-ldap php83-php-odbc php83-php-pear php83-php-xml php83-php-mbstring php83-php-snmp php83-php-soap php83-php-intl php83-php-zip
sudo systemctl restart httpd

# Cài đặt Postfix
echo "Cài đặt Postfix..."
sudo dnf install -y postfix
sudo systemctl start postfix
sudo systemctl enable postfix

# Cấu hình Postfix
echo "Cấu hình Postfix..."
sudo postconf -e "myhostname = rocketsmtp.site"
sudo postconf -e "mydomain = rocketsmtp.site"
sudo postconf -e "myorigin = \$mydomain"
sudo postconf -e "inet_interfaces = all"
sudo postconf -e "inet_protocols = ipv4"
sudo postconf -e "mydestination = \$myhostname, localhost.\$mydomain, localhost"
sudo postconf -e "mynetworks = 127.0.0.0/8, 103.176.20.154/32"
sudo postconf -e "home_mailbox = Maildir/"
sudo systemctl restart postfix

# Cài đặt Dovecot
echo "Cài đặt Dovecot..."
sudo dnf install -y dovecot
sudo systemctl start dovecot
sudo systemctl enable dovecot

# Cấu hình Dovecot
echo "Cấu hình Dovecot..."
sudo bash -c 'cat > /etc/dovecot/dovecot.conf <<EOF
listen = *
protocols = imap
EOF'

sudo bash -c 'cat > /etc/dovecot/conf.d/10-mail.conf <<EOF
mail_location = maildir:~/Maildir
EOF'

sudo bash -c 'cat > /etc/dovecot/conf.d/10-auth.conf <<EOF
disable_plaintext_auth = no
auth_mechanisms = plain login
!include auth-system.conf.ext
EOF'

sudo bash -c 'cat > /etc/dovecot/conf.d/10-master.conf <<EOF
service imap-login {
  inet_listener imap {
    port = 143
  }
}
service auth {
  unix_listener auth-userdb {
    mode = 0666
  }
}
EOF'

sudo systemctl restart dovecot

# Tạo cơ sở dữ liệu và người dùng cho Roundcube
echo "Tạo cơ sở dữ liệu và người dùng cho Roundcube..."
DB_NAME="roundcubemail"
DB_USER="roundcubeuser"
DB_PASS="roundcubepass"
MYSQL_ROOT_PASSWORD="Tnt@510510"

sudo mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "DROP DATABASE IF EXISTS $DB_NAME;"
sudo mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "CREATE DATABASE $DB_NAME;"
sudo mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
sudo mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';"
sudo mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "FLUSH PRIVILEGES;"

# Tải và cài đặt Roundcube
echo "Tải và cài đặt Roundcube..."
cd /var/www/html
sudo wget -q https://github.com/roundcube/roundcubemail/releases/download/1.5.0/roundcubemail-1.5.0-complete.tar.gz
sudo tar -xvf roundcubemail-1.5.0-complete.tar.gz
sudo mv roundcubemail-1.5.0 roundcube
sudo chown -R apache:apache /var/www/html/roundcube
sudo chmod -R 755 /var/www/html/roundcube

# Cấu hình Roundcube
echo "Cấu hình Roundcube..."
cd /var/www/html/roundcube
sudo cp config/config.inc.php.sample config/config.inc.php
sudo sed -i "s|\$config\['db_dsnw'\] = '.*';|\$config\['db_dsnw'\] = 'mysql://$DB_USER:$DB_PASS@localhost/$DB_NAME';|" config/config.inc.php
sudo sed -i "s|\$config\['default_host'\] = '.*';|\$config\['default_host'\] = 'localhost';|" config/config.inc.php
sudo sed -i "s|\$config\['smtp_server'\] = '.*';|\$config\['smtp_server'\] = 'localhost';|" config/config.inc.php
sudo sed -i "s|\$config\['smtp_user'\] = '.*';|\$config\['smtp_user'\] = '%u';|" config/config.inc.php
sudo sed -i "s|\$config\['smtp_pass'\] = '.*';|\$config\['smtp_pass'\] = '%p';|" config/config.inc.php
sudo sed -i "s|\$config\['imap_auth_type'\] = .*;|\$config\['imap_auth_type'\] = 'PLAIN';|" config/config.inc.php

# Khởi tạo cơ sở dữ liệu Roundcube
echo "Khởi tạo cơ sở dữ liệu Roundcube..."
sudo mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" < /var/www/html/roundcube/SQL/mysql.initial.sql

# Cấu hình Apache cho Roundcube
echo "Cấu hình Apache cho Roundcube..."
sudo bash -c 'cat > /etc/httpd/conf.d/roundcube.conf <<EOF
Alias /roundcube /var/www/html/roundcube

<Directory /var/www/html/roundcube>
    Options -Indexes
    AllowOverride All
    Order allow,deny
    Allow from all
</Directory>
EOF'
sudo systemctl restart httpd

# Tạo người dùng email
echo "Tạo người dùng email mailuser..."
sudo useradd -m mailuser || true
echo "pss123" | sudo passwd --stdin mailuser
sudo mkdir -p /home/mailuser/Maildir
sudo chown -R mailuser:mailuser /home/mailuser/Maildir

# Mở port trên firewall
echo "Mở port trên firewall..."
sudo firewall-cmd --add-service=http --permanent
sudo firewall-cmd --add-service=smtp --permanent
sudo firewall-cmd --add-port=143/tcp --permanent
sudo firewall-cmd --reload

# Kiểm tra trạng thái dịch vụ
echo "Kiểm tra trạng thái dịch vụ..."
sudo systemctl status postfix
sudo systemctl status dovecot
sudo systemctl status httpd

# Hoàn tất cài đặt
echo "Cài đặt hoàn tất!"
echo "Truy cập Roundcube tại: http://103.176.20.154/roundcube"
echo "Đăng nhập với: mailuser / pss123"
echo "Kiểm tra log nếu có lỗi: /var/log/dovecot.log và /var/www/html/roundcube/logs/errors.log"
