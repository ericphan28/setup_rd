#!/bin/bash

# Cài đặt các công cụ
echo "Đang cài đặt các công cụ cơ bản..."
dnf install -y nano telnet bind-utils s-nail tar wget

# Kiểm tra từng công cụ
echo -e "\nKiểm tra nano:"
nano --version

echo -e "\nKiểm tra telnet (chạy thử kết nối localhost 22 nếu SSH đang bật):"
telnet localhost 22 </dev/null 2>&1 | grep -i "Connected" || echo "Telnet đã cài nhưng không kết nối được localhost:22 (có thể SSH chưa chạy)"

echo -e "\nKiểm tra nslookup:"
nslookup rocketsmtp.site

echo -e "\nKiểm tra s-nail:"
s-nail --version

echo -e "\nKiểm tra tar:"
tar --version

echo -e "\nKiểm tra wget:"
wget --version

echo -e "\nHoàn tất cài đặt và kiểm tra công cụ!"

#!/bin/bash

#!/bin/bash
echo "Đang cài đặt Postfix..."
dnf install -y postfix
cp /etc/postfix/main.cf /etc/postfix/main.cf.bak
echo "Đang cấu hình Postfix..."
sed -i 's/#myhostname = .*/myhostname = rocketsmtp.site/' /etc/postfix/main.cf
sed -i 's/#mydomain = .*/mydomain = rocketsmtp.site/' /etc/postfix/main.cf
sed -i 's/#myorigin = .*/myorigin = $mydomain/' /etc/postfix/main.cf
sed -i 's/inet_interfaces = localhost/inet_interfaces = all/' /etc/postfix/main.cf
sed -i 's/mydestination = .*/mydestination = $myhostname, localhost.$mydomain, localhost/' /etc/postfix/main.cf
sed -i '/^home_mailbox =/d' /etc/postfix/main.cf  # Xóa mọi dòng home_mailbox cũ
echo "home_mailbox = Maildir/" >> /etc/postfix/main.cf  # Thêm dòng mới
echo "Khởi động và bật Postfix..."
systemctl start postfix
systemctl enable postfix
echo "Kiểm tra trạng thái Postfix..."
systemctl status postfix | grep "Active:"
echo "Kiểm tra SMTP qua telnet..."
echo -e "EHLO rocketsmtp.site\nQUIT" | telnet localhost 25
echo "Hoàn tất cài đặt và kiểm tra Postfix!"

#!/bin/bash

# Cài đặt firewalld
echo "Đang cài đặt firewalld..."
dnf install -y firewalld

# Khởi động và bật firewalld
echo "Khởi động và bật firewalld..."
systemctl start firewalld
systemctl enable firewalld

# Kiểm tra trạng thái
echo "Kiểm tra trạng thái firewalld..."
systemctl status firewalld | grep "Active:"

# Mở các cổng cần thiết cho Roundcube
echo "Đang mở các cổng cần thiết..."
firewall-cmd --add-port=22/tcp --permanent    # SSH
firewall-cmd --add-port=25/tcp --permanent    # SMTP
firewall-cmd --add-port=143/tcp --permanent   # IMAP
firewall-cmd --add-port=110/tcp --permanent   # POP3
firewall-cmd --add-port=80/tcp --permanent    # HTTP
firewall-cmd --add-port=443/tcp --permanent   # HTTPS
firewall-cmd --add-port=465/tcp --permanent   # SMTPS
firewall-cmd --add-port=993/tcp --permanent   # IMAPS
firewall-cmd --add-port=995/tcp --permanent   # POP3S

# Tải lại firewall
echo "Tải lại firewall để áp dụng..."
firewall-cmd --reload

# Kiểm tra danh sách cổng
echo "Danh sách cổng đã mở:"
firewall-cmd --list-all

echo "Hoàn tất cài đặt và cấu hình firewall!"

#!/bin/bash

# Cài đặt Dovecot
echo "Đang cài đặt Dovecot..."
dnf install -y dovecot

# Sao lưu file cấu hình
cp /etc/dovecot/dovecot.conf /etc/dovecot/dovecot.conf.bak

# Cấu hình Dovecot
echo "Đang cấu hình Dovecot..."
sed -i 's/#protocols = imap pop3 lmtp/protocols = imap pop3/' /etc/dovecot/dovecot.conf
sed -i 's/#mail_location = .*/mail_location = maildir:~\/Maildir/' /etc/dovecot/conf.d/10-mail.conf
sed -i 's/#disable_plaintext_auth = yes/disable_plaintext_auth = no/' /etc/dovecot/conf.d/10-auth.conf
sed -i 's/#auth_mechanisms = plain/auth_mechanisms = plain login/' /etc/dovecot/conf.d/10-auth.conf

# Khởi động Dovecot
echo "Khởi động và bật Dovecot..."
systemctl start dovecot
systemctl enable dovecot

# Kiểm tra trạng thái
echo "Kiểm tra trạng thái Dovecot..."
systemctl status dovecot | grep "Active:"

# Kiểm tra IMAP và POP3
echo "Kiểm tra IMAP qua telnet..."
echo -e "a1 LOGIN test test\na2 LOGOUT" | telnet localhost 143
echo "Kiểm tra POP3 qua telnet..."
echo -e "USER test\nPASS test\nQUIT" | telnet localhost 110

# Kiểm tra port
echo "Kiểm tra các port đang lắng nghe..."
netstat -tuln | grep -E ':143|:110'

echo "Hoàn tất cài đặt và kiểm tra Dovecot!"

#!/bin/bash

# Tạo user mailuser
echo "Đang tạo user mailuser..."
useradd -m -s /bin/bash mailuser
echo "mailuser:pss123" | chpasswd

# Tạo thư mục Maildir
echo "Tạo thư mục Maildir cho mailuser..."
mkdir -p /home/mailuser/Maildir/{new,cur,tmp}
chown -R mailuser:mailuser /home/mailuser/Maildir
chmod -R 700 /home/mailuser/Maildir

# Kiểm tra gửi email
echo "Gửi email thử bằng s-nail..."
echo "This is a test email" | s-nail -s "Test from mailuser" -r "mailuser@rocketsmtp.site" your_email@example.com

# Kiểm tra log
echo "Kiểm tra log Postfix..."
tail -n 20 /var/log/maillog

# Kiểm tra IMAP
echo "Kiểm tra đăng nhập IMAP..."
echo -e "a1 LOGIN mailuser pss123\na2 LIST \"\" \"*\"\na3 LOGOUT" | telnet 127.0.0.1 143

echo "Hoàn tất tạo user và kiểm tra email!"

 
