#!/bin/bash

# Script cài đặt và cấu hình mail server toàn diện (Postfix + Dovecot + Let's Encrypt)
# Chạy với quyền root: sudo bash setup_mail_server.sh

# Biến cấu hình
MAIL_USER="mailuser"
DOMAIN="rocketsmtp.site"
HOSTNAME="mail.$DOMAIN"
MAIL_DIR="/home/$MAIL_USER/Maildir"

# Hàm hiển thị lỗi mà không thoát
show_error() {
    echo "LỖI: $1"
    echo "Tiếp tục chạy script để debug. Kiểm tra log chi tiết nếu cần."
}

# Kiểm tra quyền root
if [ "$(id -u)" != "0" ]; then
    show_error "Script này cần chạy với quyền root. Sử dụng sudo hoặc đăng nhập root."
    exit 1
fi

echo "Bắt đầu cài đặt và cấu hình mail server..."

# Kiểm tra môi trường
echo "Kiểm tra môi trường..."
if ! command -v dnf >/dev/null 2>&1; then
    show_error "Không tìm thấy dnf. Hệ thống phải dùng CentOS/RHEL với dnf."
fi

# Cài đặt EPEL repository
echo "Cài đặt EPEL repository cho certbot..."
dnf install -y epel-release || show_error "Không thể cài đặt EPEL repository."

# Cập nhật hệ thống
#echo "Cập nhật hệ thống..."
dnf update -y || show_error "Không thể cập nhật hệ thống."

# Cài đặt các gói cần thiết
echo "Cài đặt Postfix, Dovecot, s-nail, dovecot-pigeonhole, certbot..."
dnf install -y postfix dovecot s-nail dovecot-pigeonhole certbot || show_error "Không thể cài đặt các gói cần thiết."

# Kiểm tra gói đã cài chưa
for pkg in postfix dovecot s-nail dovecot-pigeonhole certbot; do
    if ! rpm -q "$pkg" >/dev/null 2>&1; then
        show_error "Gói $pkg chưa được cài đặt."
    else
        echo " - Gói $pkg đã được cài đặt."
    fi
done

# Tạo user mail
echo "Tạo user $MAIL_USER nếu chưa tồn tại..."
if ! id "$MAIL_USER" >/dev/null 2>&1; then
    useradd -m -s /sbin/nologin "$MAIL_USER" || show_error "Không thể tạo user $MAIL_USER."
fi

# Tạo thư mục Maildir
echo "Tạo thư mục Maildir cho $MAIL_USER..."
if [ ! -d "$MAIL_DIR" ]; then
    mkdir -p "$MAIL_DIR"/{new,cur,tmp} || show_error "Không thể tạo thư mục Maildir."
    chown -R "$MAIL_USER:$MAIL_USER" "$MAIL_DIR" || show_error "Không thể chown thư mục Maildir."
    chmod -R 700 "$MAIL_DIR" || show_error "Không thể chmod thư mục Maildir."
else
    echo "Thư mục Maildir đã tồn tại, bỏ qua."
fi

# Cấu hình Postfix
if [ -d "/etc/postfix" ]; then
    echo "Cấu hình Postfix..."
    cat <<EOF > /etc/postfix/main.cf
myhostname = $HOSTNAME
mydomain = $DOMAIN
myorigin = \$mydomain
inet_interfaces = all
inet_protocols = all
mydestination = \$myhostname, localhost.\$mydomain, localhost, \$mydomain
home_mailbox = Maildir/
smtpd_banner = \$myhostname ESMTP
smtpd_tls_cert_file = /etc/letsencrypt/live/$DOMAIN/fullchain.pem
smtpd_tls_key_file = /etc/letsencrypt/live/$DOMAIN/privkey.pem
smtpd_use_tls = yes
smtp_tls_security_level = may
smtpd_tls_security_level = may
smtpd_sasl_auth_enable = yes
smtpd_sasl_type = dovecot
smtpd_sasl_path = private/auth
smtpd_sasl_security_options = noanonymous
smtpd_recipient_restrictions = permit_sasl_authenticated, permit_mydestination, reject_unauth_destination
mailbox_transport = lmtp:unix:/var/spool/postfix/private/dovecot-lmtp
EOF

    echo "Cấu hình port 587 trong Postfix..."
    cat <<EOF > /etc/postfix/master.cf
submission inet n       -       y       -       -       smtpd
  -o syslog_name=postfix/submission
  -o smtpd_tls_security_level=encrypt
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_reject_unlisted_recipient=no
  -o smtpd_recipient_restrictions=permit_sasl_authenticated,reject
EOF

    echo "Kiểm tra cấu hình Postfix..."
    postconf -n > /dev/null 2>&1 || show_error "Cấu hình Postfix không hợp lệ. Kiểm tra /etc/postfix/main.cf."
else
    show_error "Thư mục /etc/postfix không tồn tại. Postfix chưa được cài đặt."
fi

# Cấu hình Dovecot
if [ -d "/etc/dovecot" ]; then
    echo "Cấu hình Dovecot..."
    cat <<EOF > /etc/dovecot/dovecot.conf
protocols = imap lmtp
listen = *, ::
EOF

    cat <<EOF > /etc/dovecot/conf.d/10-auth.conf
auth_mechanisms = plain login
auth_username_format = %n
!include auth-system.conf.ext
EOF

    cat <<EOF > /etc/dovecot/conf.d/10-mail.conf
mail_location = maildir:/home/%u/Maildir
mail_access_groups = mail
EOF

    cat <<EOF > /etc/dovecot/conf.d/10-ssl.conf
ssl = required
ssl_cert = </etc/letsencrypt/live/$DOMAIN/fullchain.pem
ssl_key = </etc/letsencrypt/live/$DOMAIN/privkey.pem
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

    echo "Cấu hình logging chi tiết cho Dovecot..."
    cat <<EOF > /etc/dovecot/conf.d/10-logging.conf
log_path = /var/log/dovecot.log
info_log_path = /var/log/dovecot-info.log
debug_log_path = /var/log/dovecot-debug.log
mail_debug = yes
EOF
    touch /var/log/dovecot{,-info,-debug}.log
    chown dovecot:dovecot /var/log/dovecot*.log || show_error "Không thể chown file log Dovecot."
    chmod 660 /var/log/dovecot*.log || show_error "Không thể chmod file log Dovecot."
else
    show_error "Thư mục /etc/dovecot không tồn tại. Dovecot chưa được cài đặt."
fi

# Cấu hình logging cho Postfix
if [ -f "/etc/postfix/main.cf" ]; then
    echo "Cấu hình logging chi tiết cho Postfix..."
    sed -i 's/#syslog_facility = mail/syslog_facility = mail/' /etc/postfix/main.cf
    sed -i 's/#debug_peer_level = 2/debug_peer_level = 2/' /etc/postfix/main.cf
fi

# Cài đặt Let's Encrypt
echo "Cài đặt chứng chỉ Let's Encrypt..."
if command -v certbot >/dev/null 2>&1; then
    certbot certonly --standalone -d "$DOMAIN" --non-interactive --agree-tos --email "admin@$DOMAIN" || show_error "Không thể tạo chứng chỉ Let's Encrypt. Kiểm tra DNS của $DOMAIN."
else
    show_error "Certbot không được cài đặt."
fi

# Kiểm tra chứng chỉ
if [ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ] || [ ! -f "/etc/letsencrypt/live/$DOMAIN/privkey.pem" ]; then
    show_error "Chứng chỉ Let's Encrypt không tồn tại. Dùng SSL tự ký tạm thời."
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/pki/tls/private/mail.key -out /etc/pki/tls/certs/mail.crt -subj "/CN=$DOMAIN" || show_error "Không thể tạo SSL tự ký."
    if [ -f "/etc/postfix/main.cf" ]; then
        sed -i "s|smtpd_tls_cert_file = .*|smtpd_tls_cert_file = /etc/pki/tls/certs/mail.crt|" /etc/postfix/main.cf
        sed -i "s|smtpd_tls_key_file = .*|smtpd_tls_key_file = /etc/pki/tls/private/mail.key|" /etc/postfix/main.cf
    fi
    if [ -f "/etc/dovecot/conf.d/10-ssl.conf" ]; then
        sed -i "s|ssl_cert = .*|ssl_cert = </etc/pki/tls/certs/mail.crt|" /etc/dovecot/conf.d/10-ssl.conf
        sed -i "s|ssl_key = .*|ssl_key = </etc/pki/tls/private/mail.key|" /etc/dovecot/conf.d/10-ssl.conf
    fi
fi

# Khởi động dịch vụ
echo "Khởi động Postfix và Dovecot..."
systemctl enable postfix dovecot 2>/dev/null || show_error "Không thể enable Postfix hoặc Dovecot."
systemctl restart postfix dovecot 2>/dev/null || show_error "Không thể restart Postfix hoặc Dovecot."

# Kiểm tra trạng thái dịch vụ
echo "Kiểm tra trạng thái Postfix..."
if systemctl is-active postfix >/dev/null 2>&1; then
    echo " - Postfix đang chạy."
else
    show_error "Postfix không chạy. Xem log: journalctl -u postfix"
fi

echo "Kiểm tra trạng thái Dovecot..."
if systemctl is-active dovecot >/dev/null 2>&1; then
    echo " - Dovecot đang chạy."
else
    show_error "Dovecot không chạy. Xem log: journalctl -u dovecot"
fi

# Mở port trên firewall
echo "Mở các port cần thiết trên firewall..."
firewall-cmd --permanent --add-port={25,587,143,993}/tcp || show_error "Không thể mở port trên firewall."
firewall-cmd --reload || show_error "Không thể reload firewall."

# Test gửi email
echo "Test gửi email..."
if command -v s-nail >/dev/null 2>&1; then
    echo "Test email from $HOSTNAME" | s-nail -s "Test Mail Server" -r "$MAIL_USER@$DOMAIN" "$MAIL_USER@$DOMAIN"
    if [ $? -eq 0 ]; then
        echo " - Gửi email thành công."
        sleep 2
        if ls "$MAIL_DIR/new/"* >/dev/null 2>&1; then
            echo " - Email đã được lưu vào $MAIL_DIR/new/."
        else
            show_error "Email không được lưu vào Maildir. Kiểm tra log: journalctl -u dovecot"
        fi
    else
        show_error "Không gửi được email. Kiểm tra log: journalctl -u postfix"
    fi
else
    show_error "s-nail không được cài đặt."
fi

# Hoàn tất
echo "Hoàn tất cài đặt mail server!"
echo "Kiểm tra thư mục $MAIL_DIR/new/ để xem email test."
echo "Log Postfix: /var/log/maillog"
echo "Log Dovecot: /var/log/dovecot.log, /var/log/dovecot-info.log, /var/log/dovecot-debug.log"
echo "Nếu có lỗi, chạy 'journalctl -u postfix' hoặc 'journalctl -u dovecot' để xem chi tiết."
