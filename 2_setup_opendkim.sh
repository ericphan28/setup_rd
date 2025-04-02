#!/bin/bash

# Script cài đặt và kiểm tra DKIM cho email trên AlmaLinux 9.3
# Tác giả: Grok 3 (xAI)

# Biến cấu hình
DOMAIN="rocketsmtp.site"           # Domain cần cấu hình DKIM
MAIL_USER="mailuser"               # Tên user email
SELECTOR="mail"                    # Selector cho DKIM (có thể thay đổi, ví dụ: "2023")
DKIM_KEY_DIR="/etc/opendkim/keys"  # Thư mục lưu khóa DKIM
CONFIG_FILE="/etc/postfix/main.cf" # File cấu hình Postfix

# Bước 0: Cấu hình DNS (dùng Cloudflare DNS để đảm bảo độ tin cậy)
echo "Cấu hình DNS..."
echo "nameserver 1.1.1.1" > /etc/resolv.conf  # Đặt DNS chính là 1.1.1.1 (Cloudflare)
echo "nameserver 1.0.0.1" >> /etc/resolv.conf # Đặt DNS phụ là 1.0.0.1 (Cloudflare)

# Bước 1: Kích hoạt kho CRB
echo "Kích hoạt kho CRB để cài đặt các thư viện phụ thuộc cho OpenDKIM..."
dnf config-manager --set-enabled crb || { echo "Lỗi: Không thể kích hoạt kho CRB."; exit 1; }

# Bước 2: Cài đặt các thư viện phụ thuộc
echo "Cài đặt các thư viện phụ thuộc cho OpenDKIM..."
dnf install -y sendmail-milter libmemcached-awesome || { echo "Lỗi: Không thể cài đặt thư viện phụ thuộc."; exit 1; }

# Bước 3: Cài đặt OpenDKIM
echo "Cài đặt OpenDKIM và công cụ hỗ trợ..."
dnf install -y opendkim opendkim-tools || { echo "Lỗi: Không thể cài đặt OpenDKIM."; exit 1; }
if ! rpm -q opendkim >/dev/null 2>&1; then
    echo "Lỗi: OpenDKIM không được cài đặt đúng cách."
    exit 1
fi

# Bước 4: Tạo khóa DKIM
echo "Tạo khóa DKIM..."
mkdir -p ${DKIM_KEY_DIR}           # Tạo thư mục lưu khóa DKIM nếu chưa có
rm -f ${DKIM_KEY_DIR}/${SELECTOR}.* # Xóa khóa cũ nếu có để tránh xung đột
chown opendkim:opendkim ${DKIM_KEY_DIR} # Đặt quyền sở hữu cho user opendkim
chmod 700 ${DKIM_KEY_DIR}          # Đặt quyền truy cập thư mục chỉ cho owner
opendkim-genkey -s ${SELECTOR} -d ${DOMAIN} -D ${DKIM_KEY_DIR} # Tạo cặp khóa DKIM (public và private)
chown opendkim:opendkim ${DKIM_KEY_DIR}/${SELECTOR}.private # Đặt quyền sở hữu khóa private
chmod 600 ${DKIM_KEY_DIR}/${SELECTOR}.private # Đặt quyền đọc/ghi chỉ cho owner

# Bước 5: Cấu hình opendkim
echo "Cấu hình OpenDKIM..."
cat > /etc/opendkim.conf <<EOF     # Tạo file cấu hình opendkim
# Cấu hình cơ bản cho opendkim
Domain                  ${DOMAIN}  # Domain áp dụng DKIM
Selector                ${SELECTOR} # Selector dùng để ký
KeyFile                 ${DKIM_KEY_DIR}/${SELECTOR}.private # Đường dẫn khóa private
Socket                  local:/var/run/opendkim/opendkim.sock # Socket để giao tiếp với Postfix
Syslog                  yes        # Bật log qua syslog
Umask                   0002       # Đảm bảo socket có quyền rw-rw---- (660)
EOF

# Bước 6: Cấu hình Postfix để ký DKIM
echo "Cấu hình Postfix với DKIM..."
sed -i "/^[ \t]*smtpd_milters =/d" ${CONFIG_FILE} # Xóa dòng smtpd_milters cũ
sed -i "/^[ \t]*non_smtpd_milters =/d" ${CONFIG_FILE} # Xóa dòng non_smtpd_milters cũ
sed -i "/^[ \t]*milter_default_action =/d" ${CONFIG_FILE} # Xóa dòng milter_default_action cũ
sed -i "/^[ \t]*milter_protocol =/d" ${CONFIG_FILE} # Xóa dòng milter_protocol cũ
echo "smtpd_milters = unix:/var/run/opendkim/opendkim.sock" >> ${CONFIG_FILE} # Thêm milter DKIM vào Postfix
echo "non_smtpd_milters = unix:/var/run/opendkim/opendkim.sock" >> ${CONFIG_FILE} # Áp dụng milter cho cả non-SMTP
echo "milter_default_action = accept" >> ${CONFIG_FILE} # Chấp nhận mail nếu milter thất bại
echo "milter_protocol = 6" >> ${CONFIG_FILE} # Sử dụng giao thức milter phiên bản 6
usermod -aG opendkim postfix # Thêm postfix vào nhóm opendkim để truy cập socket

# Bước 7: Khởi động lại dịch vụ
echo "Khởi động dịch vụ..."
systemctl enable opendkim --now || { echo "Lỗi: Không thể khởi động opendkim."; exit 1; } # Kích hoạt và khởi động opendkim
chmod 660 /var/run/opendkim/opendkim.sock # Sửa quyền socket để postfix truy cập được
chown opendkim:postfix /var/run/opendkim/opendkim.sock # Đặt nhóm postfix cho socket
systemctl restart postfix || { echo "Lỗi: Không thể khởi động lại Postfix."; exit 1; } # Khởi động lại Postfix

# Bước 8: Hiển thị bản ghi DKIM để thêm vào DNS
echo "Thêm bản ghi TXT sau vào DNS của ${DOMAIN} (ví dụ: mail._domainkey.${DOMAIN}):"
cat ${DKIM_KEY_DIR}/${SELECTOR}.txt # Hiển thị bản ghi DKIM để thêm vào DNS

# Bước 9: Kiểm tra DKIM với email thử nghiệm
echo "Gửi mail thử từ ${MAIL_USER}@${DOMAIN} để kiểm tra DKIM:"
echo "1. Dùng lệnh sau để gửi mail thử:"
echo "   echo 'Test DKIM content' | /usr/sbin/sendmail -f ${MAIL_USER}@${DOMAIN} <email_nhan>"
echo "2. Hoặc dùng Roundcube gửi mail từ ${MAIL_USER}@${DOMAIN} đến một email khác (ví dụ: Gmail)."
echo "3. Kiểm tra header email nhận được để xác nhận DKIM-Signature."
echo "4. Kiểm tra log Postfix:"
echo "   tail -n 50 /var/log/maillog | grep dkim"

echo "Cấu hình DKIM hoàn tất! Thêm bản ghi DNS và thử gửi mail để kiểm tra."
