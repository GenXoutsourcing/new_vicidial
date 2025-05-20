
#!/bin/bash


systemctl stop firewalld
certbot renew
systemctl restart firewalld

systemctl restart httpd


