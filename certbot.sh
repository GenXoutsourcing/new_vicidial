
#!/bin/bash

mv /etc/httpd/conf.d/viciportal-ssl.conf /etc/httpd/conf.d/viciportal-ssl.conf.
service firewalld stop
certbot renew
service firewalld restart
mv /etc/httpd/conf.d/viciportal-ssl.conf. /etc/httpd/conf.d/viciportal-ssl.conf
domain=$(basename /etc/letsencrypt/renewal/*.conf | sed 's/\.conf$//')
systemctl reload httpd
asterisk -rx "reload"
