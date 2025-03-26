#!/bin/bash

# Script cài đặt và cấu hình Postfix
# Chạy với quyền root: sudo bash setup_postfix.sh

# Biến cấu hình
DOMAIN="rocketsmtp.site"
HOSTNAME="mail.rocketsmtp.site"

# Kiểm tra quyền root
if [ "$(id -u)" != "0" ]; then
   echo "Script này cần chạy với quyền root. Sử dụng sudo hoặc đăng nhập root."
   exit 1
fi

echo "Bắt đầu cài đặt và cấu hình Postfix..."

# Bước 1: Cài đặt Postfix
echo "Cài đặt Postfix..."
dnf install -y postfix || { echo "Lỗi: Không thể cài đặt Postfix."; exit 1; }

# Bước 2: Cấu hình Postfix
echo "Cấu hình Postfix..."
cat > /etc/postfix/main.cf << EOF
myhostname = $HOSTNAME
mydomain = $DOMAIN
myorigin = \$mydomain
mydestination = \$myhostname, localhost.\$mydomain, localhost, \$mydomain
inet_interfaces = all
inet_protocols = all
home_mailbox = /var/mail/$DOMAIN/%n/
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

# Bước 3: Tạo chứng chỉ tự ký cho Postfix
echo "Tạo chứng chỉ tự ký cho Postfix..."
mkdir -p /etc/pki/tls/certs /etc/pki/tls/private
openssl req -x509 -newkey rsa:2048 -keyout /etc/pki/tls/private/postfix.key -out /etc/pki/tls/certs/postfix.pem -days 365 -nodes -subj "/C=US/ST=State/L=City/O=Organization/OU=Unit/CN=$HOSTNAME"
chmod 600 /etc/pki/tls/private/postfix.key

# Bước 4: Khởi động Postfix và OpenDKIM
echo "Khởi động Postfix và OpenDKIM..."
systemctl start postfix
systemctl enable postfix
systemctl start opendkim
systemctl enable opendkim

# Bước 5: Kiểm tra trạng thái dịch vụ
echo "Kiểm tra trạng thái dịch vụ..."
systemctl status postfix
systemctl status opendkim

# Bước 6: Hoàn tất
echo "Cài đặt và cấu hình Postfix hoàn tất!"
echo "Postfix đã được cài đặt và cấu hình."
echo "OpenDKIM đã được khởi động và tích hợp với Postfix."
echo "Bạn có thể tiếp tục với bước tiếp theo (cài đặt Dovecot)."