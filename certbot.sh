
#!/bin/bash

mv /etc/httpd/conf.d/viciportal-ssl.conf /etc/httpd/conf.d/viciportal-ssl.conf.
systemctl firewalld stop
certbot renew
systemctl firewalld restart
mv /etc/httpd/conf.d/viciportal-ssl.conf. /etc/httpd/conf.d/viciportal-ssl.conf
domain=$(basename /etc/letsencrypt/renewal/*.conf | sed 's/\.conf$//')
systemctl reload httpd
asterisk -rx "reload"
