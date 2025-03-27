#!/bin/bash

# Cài đặt các gói cần thiết
dnf install -y postfix dovecot cyrus-sasl cyrus-sasl-plain cyrus-sasl-md5 cyrus-sasl-sql s-nail bind-utils openssl swaks || { echo "Cài đặt gói thất bại"; exit 1; }

# Cấu hình Postfix
postconf -e "myhostname = rocketsmtp.site" \
         "mydomain = rocketsmtp.site" \
         "myorigin = \$mydomain" \
         "inet_interfaces = all" \
         "inet_protocols = all" \
         "mydestination = \$myhostname, localhost.\$mydomain, localhost, \$mydomain" \
         "mynetworks = 127.0.0.0/8, 103.176.20.154" \
         "home_mailbox = Maildir/" \
         "smtpd_banner = \$myhostname ESMTP" \
         "smtpd_use_tls = yes" \
         "smtpd_tls_security_level = may" \
         "smtpd_sasl_auth_enable = yes" \
         "smtpd_sasl_type = cyrus" \
         "smtpd_sasl_path = smtpd" \
         "smtpd_sasl_local_domain = rocketsmtp.site" \
         "smtpd_sasl_security_options = noanonymous" \
         "broken_sasl_auth_clients = yes" \
         "smtpd_relay_restrictions = permit_mynetworks, permit_sasl_authenticated, defer_unauth_destination" \
         "smtpd_recipient_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_unauth_destination"

# Tạo chứng chỉ tự ký
mkdir -p /etc/ssl/certs /etc/ssl/private
openssl req -new -x509 -days 365 -nodes \
    -out /etc/ssl/certs/postfix.pem \
    -keyout /etc/ssl/private/postfix.key \
    -subj "/CN=rocketsmtp.site" || { echo "Tạo chứng chỉ thất bại"; exit 1; }
chmod 600 /etc/ssl/private/postfix.key
postconf -e "smtpd_tls_cert_file = /etc/ssl/certs/postfix.pem" \
         "smtpd_tls_key_file = /etc/ssl/private/postfix.key"

# Cấu hình SASL
cat <<EOF > /etc/sasl2/smtpd.conf
pwcheck_method: auxprop
auxprop_plugin: sasldb
mech_list: PLAIN LOGIN
EOF
chmod 640 /etc/sasl2/smtpd.conf
chown postfix:postfix /etc/sasl2/smtpd.conf

# Cấu hình Dovecot
sed -i 's/^#disable_plaintext_auth = yes/disable_plaintext_auth = no/' /etc/dovecot/conf.d/10-auth.conf
sed -i 's/^#mail_location =/mail_location = maildir:~\/Maildir/' /etc/dovecot/conf.d/10-mail.conf
sed -i 's/^#ssl = yes/ssl = no/' /etc/dovecot/conf.d/10-ssl.conf
echo "auth_mechanisms = plain login" >> /etc/dovecot/conf.d/10-auth.conf

# Tạo người dùng thử nghiệm
useradd -m -s /sbin/nologin testuser || { echo "Tạo user thất bại"; exit 1; }
echo "testuser:Test@123" | chpasswd
mkdir -p /home/testuser/Maildir
chown -R testuser:testuser /home/testuser/Maildir

# Cấu hình SASL password
echo "Test@123" | saslpasswd2 -c -u rocketsmtp.site -a smtp testuser
chown postfix:postfix /etc/sasl2/sasldb2
chmod 600 /etc/sasl2/sasldb2

# Khởi động dịch vụ
systemctl enable --now postfix dovecot saslauthd || { echo "Khởi động dịch vụ thất bại"; exit 1; }
systemctl restart postfix dovecot saslauthd

# Cấu hình tường lửa
firewall-cmd --add-service=smtp --permanent
firewall-cmd --add-service=imap --permanent
firewall-cmd --add-service=pop3 --permanent
firewall-cmd --reload

echo "Cài đặt hoàn tất. Kiểm tra trạng thái dịch vụ:"
systemctl status postfix dovecot saslauthd
