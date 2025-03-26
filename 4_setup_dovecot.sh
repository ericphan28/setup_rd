#!/bin/bash

# Script cài đặt và cấu hình Dovecot
# Chạy với quyền root: sudo bash setup_dovecot.sh

# Biến cấu hình
DOMAIN="rocketsmtp.site"
HOSTNAME="mail.rocketsmtp.site"

# Kiểm tra quyền root
if [ "$(id -u)" != "0" ]; then
   echo "Script này cần chạy với quyền root. Sử dụng sudo hoặc đăng nhập root."
   exit 1
fi

echo "Bắt đầu cài đặt và cấu hình Dovecot..."

# Bước 1: Cài đặt Dovecot
echo "Cài đặt Dovecot..."
dnf install -y dovecot || { echo "Lỗi: Không thể cài đặt Dovecot."; exit 1; }

# Bước 2: Cấu hình Dovecot
echo "Cấu hình Dovecot..."

# Cấu hình chính
cat > /etc/dovecot/dovecot.conf << EOF
protocols = imap pop3
listen = *
EOF

# Cấu hình xác thực (đảm bảo passdb được include)
cat > /etc/dovecot/conf.d/10-auth.conf << EOF
disable_plaintext_auth = no
auth_mechanisms = plain login
!include auth-system.conf.ext
EOF

# Đảm bảo passdb trong auth-system.conf.ext
echo "Đảm bảo passdb được cấu hình..."
cat > /etc/dovecot/conf.d/auth-system.conf.ext << EOF
passdb {
  driver = pam
  args = dovecot
}
userdb {
  driver = passwd
}
EOF

# Cấu hình mailbox
cat > /etc/dovecot/conf.d/10-mail.conf << EOF
mail_location = maildir:/var/mail/$DOMAIN/%n
EOF

# Cấu hình SSL
cat > /etc/dovecot/conf.d/10-ssl.conf << EOF
ssl = yes
ssl_cert = </etc/pki/dovecot/certs/dovecot.pem
ssl_key = </etc/pki/dovecot/private/dovecot.key
EOF

# Cấu hình SASL cho Postfix
cat > /etc/dovecot/conf.d/10-master.conf << EOF
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

# Bước 3: Tạo chứng chỉ tự ký cho Dovecot
echo "Tạo chứng chỉ tự ký cho Dovecot..."
mkdir -p /etc/pki/dovecot/certs /etc/pki/dovecot/private
openssl req -x509 -newkey rsa:2048 -keyout /etc/pki/dovecot/private/dovecot.key -out /etc/pki/dovecot/certs/dovecot.pem -days 365 -nodes -subj "/C=US/ST=State/L=City/O=Organization/OU=Unit/CN=$HOSTNAME"
chmod 600 /etc/pki/dovecot/private/dovecot.key

# Bước 4: Đảm bảo quyền thư mục SASL
echo "Đảm bảo quyền thư mục SASL cho Postfix..."
mkdir -p /var/spool/postfix/private
chown postfix:postfix /var/spool/postfix/private
chmod 750 /var/spool/postfix/private

# Bước 5: Khởi động Dovecot
echo "Khởi động Dovecot..."
systemctl stop dovecot  # Dừng để đảm bảo áp dụng cấu hình mới
systemctl start dovecot
systemctl enable dovecot

# Bước 6: Kiểm tra trạng thái dịch vụ
echo "Kiểm tra trạng thái dịch vụ..."
systemctl status dovecot
if systemctl is-active dovecot >/dev/null; then
    echo "Dovecot đang chạy."
else
    echo "Lỗi: Dovecot không chạy. Kiểm tra log /var/log/maillog."
    exit 1
fi

# Bước 7: Kiểm tra socket SASL
echo "Kiểm tra socket SASL..."
sleep 2  # Đợi 2 giây để socket được tạo
if [ -S /var/spool/postfix/private/auth ]; then
    echo "Socket SASL đã được tạo thành công."
else
    echo "Lỗi: Socket SASL không tồn tại. Kiểm tra log /var/log/maillog và cấu hình /etc/dovecot/conf.d/10-master.conf."
    exit 1
fi

# Bước 8: Hoàn tất
echo "Cài đặt và cấu hình Dovecot hoàn tất!"
echo "Dovecot đã được cài đặt và cấu hình."
echo "Bạn có thể tiếp tục với bước tiếp theo (cài đặt Roundcube)."