#!/bin/sh
wget https://cybur-dial.com/downloads/standard-db.zip
unzip standard-db.zip
mysql -u root asterisk < standard-db
/usr/share/astguiclient/ADMIN_update_server_ip.pl --old-server_ip=149.28.96.244
cd /usr/src/astguiclient/trunk
svn up
perl install.pl --no-prompt
mysql -p -f --database=asterisk < /usr/src/astguiclient/trunk/extras/upgrade_2.14.sql
echo "Just press enter"
echo "The default password for the 6666 admin user is CyburDial2024"
echo "The default password for the 6666 admin user is CyburDial2024"
echo "The default password for the 6666 admin user is CyburDial2024"
echo "The default password for the 6666 admin user is CyburDial2024"
