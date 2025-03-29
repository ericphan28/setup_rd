#!/bin/bash

# Script cài đặt và cấu hình Postfix với OpenDKIM
# Chạy với quyền root: sudo bash setup_postfix.sh

# Biến cấu hình
DOMAIN="rocketsmtp.site"
HOSTNAME="mail.rocketsmtp.site"

# Kiểm tra quyền root
if [ "$(id -u)" != "0" ]; then
   echo "Script này cần chạy với quyền root. Sử dụng sudo hoặc đăng nhập root."
   exit 1
fi

echo "Cập nhật hệ thống..."
dnf update -y

echo "Bắt đầu cài đặt và cấu hình Postfix..."

# Bước 1: Cài đặt Postfix và OpenDKIM nếu chưa có
echo "Cài đặt Postfix và OpenDKIM..."
dnf install -y postfix opendkim || { echo "Lỗi: Không thể cài đặt Postfix hoặc OpenDKIM."; exit 1; }

# Bước 2: Cấu hình Postfix
echo "Cấu hình Postfix..."
cat > /etc/postfix/main.cf << EOF
myhostname = $HOSTNAME
mydomain = $DOMAIN
myorigin = \$mydomain
mydestination = \$myhostname, localhost.\$mydomain, localhost, \$mydomain
inet_interfaces = all
inet_protocols = all
home_mailbox = /var/mail/%u/
smtpd_sasl_type = dovecot
smtpd_sasl_path = private/auth
smtpd_sasl_auth_enable = yes
smtpd_sasl_security_options = noanonymous
smtpd_sasl_local_domain = \$myhostname
smtpd_recipient_restrictions = permit_sasl_authenticated, permit_mynetworks, reject_unauth_destination
smtpd_tls_cert_file = /etc/pki/tls/certs/postfix.pem
smtpd_tls_key_file = /etc/pki/tls/private/postfix.key
smtpd_use_tls = yes
smtp_tls_security_level = may
milter_default_action = accept
milter_protocol = 2
smtpd_milters = inet:localhost:8891
non_smtpd_milters = inet:localhost:8891
EOF

# Bước 3: Đảm bảo thư mục mailbox tồn tại
echo "Tạo thư mục mailbox..."
mkdir -p /var/mail
chmod 700 /var/mail

# Bước 4: Tạo chứng chỉ tự ký cho Postfix
echo "Tạo chứng chỉ tự ký cho Postfix..."
mkdir -p /etc/pki/tls/certs /etc/pki/tls/private
openssl req -x509 -newkey rsa:2048 -keyout /etc/pki/tls/private/postfix.key -out /etc/pki/tls/certs/postfix.pem -days 365 -nodes -subj "/C=US/ST=State/L=City/O=Organization/OU=Unit/CN=$HOSTNAME"
chmod 600 /etc/pki/tls/private/postfix.key

# Bước 5: Cấu hình firewall (mở cổng SMTP)
echo "Cấu hình firewall..."
firewall-cmd --add-service=smtp --permanent
firewall-cmd --add-service=smtps --permanent
firewall-cmd --add-service=submission --permanent
firewall-cmd --reload

# Bước 6: Khởi động và kích hoạt Postfix & OpenDKIM
echo "Khởi động và kích hoạt Postfix & OpenDKIM..."
systemctl enable --now postfix
systemctl enable --now opendkim

# Bước 7: Kiểm tra trạng thái dịch vụ
echo "Kiểm tra trạng thái dịch vụ..."
systemctl status postfix --no-pager
systemctl status opendkim --no-pager

# Bước 8: Kiểm tra cấu hình Postfix
echo "Kiểm tra cấu hình Postfix..."
postfix check
if [ $? -ne 0 ]; then
    echo "Lỗi: Cấu hình Postfix có vấn đề. Kiểm tra lại file /etc/postfix/main.cf."
    exit 1
fi

# Bước 9: Khởi động lại Postfix để áp dụng thay đổi
echo "Khởi động lại Postfix..."
systemctl restart postfix

# Bước 10: Hoàn tất
echo "Cài đặt và cấu hình Postfix hoàn tất!"
echo "Postfix đã được cài đặt và cấu hình."
echo "OpenDKIM đã được khởi động và tích hợp với Postfix."
echo "Bạn có thể tiếp tục với bước tiếp theo (cài đặt Dovecot)."
