#!/bin/bash

# Script cài đặt và cấu hình hoàn chỉnh mail server (Postfix, Dovecot, SSL, sửa lỗi)
# Chạy với quyền root: sudo bash setup_complete_mail_server.sh

# Biến cấu hình
DOMAIN="rocketsmtp.site"
MAIL_USER="mailuser"
MAIL_PASSWORD="your_secure_password"  # Thay bằng mật khẩu thực tế
HOSTNAME="mail.$DOMAIN"
IP_ADDRESS=$(ip addr show | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | cut -d/ -f1 | head -n 1)

# Kiểm tra quyền root
if [ "$(id -u)" != "0" ]; then
    echo "Script này cần chạy với quyền root. Sử dụng sudo hoặc đăng nhập root."
    exit 1
fi

echo "Bắt đầu cài đặt và cấu hình mail server..."

# Cập nhật hệ thống
echo "Cập nhật hệ thống..."
dnf update -y

# Cài đặt các gói cần thiết
echo "Cài đặt Postfix, Dovecot, OpenSSL, s-nail, dovecot-pigeonhole..."
dnf install -y postfix dovecot openssl s-nail dovecot-pigeonhole || { echo "Lỗi: Không thể cài đặt gói."; exit 1; }

# Tạo user mail
echo "Tạo user $MAIL_USER..."
if ! id $MAIL_USER >/dev/null 2>&1; then
    useradd -m -s /sbin/nologin $MAIL_USER
    echo "$MAIL_USER:$MAIL_PASSWORD" | chpasswd
fi

# Tạo thư mục Maildir
echo "Tạo thư mục Maildir cho $MAIL_USER..."
mkdir -p /home/$MAIL_USER/Maildir/{new,cur,tmp}
chown -R $MAIL_USER:$MAIL_USER /home/$MAIL_USER/Maildir
chmod -R 700 /home/$MAIL_USER/Maildir

# Tạo chứng chỉ SSL
echo "Tạo chứng chỉ SSL tự ký..."
if [ ! -f /etc/pki/tls/certs/$DOMAIN.crt ]; then
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout /etc/pki/tls/private/$DOMAIN.key \
        -out /etc/pki/tls/certs/$DOMAIN.crt \
        -subj "/C=VN/ST=Hanoi/L=Hanoi/O=YourOrg/OU=IT/CN=$HOSTNAME"
    chmod 600 /etc/pki/tls/private/$DOMAIN.key
fi

# Cấu hình Postfix
echo "Cấu hình Postfix..."
cat <<EOF > /etc/postfix/main.cf
myhostname = $HOSTNAME
mydomain = $DOMAIN
myorigin = \$mydomain
inet_interfaces = all
inet_protocols = all
mydestination = \$myhostname, localhost.\$mydomain, localhost, \$mydomain
mynetworks = 127.0.0.0/8, $IP_ADDRESS/32
home_mailbox = Maildir/

# SMTP với SSL/TLS
smtpd_tls_cert_file = /etc/pki/tls/certs/$DOMAIN.crt
smtpd_tls_key_file = /etc/pki/tls/private/$DOMAIN.key
smtpd_tls_security_level = may
smtp_tls_security_level = may
smtpd_tls_loglevel = 1

# SASL
smtpd_sasl_auth_enable = yes
smtpd_sasl_type = dovecot
smtpd_sasl_path = private/auth
smtpd_sasl_security_options = noanonymous
smtpd_recipient_restrictions = permit_sasl_authenticated, permit_mynetworks, reject_unauth_destination

# LMTP
virtual_transport = lmtp:unix:/var/spool/postfix/private/dovecot-lmtp
EOF

cat <<EOF > /etc/postfix/master.cf
submission inet n       -       y       -       -       smtpd
  -o syslog_name=postfix/submission
  -o smtpd_tls_security_level=encrypt
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_recipient_restrictions=permit_sasl_authenticated,reject
EOF

# Cấu hình Dovecot
echo "Cấu hình Dovecot..."
cat <<EOF > /etc/dovecot/dovecot.conf
protocols = imap lmtp
listen = *, ::
EOF

cat <<EOF > /etc/dovecot/conf.d/10-auth.conf
disable_plaintext_auth = no
auth_mechanisms = plain login
auth_username_format = %n
!include auth-system.conf.ext
EOF

cat <<EOF > /etc/dovecot/conf.d/10-mail.conf
mail_location = maildir:/home/%u/Maildir
mail_access_groups = mail
EOF

cat <<EOF > /etc/dovecot/conf.d/10-ssl.conf
ssl = yes
ssl_cert = </etc/pki/tls/certs/$DOMAIN.crt
ssl_key = </etc/pki/tls/private/$DOMAIN.key
EOF

cat <<EOF > /etc/dovecot/conf.d/20-lmtp.conf
service lmtp {
  unix_listener /var/spool/postfix/private/dovecot-lmtp {
    mode = 0600
    user = postfix
    group = postfix
  }
}
protocol lmtp {
  mail_plugins = \$mail_plugins sieve
  postmaster_address = postmaster@$DOMAIN
}
EOF

cat <<EOF > /etc/dovecot/conf.d/10-master.conf
service imap-login {
  inet_listener imap {
    port = 143
  }
  inet_listener imaps {
    port = 993
  }
}
service lmtp {
  unix_listener /var/spool/postfix/private/dovecot-lmtp {
    mode = 0600
    user = postfix
    group = postfix
  }
}
service auth {
  unix_listener /var/spool/postfix/private/auth {
    mode = 0660
    user = postfix
    group = postfix
  }
  user = dovecot
}
service auth-worker {
  user = dovecot
}
EOF

# Mở port trên firewall
echo "Mở port 25, 587, 143, 993 trên firewall..."
firewall-cmd --permanent --add-port={25,587,143,993}/tcp
firewall-cmd --reload

# Khởi động và bật dịch vụ
echo "Khởi động và bật Postfix, Dovecot..."
systemctl enable postfix dovecot
systemctl restart postfix dovecot
if ! systemctl is-active postfix >/dev/null 2>&1 || ! systemctl is-active dovecot >/dev/null 2>&1; then
    echo "Lỗi: Postfix hoặc Dovecot không chạy. Kiểm tra log bằng 'journalctl -u postfix' hoặc 'journalctl -u dovecot'."
    exit 1
fi

# Test gửi email
echo "Test gửi email..."
echo "Test email from complete setup" | s-nail -s "Test Complete Setup" -r "$MAIL_USER@$DOMAIN" "$MAIL_USER@$DOMAIN"
if [ $? -eq 0 ]; then
    echo " - Gửi email thành công."
    sleep 2
    if ls /home/$MAIL_USER/Maildir/new/* >/dev/null 2>&1; then
        echo " - Email đã được lưu vào /home/$MAIL_USER/Maildir/new/."
    else
        echo " - Lỗi: Email không được lưu vào Maildir. Kiểm tra log Dovecot: 'journalctl -u dovecot'."
    fi
else
    echo " - Lỗi: Không gửi được email. Kiểm tra log Postfix: 'journalctl -u postfix'."
fi

# Hoàn tất
echo "Hoàn tất cài đặt mail server!"
echo "Kiểm tra /home/$MAIL_USER/Maildir/new/ để xem email test."
echo "Nếu có lỗi, cung cấp log từ 'journalctl -u postfix' hoặc 'journalctl -u dovecot'."
