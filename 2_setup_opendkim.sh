#!/bin/bash

# Script cài đặt và cấu hình OpenDKIM
# Chạy với quyền root: sudo bash setup_opendkim.sh

# Biến cấu hình
DOMAIN="rocketsmtp.site"

# Kiểm tra quyền root
if [ "$(id -u)" != "0" ]; then
   echo "Script này cần chạy với quyền root. Sử dụng sudo hoặc đăng nhập root."
   exit 1
fi

echo "Bắt đầu cài đặt và cấu hình OpenDKIM..."

# Cấu hình DNS
echo "Cấu hình DNS..."
echo "nameserver 1.1.1.1" > /etc/resolv.conf
echo "nameserver 1.0.0.1" >> /etc/resolv.conf

# Bước 1: Kích hoạt kho CRB
echo "Kích hoạt kho CRB để cài đặt các thư viện phụ thuộc cho OpenDKIM..."
dnf config-manager --set-enabled crb || { echo "Lỗi: Không thể kích hoạt kho CRB."; exit 1; }

# Bước 2: Cài đặt các thư viện phụ thuộc
echo "Cài đặt các thư viện phụ thuộc cho OpenDKIM..."
dnf install -y sendmail-milter libmemcached-awesome || { echo "Lỗi: Không thể cài đặt thư viện phụ thuộc."; exit 1; }

# Bước 3: Cài đặt OpenDKIM
echo "Cài đặt OpenDKIM..."
dnf install -y opendkim opendkim-tools || { echo "Lỗi: Không thể cài đặt OpenDKIM."; exit 1; }

# Bước 4: Tạo thư mục và key DKIM
echo "Tạo thư mục và key DKIM..."
mkdir -p /etc/opendkim/keys
opendkim-genkey -s mail -d $DOMAIN
mv mail.private /etc/opendkim/keys/mail
mv mail.txt /etc/opendkim/keys/mail.txt
chown opendkim:opendkim /etc/opendkim/keys/mail
chmod 600 /etc/opendkim/keys/mail

# Bước 5: Cấu hình OpenDKIM
echo "Cấu hình OpenDKIM..."
cat > /etc/opendkim.conf << EOF
Mode                    sv
Syslog                  yes
SyslogSuccess           yes
LogWhy                  yes
Canonicalization        relaxed/relaxed
Domain                  $DOMAIN
Selector                mail
KeyFile                 /etc/opendkim/keys/mail
Socket                  inet:8891@localhost
EOF

echo "*@$DOMAIN mail._domainkey.$DOMAIN" > /etc/opendkim/SigningTable
echo "mail._domainkey.$DOMAIN $DOMAIN:mail:/etc/opendkim/keys/mail" > /etc/opendkim/KeyTable
echo -e "127.0.0.1\nlocalhost\n$DOMAIN" > /etc/opendkim/TrustedHosts

# Bước 6: Hướng dẫn thêm bản ghi DNS
echo "Vui lòng thêm các bản ghi DNS sau:"
echo "1. SPF: Name: $DOMAIN, Type: TXT, Value: v=spf1 a mx ip4:YOUR_SERVER_IP -all"
echo "   (Thay YOUR_SERVER_IP bằng địa chỉ IP của máy chủ, ví dụ: $(curl -s ifconfig.me))"
echo "2. DKIM: Name: mail._domainkey.$DOMAIN, Type: TXT, Value: (xem nội dung file /etc/opendkim/keys/mail.txt)"
echo "   Nội dung file mail.txt:"
cat /etc/opendkim/keys/mail.txt
echo "3. DMARC: Name: _dmarc.$DOMAIN, Type: TXT, Value: v=DMARC1; p=none; rua=mailto:dmarc-reports@$DOMAIN;"
echo "Nhấn Enter để tiếp tục sau khi đã thêm bản ghi DNS..."
read

# Bước 7: Hoàn tất
echo "Cài đặt và cấu hình OpenDKIM hoàn tất!"
echo "OpenDKIM đã được cài đặt và cấu hình."
echo "Các bản ghi DNS đã được hướng dẫn. Đảm bảo bạn đã thêm chúng trước khi tiếp tục."
echo "Bạn có thể tiếp tục với bước tiếp theo (cài đặt Postfix)."