
#!/bin/bash

mv /etc/httpd/conf.d/viciportal-ssl.conf /etc/httpd/conf.d/viciportal-ssl.conf.
sudo systemctl stop firewalld
certbot renew
sudo systemctl restart firewalld
mv /etc/httpd/conf.d/viciportal-ssl.conf. /etc/httpd/conf.d/viciportal-ssl.conf
domain=$(basename /etc/letsencrypt/renewal/*.conf | sed 's/\.conf$//')
systemctl reload httpd
asterisk -rx "reload"
