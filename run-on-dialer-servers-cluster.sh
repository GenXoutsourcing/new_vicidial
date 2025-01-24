echo "Enter the database IP:"
read DB

perl /usr/src/astguiclient/trunk/install.pl --DB_server=$DB --no-prompt
asterisk -rx 'core restart now'
sleep 2
/usr/share/astguiclient/ADMIN_keepalive_ALL.pl
