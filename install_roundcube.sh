#!/bin/bash

# Script cài đặt Roundcube trên AlmaLinux 9
# Domain: rocketsmtp.site
# IP: 103.176.20.154
# User: mailuser
# Password: pss123

# Cập nhật hệ thống
echo "Đang cập nhật hệ thống..."
sudo dnf update -y
if [ $? -ne 0 ]; then
    echo "Lỗi: Không thể cập nhật hệ thống. Vui lòng kiểm tra kết nối mạng hoặc quyền root."
    exit 1
fi

# Kiểm tra và cài đặt các công cụ cơ bản
echo "Kiểm tra và cài đặt các công cụ cơ bản (nano, telnet, bind-utils)..."
for tool in nano telnet bind-utils; do
    if ! command -v $tool &> /dev/null; then
        echo "$tool chưa được cài đặt. Đang cài đặt $tool..."
        sudo dnf install -y $tool
        if [ $? -ne 0 ]; then
            echo "Lỗi: Không thể cài đặt $tool. Vui lòng kiểm tra lại."
            exit 1
        else
            echo "$tool đã được cài đặt thành công."
        fi
    else
        echo "$tool đã được cài đặt."
    fi
done

# Cài đặt Apache
echo "Cài đặt Apache..."
sudo dnf install -y httpd
if [ $? -ne 0 ]; then
    echo "Lỗi: Không thể cài đặt Apache."
    exit 1
fi
sudo systemctl start httpd
sudo systemctl enable httpd
if [ $? -ne 0 ]; then
    echo "Lỗi: Không thể khởi động hoặc kích hoạt Apache."
    exit 1
fi
echo "Apache đã được cài đặt và khởi động thành công."

# Cài đặt MariaDB
echo "Cài đặt MariaDB..."
sudo dnf install -y mariadb-server
if [ $? -ne 0 ]; then
    echo "Lỗi: Không thể cài đặt MariaDB."
    exit 1
fi
sudo systemctl start mariadb
sudo systemctl enable mariadb
if [ $? -ne 0 ]; then
    echo "Lỗi: Không thể khởi động hoặc kích hoạt MariaDB."
    exit 1
fi
echo "MariaDB đã được cài đặt và khởi động thành công."

# Bảo mật MariaDB
echo "Đang bảo mật MariaDB... Vui lòng làm theo hướng dẫn trên màn hình."
sudo mysql_secure_installation

# Cài đặt PHP và các module cần thiết
echo "Cài đặt PHP và các module cần thiết..."
sudo dnf install -y php php-mysqlnd php-gd php-imap php-ldap php-odbc php-pear php-xml php-xmlrpc php-mbstring php-snmp php-soap php-tidy php-intl php-zip
if [ $? -ne 0 ]; then
    echo "Lỗi: Không thể cài đặt PHP hoặc các module cần thiết."
    exit 1
fi
sudo systemctl restart httpd
echo "PHP đã được cài đặt và Apache đã được khởi động lại."

# Tạo cơ sở dữ liệu và người dùng cho Roundcube
echo "Tạo cơ sở dữ liệu và người dùng cho Roundcube..."
DB_NAME="roundcubemail"
DB_USER="roundcubeuser"
DB_PASS="roundcubepass"
MYSQL_ROOT_PASSWORD="your_root_password"  # Thay bằng mật khẩu root của MySQL

mysql -u root -p$MYSQL_ROOT_PASSWORD -e "CREATE DATABASE $DB_NAME;" 2>/dev/null
if [ $? -ne 0 ]; then
    echo "Lỗi: Không thể tạo cơ sở dữ liệu. Kiểm tra mật khẩu root hoặc MariaDB có chạy không."
    exit 1
fi
mysql -u root -p$MYSQL_ROOT_PASSWORD -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';" 2>/dev/null
mysql -u root -p$MYSQL_ROOT_PASSWORD -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';" 2>/dev/null
mysql -u root -p$MYSQL_ROOT_PASSWORD -e "FLUSH PRIVILEGES;" 2>/dev/null
echo "Cơ sở dữ liệu và người dùng đã được tạo thành công."

# Tải xuống Roundcube
echo "Tải xuống Roundcube..."
cd /var/www/html
sudo wget https://github.com/roundcube/roundcubemail/releases/download/1.5.0/roundcubemail-1.5.0-complete.tar.gz
if [ $? -ne 0 ]; then
    echo "Lỗi: Không thể tải xuống Roundcube."
    exit 1
fi
sudo tar -xvf roundcubemail-1.5.0-complete.tar.gz
sudo mv roundcubemail-1.5.0 roundcube
echo "Roundcube đã được tải xuống và giải nén."

# Cấu hình Roundcube
echo "Cấu hình Roundcube..."
cd roundcube
sudo cp config/config.inc.php.sample config/config.inc.php
sudo sed -i "s/\$config\['db_dsnw'\] = '.*';/\$config\['db_dsnw'\] = 'mysql:\/\/$DB_USER:$DB_PASS@localhost\/$DB_NAME';/" config/config.inc.php
sudo sed -i "s/\$config\['default_host'\] = '.*';/\$config\['default_host'\] = 'rocketsmtp.site';/" config/config.inc.php
sudo sed -i "s/\$config\['smtp_server'\] = '.*';/\$config\['smtp_server'\] = 'rocketsmtp.site';/" config/config.inc.php
sudo sed -i "s/\$config\['smtp_user'\] = '.*';/\$config\['smtp_user'\] = '%u';/" config/config.inc.php
sudo sed -i "s/\$config\['smtp_pass'\] = '.*';/\$config\['smtp_pass'\] = '%p';/" config/config.inc.php
echo "Roundcube đã được cấu hình."

# Thiết lập quyền sở hữu và quyền truy cập
echo "Thiết lập quyền sở hữu và quyền truy cập..."
sudo chown -R apache:apache /var/www/html/roundcube
sudo chmod -R 755 /var/www/html/roundcube

# Khởi tạo cơ sở dữ liệu Roundcube
echo "Khởi tạo cơ sở dữ liệu Roundcube..."
mysql -u $DB_USER -p$DB_PASS $DB_NAME < /var/www/html/roundcube/SQL/mysql.initial.sql
if [ $? -ne 0 ]; then
    echo "Lỗi: Không thể khởi tạo cơ sở dữ liệu Roundcube."
    exit 1
fi
echo "Cơ sở dữ liệu Roundcube đã được khởi tạo."

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
if [ $? -ne 0 ]; then
    echo "Lỗi: Không thể khởi động lại Apache."
    exit 1
fi
echo "Apache đã được cấu hình và khởi động lại."

# Tạo người dùng email
echo "Tạo người dùng email mailuser..."
sudo useradd mailuser
echo "pss123" | sudo passwd --stdin mailuser
if [ $? -ne 0 ]; then
    echo "Lỗi: Không thể tạo người dùng mailuser."
    exit 1
fi
echo "Người dùng mailuser đã được tạo với mật khẩu pss123."

# Hoàn tất cài đặt
echo "Cài đặt Roundcube hoàn tất!"
echo "Bạn có thể truy cập Roundcube tại: http://103.176.20.154/roundcube"
echo "Đăng nhập với: mailuser / pss123"
echo "Lưu ý: Đảm bảo máy chủ email đã được cấu hình đúng và firewall cho phép truy cập port 80."
