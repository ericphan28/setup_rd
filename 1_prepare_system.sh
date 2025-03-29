#!/bin/bash

# Script chuẩn bị hệ thống cho cài đặt Roundcube
# Chạy với quyền root: sudo bash prepare_system.sh

# Biến cấu hình
DOMAIN="rocketsmtp.site"
HOSTNAME="mail.rocketsmtp.site"

# Kiểm tra quyền root
if [ "$(id -u)" != "0" ]; then
   echo "Script này cần chạy với quyền root. Sử dụng sudo hoặc đăng nhập root."
   exit 1
fi

echo "Bắt đầu chuẩn bị hệ thống cho cài đặt Roundcube..."

# Bước 1: Kiểm tra kết nối internet
echo "Kiểm tra kết nối internet..."
ping -c 4 8.8.8.8 > /dev/null 2>&1
if [ $? -ne 0 ]; then
   echo "Lỗi: Máy chủ không có kết nối internet. Vui lòng kiểm tra kết nối mạng và thử lại."
   exit 1
fi

# Bước 2: Kiểm tra và cấu hình DNS
echo "Kiểm tra phân giải DNS..."
if command -v getent >/dev/null 2>&1; then
   getent hosts mirrors.almalinux.org > /dev/null 2>&1
   if [ $? -ne 0 ]; then
      echo "Cảnh báo: Không thể phân giải tên miền mirrors.almalinux.org. Cấu hình DNS..."
      if systemctl is-active NetworkManager >/dev/null 2>&1; then
         echo "NetworkManager đang hoạt động. Sử dụng nmcli để cấu hình DNS."
         nmcli con mod "$(nmcli con show | grep -v NAME | awk '{print $1}')" ipv4.dns "1.1.1.1 1.0.0.1"
         nmcli con up "$(nmcli con show | grep -v NAME | awk '{print $1}')"
      else
         echo "nameserver 1.1.1.1" > /etc/resolv.conf
         echo "nameserver 1.0.0.1" >> /etc/resolv.conf
      fi
      getent hosts mirrors.almalinux.org > /dev/null 2>&1
      if [ $? -ne 0 ]; then
         echo "Cảnh báo: Vẫn không thể phân giải tên miền. Script sẽ tiếp tục, nhưng bạn cần khắc phục DNS sau."
         echo "Nhấn Enter để tiếp tục..."
         read
      fi
   fi
else
   echo "Cảnh báo: Không tìm thấy lệnh 'getent'. Bỏ qua kiểm tra DNS."
   echo "Nhấn Enter để tiếp tục..."
   read
fi

# Bước 3: Cập nhật hệ thống và cài đặt công cụ cần thiết
echo "Cập nhật hệ thống và cài đặt công cụ cần thiết..."
dnf update -y || { echo "Lỗi: Không thể cập nhật hệ thống."; exit 1; }
dnf install -y epel-release || { echo "Lỗi: Không thể cài đặt epel-release."; exit 1; }
dnf install -y wget curl net-tools firewalld tar bind-utils nmap-ncat s-nail || { echo "Lỗi: Không thể cài đặt công cụ."; exit 1; }

# Bước 4: Thiết lập hostname
echo "Thiết lập hostname..."
hostnamectl set-hostname $HOSTNAME
echo "127.0.0.1 $HOSTNAME mail localhost localhost.localdomain" >> /etc/hosts

# Bước 5: Mở các cổng cần thiết trên firewall
echo "Mở các cổng cần thiết trên firewall..."
systemctl start firewalld
systemctl enable firewalld
firewall-cmd --add-port=25/tcp --permanent
firewall-cmd --add-port=143/tcp --permanent
firewall-cmd --add-port=587/tcp --permanent
firewall-cmd --add-port=80/tcp --permanent
firewall-cmd --add-port=443/tcp --permanent
firewall-cmd --reload

# Bước 6: Hoàn tất
echo "Chuẩn bị hệ thống hoàn tất!"
echo "Các công cụ cơ bản đã được cài đặt."
echo "Hostname đã được thiết lập: $HOSTNAME"
echo "Các cổng cần thiết đã được mở trên firewall."
echo "Bạn có thể tiếp tục với bước tiếp theo (cấu hình OpenDKIM)."
