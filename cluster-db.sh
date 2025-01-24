#!/bin/sh
wget https://cybur-dial.com/downloads/cluster-db
echo "Enter the database IP:"
read DB
mysql -u root asterisk < cluster-db
/usr/share/astguiclient/ADMIN_update_server_ip.pl --old-server_ip=192.168.1.1 --server_ip=$DB
echo "Enter dialer 1 IP:"
read DIALER1
/usr/share/astguiclient/ADMIN_update_server_ip.pl --old-server_ip=192.168.1.2 --server_ip=$DIALER1
echo "Enter dialer 2 IP:"
read DIALER2
/usr/share/astguiclient/ADMIN_update_server_ip.pl --old-server_ip=192.168.1.3 --server_ip=$DIALER2
echo "Enter dialer 3 IP:"
read DIALER3
/usr/share/astguiclient/ADMIN_update_server_ip.pl --old-server_ip=192.168.1.4 --server_ip=$DIALER3
echo "Enter dialer 4 IP:"
read DIALER4
/usr/share/astguiclient/ADMIN_update_server_ip.pl --old-server_ip=192.168.1.5 --server_ip=$DIALER4
echo "Enter dialer 5 IP:"
read DIALER5
/usr/share/astguiclient/ADMIN_update_server_ip.pl --old-server_ip=192.168.1.6 --server_ip=$DIALER5
echo "Enter dialer 6 IP:"
read DIALER6
/usr/share/astguiclient/ADMIN_update_server_ip.pl --old-server_ip=192.168.1.7 --server_ip=$DIALER6

cd /usr/src/astguiclient/trunk
svn up
perl install.pl --no-prompt --db-server=$DB
mysql -p -f --database=asterisk < /usr/src/astguiclient/trunk/extras/upgrade_2.14.sql
echo "Press Enter"
echo "The default password for the 6666 admin user is CyburDial2025"
echo "The default password for the 6666 admin user is CyburDial2025"
echo "The default password for the 6666 admin user is CyburDial2025"
echo "The default password for the 6666 admin user is CyburDial2025"
echo "This added users 8000 - 8150 with matching passwords and phones load balanced across all servers"
echo "Don't forget to update the webrtc template named "SIP_GENERIC" with your SSL certs for each server"
