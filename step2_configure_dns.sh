#!/bin/bash

# Script cấu hình và kiểm tra DNS cho Roundcube - Bước 2
# Chạy với quyền root: sudo bash step2_configure_dns.sh

# Biến cấu hình
DOMAIN="rocketsmtp.site"
EXPECTED_IP="103.176.20.154"

# Kiểm tra quyền root
if [ "$(id -u)" != "0" ]; then
   echo "Script này cần chạy với quyền root. Sử dụng sudo hoặc đăng nhập root."
   exit 1
fi

echo "Bắt đầu Bước 2: Kiểm tra và cấu hình DNS cho $DOMAIN..."

# Kiểm tra kết nối internet
echo "Kiểm tra kết nối internet..."
ping -c 4 8.8.8.8 > /dev/null 2>&1
if [ $? -ne 0 ]; then
   echo "Lỗi: Máy chủ không có kết nối internet. Vui lòng kiểm tra kết nối mạng và thử lại."
   exit 1
fi

# Đảm bảo phân giải DNS hoạt động trên VPS
echo "Kiểm tra khả năng phân giải DNS..."
if ! dig +short google.com >/dev/null 2>&1; then
   echo "Cảnh báo: VPS không thể phân giải DNS. Cập nhật /etc/resolv.conf..."
   echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf > /dev/null
   echo "nameserver 1.0.0.1" | sudo tee -a /etc/resolv.conf > /dev/null
   if ! dig +short google.com >/dev/null 2>&1; then
      echo "Lỗi: Vẫn không thể phân giải DNS sau khi cập nhật. Vui lòng kiểm tra mạng."
      exit 1
   else
      echo "Đã cập nhật /etc/resolv.conf thành công."
   fi
else
   echo "Phân giải DNS trên VPS hoạt động tốt."
fi

# Kiểm tra bản ghi A
echo "Kiểm tra bản ghi A cho $DOMAIN..."
A_RECORD=$(dig +short A $DOMAIN | grep -v '\.$' | head -n 1)
if [ "$A_RECORD" = "$EXPECTED_IP" ]; then
   echo " - Bản ghi A: OK ($DOMAIN trỏ về $A_RECORD)"
else
   echo " - Cảnh báo: Bản ghi A không khớp. Hiện tại: $A_RECORD, mong đợi: $EXPECTED_IP"
   echo "   Vui lòng cập nhật bản ghi A tại nhà cung cấp DNS của bạn."
fi

# Kiểm tra bản ghi MX
echo "Kiểm tra bản ghi MX cho $DOMAIN..."
MX_RECORD=$(dig +short MX $DOMAIN)
if [ -n "$MX_RECORD" ]; then
   echo " - Bản ghi MX: OK ($MX_RECORD)"
else
   echo " - Cảnh báo: Không tìm thấy bản ghi MX."
   echo "   Đề xuất: Thêm bản ghi MX (ví dụ: 10 $DOMAIN) tại nhà cung cấp DNS."
fi

# Kiểm tra bản ghi TXT (SPF)
echo "Kiểm tra bản ghi TXT (SPF) cho $DOMAIN..."
SPF_RECORD=$(dig +short TXT $DOMAIN | grep "v=spf1")
if [ -n "$SPF_RECORD" ]; then
   echo " - Bản ghi SPF: OK ($SPF_RECORD)"
else
   echo " - Cảnh báo: Không tìm thấy bản ghi SPF."
   echo "   Đề xuất: Thêm bản ghi TXT: 'v=spf1 ip4:$EXPECTED_IP -all' tại nhà cung cấp DNS."
fi

# Hoàn tất
echo "Bước 2 hoàn tất!"
echo "Kết quả kiểm tra DNS đã hiển thị ở trên."
echo "Nếu có cảnh báo, hãy cập nhật DNS tại nhà cung cấp domain (ví dụ: Namecheap, GoDaddy) và đợi propagate (có thể mất vài giờ)."
echo "Sau khi xác nhận DNS đúng, báo lại để tiếp tục bước tiếp theo."
