#!/bin/bash

# Script hoàn tất cài đặt: Tạo user email và kích hoạt SSL
# Chạy với quyền root: sudo bash finalize_setup.sh

# Biến cấu hình
DOMAIN="rocketsmtp.site"
HOSTNAME="mail.rocketsmtp.site"
EMAIL_USER="user1"  # Tên user email (ví dụ: user1@rocketsmtp.site)
EMAIL_PASSWORD="securepassword123"  # Mật khẩu cho user email

# Kiểm tra quyền root
if [ "$(id -u)" != "0" ]; then
   echo "Script này cần chạy với quyền root. Sử dụng sudo hoặc đăng nhập root."
   exit 1
fi

echo "Bắt đầu hoàn tất cài đặt: Tạo user email và kích hoạt SSL..."

# Bước 1: Tạo user email
echo "Tạo user email: $EMAIL_USER@$DOMAIN..."
useradd -m -s /sbin/nologin $EMAIL_USER || { echo "Lỗi: Không thể tạo user $EMAIL_USER."; exit 1; }
echo "$EMAIL_USER:$EMAIL_PASSWORD" | chpasswd || { echo "Lỗi: Không thể đặt mật khẩu cho user $EMAIL_USER."; exit 1; }
mkdir -p /var/mail/$DOMAIN/$EMAIL_USER
chown -R $EMAIL_USER:mail /var/mail/$DOMAIN/$EMAIL_USER
chmod -R 700 /var/mail/$DOMAIN/$EMAIL_USER

# Bước 2: Cấu hình Dovecot (đã cấu hình trong setup_dovecot.sh)
echo "Đảm bảo cấu hình Dovecot đúng..."
sed -i 's|#!include auth-system.conf.ext|!include auth-system.conf.ext|' /etc/dovecot/conf.d/10-auth.conf
sed -i 's|auth_mechanisms =.*|auth_mechanisms = plain login|' /etc/dovecot/conf.d/10-auth.conf

# Bước 3: Cấu hình Postfix (đã cấu hình trong setup_postfix.sh)
echo "Cập nhật chứng chỉ TLS cho Postfix..."
sed -i "s|smtpd_tls_cert_file = .*|smtpd_tls_cert_file = /etc/letsencrypt/live/$HOSTNAME/fullchain.pem|" /etc/postfix/main.cf
sed -i "s|smtpd_tls_key_file = .*|smtpd_tls_key_file = /etc/letsencrypt/live/$HOSTNAME/privkey.pem|" /etc/postfix/main.cf

# Kích hoạt cổng 587 trong master.cf
sed -i 's|^#submission inet n|submission inet n|' /etc/postfix/master.cf
sed -i 's|^#  -o syslog_name=postfix/submission|  -o syslog_name=postfix/submission|' /etc/postfix/master.cf
sed -i 's|^#  -o smtpd_tls_security_level=encrypt|  -o smtpd_tls_security_level=encrypt|' /etc/postfix/master.cf
sed -i 's|^#  -o smtpd_sasl_auth_enable=yes|  -o smtpd_sasl_auth_enable=yes|' /etc/postfix/master.cf
sed -i 's|^#  -o smtpd_tls_auth_only=yes|  -o smtpd_tls_auth_only=yes|' /etc/postfix/master.cf

# Bước 4: Cài đặt certbot để kích hoạt SSL
echo "Cài đặt certbot để kích hoạt SSL..."
dnf install -y certbot python3-certbot-apache || { echo "Lỗi: Không thể cài đặt certbot."; exit 1; }

# Bước 5: Tạo chứng chỉ SSL với certbot
echo "Tạo chứng chỉ SSL cho $HOSTNAME..."
certbot --apache -d $HOSTNAME --non-interactive --agree-tos --email admin@$DOMAIN || { echo "Lỗi: Không thể tạo chứng chỉ SSL."; exit 1; }

# Bước 6: Cập nhật cấu hình Apache để sử dụng SSL
echo "Cập nhật cấu hình Apache để sử dụng SSL..."
sed -i "s|ServerName.*|ServerName $HOSTNAME|" /etc/httpd/conf.d/roundcube.conf

# Bước 7: Khởi động lại các dịch vụ
echo "Khởi động lại các dịch vụ..."
systemctl restart dovecot
systemctl restart postfix
systemctl restart httpd

# Bước 8: Kiểm tra trạng thái dịch vụ
echo "Kiểm tra trạng thái dịch vụ..."
systemctl status dovecot
systemctl status postfix
systemctl status httpd

# Bước 9: Hoàn tất
echo "Hoàn tất cài đặt!"
echo "User email đã được tạo: $EMAIL_USER@$DOMAIN"
echo "Mật khẩu: $EMAIL_PASSWORD"
echo "Bạn có thể đăng nhập Roundcube tại: https://$HOSTNAME"
echo "Dùng tài khoản: $EMAIL_USER@$DOMAIN và mật khẩu: $EMAIL_PASSWORD"