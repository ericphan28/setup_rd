#!/bin/bash

# Script cài đặt và cấu hình Roundcube
# Chạy với quyền root: sudo bash setup_roundcube.sh

# Biến cấu hình
DOMAIN="rocketsmtp.site"
HOSTNAME="mail.rocketsmtp.site"

# Kiểm tra quyền root
if [ "$(id -u)" != "0" ]; then
   echo "Script này cần chạy với quyền root. Sử dụng sudo hoặc đăng nhập root."
   exit 1
fi

echo "Bắt đầu cài đặt và cấu hình Roundcube..."

# Bước 1: Cài đặt EPEL (nếu chưa cài đặt)
echo "Cài đặt EPEL để đảm bảo các gói PHP bổ sung..."
dnf install -y epel-release || { echo "Lỗi: Không thể cài đặt EPEL."; exit 1; }

# Bước 2: Cài đặt kho Remi và kích hoạt PHP 8.3
echo "Cài đặt kho Remi và kích hoạt PHP 8.3..."
dnf install -y https://rpms.remirepo.net/enterprise/remi-release-9.rpm || { echo "Lỗi: Không thể cài đặt kho Remi."; exit 1; }
dnf install -y dnf-utils || { echo "Lỗi: Không thể cài đặt dnf-utils."; exit 1; }
dnf module reset php -y
dnf module enable php:remi-8.3 -y || { echo "Lỗi: Không thể kích hoạt PHP 8.3."; exit 1; }

# Bước 3: Cài đặt Apache, PHP và các module cần thiết (bao gồm php-imap)
echo "Cài đặt Apache, PHP và các module cần thiết..."
dnf install -y httpd php php-pdo php-mysqlnd php-gd php-mbstring php-json php-xml php-imap || { echo "Lỗi: Không thể cài đặt Apache và PHP. Kiểm tra xem tất cả các gói có sẵn trong kho lưu trữ không."; exit 1; }

# Bước 4: Tải và cài đặt Roundcube
echo "Tải và cài đặt Roundcube..."
wget -O roundcube.tar.gz https://github.com/roundcube/roundcubemail/releases/download/1.6.9/roundcubemail-1.6.9-complete.tar.gz || { echo "Lỗi: Không thể tải Roundcube."; exit 1; }
tar -xzf roundcube.tar.gz -C /var/www/html/ || { echo "Lỗi: Không thể giải nén Roundcube."; exit 1; }
mv /var/www/html/roundcubemail-1.6.9 /var/www/html/roundcube
chown -R apache:apache /var/www/html/roundcube
chmod -R 755 /var/www/html/roundcube

# Bước 5: Cấu hình Roundcube
echo "Cấu hình Roundcube..."
cp /var/www/html/roundcube/config/config.inc.php.sample /var/www/html/roundcube/config/config.inc.php
sed -i "s|\$config\['db_dsnw'\] = .*|\$config\['db_dsnw'\] = 'sqlite:////var/www/html/roundcube/db/sqlite.db?mode=0646';|" /var/www/html/roundcube/config/config.inc.php
sed -i "s|\$config\['default_host'\] = .*|\$config\['default_host'\] = 'localhost';|" /var/www/html/roundcube/config/config.inc.php
sed -i "s|\$config\['smtp_server'\] = .*|\$config\['smtp_server'\] = 'localhost';|" /var/www/html/roundcube/config/config.inc.php
sed -i "s|\$config\['smtp_port'\] = .*|\$config\['smtp_port'\] = 587;|" /var/www/html/roundcube/config/config.inc.php
sed -i "s|\$config\['smtp_user'\] = .*|\$config\['smtp_user'\] = '%u';|" /var/www/html/roundcube/config/config.inc.php
sed -i "s|\$config\['smtp_pass'\] = .*|\$config\['smtp_pass'\] = '%p';|" /var/www/html/roundcube/config/config.inc.php
mkdir -p /var/www/html/roundcube/db
touch /var/www/html/roundcube/db/sqlite.db
chown -R apache:apache /var/www/html/roundcube/db
chmod 664 /var/www/html/roundcube/db/sqlite.db

# Bước 6: Cấu hình Apache
echo "Cấu hình Apache..."
cat > /etc/httpd/conf.d/roundcube.conf << EOF
<VirtualHost *:80>
    ServerName $HOSTNAME
    DocumentRoot /var/www/html/roundcube

    <Directory /var/www/html/roundcube>
        Options -Indexes +FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog /var/log/httpd/roundcube_error.log
    CustomLog /var/log/httpd/roundcube_access.log combined
</VirtualHost>
EOF

# Bước 7: Khởi động Apache
echo "Khởi động Apache..."
systemctl start httpd
systemctl enable httpd

# Bước 8: Kiểm tra trạng thái dịch vụ
echo "Kiểm tra trạng thái dịch vụ..."
systemctl status httpd

# Bước 9: Hoàn tất
echo "Cài đặt và cấu hình Roundcube hoàn tất!"
echo "Roundcube đã được cài đặt và cấu hình."
echo "Bạn có thể truy cập Roundcube tại: http://$HOSTNAME"
echo "Bạn có thể tiếp tục với bước tiếp theo (tạo user email và kích hoạt SSL)."