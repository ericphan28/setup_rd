#!/bin/bash
# Script cài đặt Postfix + OpenDKIM với tối ưu hóa

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

# Kiểm tra và cài đặt Postfix & OpenDKIM nếu chưa có
if ! rpm -q postfix > /dev/null; then
    dnf install -y postfix || { echo "Lỗi: Không thể cài đặt Postfix."; exit 1; }
fi

if ! rpm -q opendkim > /dev/null; then
    dnf install -y opendkim || { echo "Lỗi: Không thể cài đặt OpenDKIM."; exit 1; }
fi

# Cấu hình Postfix
postconf -e "myhostname = $HOSTNAME"
postconf -e "mydomain = $DOMAIN"
postconf -e "myorigin = \$mydomain"
postconf -e "mydestination = \$myhostname, localhost.\$mydomain, localhost, \$mydomain"
postconf -e "inet_interfaces = all"
postconf -e "inet_protocols = all"
postconf -e "home_mailbox = /var/mail/%u/"
postconf -e "smtpd_sasl_type = dovecot"
postconf -e "smtpd_sasl_path = private/auth"
postconf -e "smtpd_sasl_auth_enable = yes"
postconf -e "smtpd_sasl_security_options = noanonymous"
postconf -e "smtpd_tls_cert_file = /etc/pki/tls/certs/postfix.pem"
postconf -e "smtpd_tls_key_file = /etc/pki/tls/private/postfix.key"
postconf -e "smtpd_use_tls = yes"
postconf -e "milter_default_action = accept"
postconf -e "milter_protocol = 2"
postconf -e "smtpd_milters = inet:localhost:8891"
postconf -e "non_smtpd_milters = inet:localhost:8891"

# Đảm bảo thư mục mailbox tồn tại
mkdir -p /var/mail
chmod 700 /var/mail

# Tạo chứng chỉ tự ký nếu chưa có
CERT_FILE="/etc/pki/tls/certs/postfix.pem"
KEY_FILE="/etc/pki/tls/private/postfix.key"
if [ ! -f "$CERT_FILE" ] || [ ! -f "$KEY_FILE" ]; then
    echo "Tạo chứng chỉ tự ký cho Postfix..."
    mkdir -p /etc/pki/tls/certs /etc/pki/tls/private
    openssl req -x509 -newkey rsa:2048 -keyout "$KEY_FILE" -out "$CERT_FILE" -days 365 -nodes -subj "/C=US/ST=State/L=City/O=Organization/OU=Unit/CN=$HOSTNAME"
    chmod 600 "$KEY_FILE"
fi

# Cấu hình firewall
echo "Cấu hình firewall..."
firewall-cmd --permanent --add-service=smtp
firewall-cmd --permanent --add-port=587/tcp  # Sửa lỗi submission
firewall-cmd --permanent --add-service=smtps
firewall-cmd --reload

# Khởi động và kích hoạt Postfix & OpenDKIM
systemctl enable --now postfix
systemctl enable --now opendkim

# Kiểm tra trạng thái dịch vụ
systemctl status postfix --no-pager
systemctl status opendkim --no-pager

echo "Cài đặt và cấu hình hoàn tất!"
