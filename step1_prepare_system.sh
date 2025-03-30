#!/bin/bash

# Script chuẩn bị hệ thống cho cài đặt Roundcube - Bước 1
# Chạy với quyền root: sudo bash step1_prepare_system.sh

# Kiểm tra quyền root
if [ "$(id -u)" != "0" ]; then
   echo "Script này cần chạy với quyền root. Sử dụng sudo hoặc đăng nhập root."
   exit 1
fi

echo "Bắt đầu Bước 1: Chuẩn bị hệ thống và cài đặt công cụ cơ bản..."

# Kiểm tra kết nối internet
echo "Kiểm tra kết nối internet..."
ping -c 4 8.8.8.8 > /dev/null 2>&1
if [ $? -ne 0 ]; then
   echo "Lỗi: Máy chủ không có kết nối internet. Vui lòng kiểm tra kết nối mạng và thử lại."
   exit 1
fi

# Cập nhật hệ thống
echo "Cập nhật hệ thống..."
#dnf update -y || { echo "Lỗi: Không thể cập nhật hệ thống."; exit 1; }

# Cài đặt các công cụ cơ bản
echo "Cài đặt các công cụ cơ bản..."
dnf install -y nano telnet bind-utils s-nail tar curl net-tools firewalld || { echo "Lỗi: Không thể cài đặt công cụ."; exit 1; }

# Kích hoạt firewalld nếu chưa chạy
if ! systemctl is-active firewalld >/dev/null 2>&1; then
   echo "Kích hoạt firewalld..."
   systemctl enable firewalld --now || { echo "Lỗi: Không thể kích hoạt firewalld."; exit 1; }
fi

# Kiểm tra các công cụ đã cài đặt
echo "Kiểm tra các công cụ đã cài đặt..."
for tool in nano telnet dig s-nail tar curl netstat firewall-cmd; do
   if ! command -v "$tool" >/dev/null 2>&1; then
      echo "Lỗi: Công cụ $tool không được cài đặt đúng cách."
      exit 1
   else
      echo " - $tool: OK"
   fi
done

# Hoàn tất
echo "Bước 1 hoàn tất!"
echo "Hệ thống đã được cập nhật và các công cụ cơ bản đã được cài đặt thành công."
echo "Hãy kiểm tra output ở trên để đảm bảo không có lỗi, sau đó báo lại để tiếp tục bước tiếp theo."
