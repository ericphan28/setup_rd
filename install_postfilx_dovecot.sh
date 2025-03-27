dnf install -y postfix dovecot cyrus-sasl cyrus-sasl-plain cyrus-sasl-md5 cyrus-sasl-sql  s-nail

postconf -e "myhostname = rocketsmtp.site"
postconf -e "mydomain = rocketsmtp.site"
postconf -e "myorigin = \$mydomain"
postconf -e "inet_interfaces = all"
postconf -e "inet_protocols = all"
postconf -e "mydestination = \$myhostname, localhost.\$mydomain, localhost, \$mydomain"
postconf -e "mynetworks = 127.0.0.0/8, 103.176.20.154"
postconf -e "home_mailbox = Maildir/"
postconf -e "smtpd_banner = \$myhostname ESMTP"
postconf -e "smtpd_tls_cert_file = /etc/ssl/certs/ssl-cert-snakeoil.pem"
postconf -e "smtpd_tls_key_file = /etc/ssl/private/ssl-cert-snakeoil.key"
postconf -e "smtpd_use_tls = yes"
postconf -e "smtpd_sasl_auth_enable = yes"
postconf -e "smtpd_sasl_security_options = noanonymous"
postconf -e "broken_sasl_auth_clients = yes"
postconf -e "smtpd_relay_restrictions = permit_mynetworks, permit_sasl_authenticated, defer_unauth_destination"
postconf -e "smtpd_recipient_restrictions = permit_mynetworks, permit_sasl_authenticated, reject_unauth_destination"


echo "pwcheck_method: auxprop" > /etc/sasl2/smtpd.conf
echo "mech_list: PLAIN LOGIN" >> /etc/sasl2/smtpd.conf

chown postfix:postfix /etc/postfix/sasl/smtpd.conf
chmod 640 /etc/postfix/sasl/smtpd.conf
systemctl restart postfix saslauthd

sed -i 's/^#disable_plaintext_auth = yes/disable_plaintext_auth = no/' /etc/dovecot/conf.d/10-auth.conf
sed -i 's/^#mail_location =/mail_location = maildir:~\/Maildir/' /etc/dovecot/conf.d/10-mail.conf
sed -i 's/^#ssl = yes/ssl = no/' /etc/dovecot/conf.d/10-ssl.conf

systemctl enable --now postfix dovecot
systemctl enable --now saslauthd

useradd testuser -m -s /sbin/nologin
echo "Test@123" | passwd --stdin testuser
mkdir -p /home/testuser/Maildir
chown -R testuser:testuser /home/testuser/Maildir


firewall-cmd --add-service=smtp --permanent
firewall-cmd --add-service=imap --permanent
firewall-cmd --add-service=pop3 --permanent
firewall-cmd --reload


dnf install -y openssl
mkdir -p /etc/ssl/certs /etc/ssl/private

openssl req -new -x509 -days 365 -nodes -out /etc/ssl/certs/postfix.pem -keyout /etc/ssl/private/postfix.key -subj "/CN=rocketsmtp.site"

chmod 600 /etc/ssl/private/postfix.key

postconf -e "smtpd_tls_cert_file = /etc/ssl/certs/postfix.pem"
postconf -e "smtpd_tls_key_file = /etc/ssl/private/postfix.key"
postconf -e "smtpd_use_tls = yes"
postconf -e "smtpd_tls_security_level = may"

systemctl restart postfix

echo "Test@123" | saslpasswd2 -c -u rocketsmtp.site -a smtp testuser
chown postfix:postfix /etc/sasl2/sasldb2
chmod 600 /etc/sasl2/sasldb2


postconf -e 'smtpd_sasl_auth_enable = yes'
postconf -e 'smtpd_sasl_security_options = noanonymous'
postconf -e 'smtpd_sasl_local_domain = rocketsmtp.site'
postconf -e 'broken_sasl_auth_clients = yes'
postconf -e 'smtpd_sasl_type = cyrus'
postconf -e 'smtpd_sasl_path = smtpd'
postconf -e 'smtpd_recipient_restrictions = permit_sasl_authenticated, permit_mynetworks, reject_unauth_destination'

cat <<EOF > /etc/sasl2/smtpd.conf
pwcheck_method: auxprop
auxprop_plugin: sasldb
mech_list: PLAIN LOGIN
EOF

systemctl restart postfix
systemctl restart saslauthd

dnf install -y swaks

