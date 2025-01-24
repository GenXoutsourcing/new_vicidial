#!/bin/sh

echo "Vicidial installation Debian 12 with WebPhone(WebRTC/SIP.js)"
apt install build-essential
apt install flex git python3-pip yum
##yum groupinstall "Development Tools" -y

apt install -y apt-transport-https lsb-release ca-certificates wget
wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/php.list
sudo apt update
apt install -y php7.4 
apt install -y mariadb-server
 
apt install libjansson* libedit* -y
apt -y install dnf-plugins-core
sudo apt install sqlite3 libsqlite3-dev -y
apt-get install linux-headers-generic -y

apt install -y php7.4 php7.4-opcache screen php7.4-mcrypt php-pear libmcrypt-dev mcrypt byobu screenie iselect db5.3-util libapache2-mod-svn subversion-tools subversion php7.4-cli php7.4-gd php7.4-curl php7.4-mysql php7.4-ldap php7.4-zip php7.4-common
apt install -y wget unzip make patch subversion php7.4-mbstring apache2
apt install -y php7.4-imap php7.4-ldap php7.4-mysqli php7.4-odbc php-pear php7.4-xml php7.4-xmlrpc curlk 
##apt install -y newt-devel libxml2-devel kernel-devel sqlite-devel libuuid-devel sox sendmail lame-devel htop iftop perl-File-Which
##apt install -y php-opcache libss7 mariadb-devel libss7* libopen* 
##apt install -y sqlite-devel httpd mod_ssl nano chkconfig htop atop mytop iftop
apt install -y uuid* libxml2*

cpan> install Bundle::CPAN
cpan> reload cpan
cpan> install YAML
cpan> install MD5
cpan> install Digest::MD5
cpan> install Digest::SHA1
cpan> install readline
cpan> reload cpan
cpan> install DBI
cpan> force install DBD::mysql
cpan> install Net::Telnet
cpan> install Time::HiRes
cpan> install Net::Server
cpan> install Switch
cpan> install Mail::Sendmail
cpan> install Unicode::Map
cpan> install Jcode
cpan> install Spreadsheet::WriteExcel
cpan> install OLE::Storage_Lite
cpan> install Proc::ProcessTable
cpan> install IO::Scalar
cpan> install Spreadsheet::ParseExcel
cpan> install Curses
cpan> install Getopt::Long
cpan> install Net::Domain
cpan> install Term::ReadKey
cpan> install Term::ANSIColor
cpan> install Spreadsheet::XLSX
cpan> install Spreadsheet::Read
cpan> install LWP::UserAgent
cpan> install HTML::Entities
cpan> install HTML::Strip
cpan> install HTML::FormatText
cpan> install HTML::TreeBuilder
cpan> install Time::Local
cpan> install MIME::Decoder
cpan> install Mail::POP3Client
cpan> install Mail::IMAPClient
cpan> install Mail::Message
cpan> install IO::Socket::SSL
cpan> install MIME::Base64
cpan> install MIME::QuotedPrint
cpan> install Crypt::Eksblowfish::Bcrypt
cpan> quit 


apt install libsrtp* -y

### up to this point

tee -a /etc/apache2/apache2.conf <<EOF

CustomLog /dev/null common

Alias /RECORDINGS/MP3 "/var/spool/asterisk/monitorDONE/MP3/"

<Directory "/var/spool/asterisk/monitorDONE/MP3/">
    Options Indexes MultiViews
    AllowOverride None
    Require all granted
</Directory>
EOF

sudo sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

tee -a /etc/php/7.4/apache2/php.ini <<EOF

error_reporting  =  E_ALL & ~E_NOTICE
memory_limit = 448M
short_open_tag = On
max_execution_time = 3330
max_input_time = 3360
post_max_size = 448M
upload_max_filesize = 442M
default_socket_timeout = 3360
date.timezone = America/New_York
EOF


systemctl restart apache2


apt install -y mysql*

apt-get install dnf-plugins-core -y
#dnf config-manager --set-enabled powertools


systemctl enable mysql

cp /etc/my.cnf /etc/my.cnf.original
echo "" > /etc/my.cnf


cat <<MYSQLCONF>> /etc/my.cnf
[mysql.server]
user = mysql
#basedir = /var/lib

[client]
port = 3306
socket = /var/lib/mysql/mysql.sock

[mysqld]
datadir = /var/lib/mysql
#tmpdir = /home/mysql_tmp
socket = /var/lib/mysql/mysql.sock
user = mysql
old_passwords = 0
ft_min_word_len = 3
max_connections = 800
max_allowed_packet = 32M
skip-external-locking
sql_mode="NO_ENGINE_SUBSTITUTION"

log-error = /var/log/mysqld/mysqld.log

query-cache-type = 1
query-cache-size = 32M

long_query_time = 1
#slow_query_log = 1
#slow_query_log_file = /var/log/mysqld/slow-queries.log

tmp_table_size = 128M
table_cache = 1024

join_buffer_size = 1M
key_buffer = 512M
sort_buffer_size = 6M
read_buffer_size = 4M
read_rnd_buffer_size = 16M
myisam_sort_buffer_size = 64M

max_tmp_tables = 64

thread_cache_size = 8
thread_concurrency = 8

# If using replication, uncomment log-bin below
#log-bin = mysql-bin

[mysqldump]
quick
max_allowed_packet = 16M

[mysql]
no-auto-rehash

[isamchk]
key_buffer = 256M
sort_buffer_size = 256M
read_buffer = 2M
write_buffer = 2M

[myisamchk]
key_buffer = 256M
sort_buffer_size = 256M
read_buffer = 2M
write_buffer = 2M

[mysqlhotcopy]
interactive-timeout

[mysqld_safe]
#log-error = /var/log/mysqld/mysqld.log
#pid-file = /var/run/mysqld/mysqld.pid
MYSQLCONF

mkdir /var/log/mysqld
touch /var/log/mysqld/slow-queries.log
chown -R mysql:mysql /var/log/mysqld
systemctl restart mariadb

systemctl enable apache2.service
systemctl enable mariadb.service
systemctl restart apache2.service
systemctl restart mariadb.service

#Install Perl Modules

echo "Install Perl"

apt install -y perl-CPAN perl-YAML perl-CPAN-DistnameInfo perl-libwww-perl perl-DBI perl-DBD-MySQL perl-GD perl-Env perl-Term-ReadLine-Gnu perl-SelfLoader perl-open.noarch 

sudo add-apt-repository ppa:ondrej/php  -y
sudo apt-get update
sudo apt-get install build-essential linux-headers-`uname -r` subversion unzip libjansson-dev sqlite autoconf automake  libxml2-dev libncurses5-dev libsqlite3-dev  -y 
sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys E5267A6C
sudo apt-key adv --fetch-keys 'https://mariadb.org/mariadb_release_signing_key.asc'
sudo add-apt-repository 'deb [arch=amd64,arm64,ppc64el] https://mariadb.mirror.liquidtelecom.com/repo/10.6/ubuntu bionic main'
sudo apt update 
sudo apt-get install apache2 apache2-bin apache2-data libapache2-mod-php7.4 php7.4 php7.4-xcache php7.4-dev php7.4-mbstring php7.4-cli php7.4-common php7.4-json php7.4-mysql php7.4-readline sox lame screen libnet-telnet-perl php5.6-mysqli libasterisk-agi-perl mariadb-server mariadb-client libelf-dev autogen libtool shtool libdbd-mysql-perl libmysqlclient-dev libsrtp-dev uuid-dev libssl-dev git curl wget -y
#Special package for ASTblind and ASTloop(ip_relay need this package)
apt-get install libc6-i386


#Install Jansson
cd /usr/src/
wget http://www.digip.org/jansson/releases/jansson-2.5.tar.gz
tar -zxf jansson-2.5.tar.gz
#tar xvzf jasson*
cd jansson-2.5
./configure
make clean
make
make install 
ldconfig

#Install CPAMN
cd /usr/bin/
apt install cpanminus -y
curl -LOk http://xrl.us/cpanm
chmod +x cpanm
cpanm readline --force
read -p 'Press Enter to continue Install perl modules: '

cpanm -f File::HomeDir
cpanm -f File::Which
cpanm CPAN::Meta::Requirements
cpanm -f CPAN
cpanm YAML
cpanm MD5
cpanm Digest::MD5
cpanm Digest::SHA1
cpanm Bundle::CPAN
cpanm DBI
cpanm -f DBD::mysql
cpanm Net::Telnet
cpanm Time::HiRes
cpanm Net::Server
cpanm Switch
cpanm Mail::Sendmail
cpanm Unicode::Map
cpanm Jcode
cpanm Spreadsheet::WriteExcel
cpanm OLE::Storage_Lite
cpanm Proc::ProcessTable
cpanm IO::Scalar
cpanm Spreadsheet::ParseExcel
cpanm Curses
cpanm Getopt::Long
cpanm Net::Domain
cpanm Term::ReadKey
cpanm Term::ANSIColor
cpanm Spreadsheet::XLSX
cpanm Spreadsheet::Read
cpanm LWP::UserAgent
cpanm HTML::Entities
cpanm HTML::Strip
cpanm HTML::FormatText
cpanm HTML::TreeBuilder
cpanm Time::Local
cpanm MIME::Decoder
cpanm Mail::POP3Client
cpanm Mail::IMAPClient
cpanm Mail::Message
cpanm IO::Socket::SSL
cpanm MIME::Base64
cpanm MIME::QuotedPrint
cpanm Crypt::Eksblowfish::Bcrypt
cpanm Crypt::RC4
cpanm Text::CSV
cpanm Text::CSV_XS

#If the DBD::MYSQL Fail Run below Command
apt install libdbd-mysql-perl



read -p 'Press Enter to continue And Install Dahdi: '
#Install dahdi
apt-get install dahdi-* dahdi
modprobe dahdi
modprobe dahdi_dummy
/usr/sbin/dahdi_cfg -vvvvvvvvvvvvv

read -p 'Press Enter to continue And Install LibPRI and Asterisk: '

#Install Asterisk 
mkdir /usr/src/asterisk
cd /usr/src/asterisk
wget http://download.vicidial.com/required-apps/asterisk-13.29.2-vici.tar.gz  
tar -xvf asterisk-13.29.2-vici.tar.gz
cd asterisk-13.29.2
: ${JOBS:=$(( $(nproc) + $(nproc) / 2 ))}
./configure --libdir=/usr/lib --with-gsm=internal --enable-opus --enable-srtp --with-ssl --enable-asteriskssl --with-pjproject-bundled --without-ogg
make menuselect/menuselect menuselect-tree menuselect.makeopts
#enable app_meetme
menuselect/menuselect --enable app_meetme menuselect.makeopts
#enable res_http_websocket
menuselect/menuselect --enable res_http_websocket menuselect.makeopts
#enable res_srtp
menuselect/menuselect --enable res_srtp menuselect.makeopts
make -j ${JOBS} all
make install
make samples


read -p 'Press Enter to continue: '
echo 'Continuing...'
#Install astguiclient
echo "Installing astguiclient"
mkdir /usr/src/astguiclient
cd /usr/src/astguiclient
svn checkout svn://svn.eflo.net/agc_2-X/trunk
cd /usr/src/astguiclient/trunk
#Add mysql users and Databases
echo "%%%%%%%%%%%%%%%Please Enter Mysql Password Or Just Press Enter if you Dont have Password%%%%%%%%%%%%%%%%%%%%%%%%%%"
mysql -u root -p << MYSQLCREOF
CREATE DATABASE asterisk DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;
CREATE USER 'cron'@'localhost' IDENTIFIED BY '1234';
GRANT SELECT,INSERT,UPDATE,DELETE,LOCK TABLES on asterisk.* TO cron@'%' IDENTIFIED BY '1234';
CREATE USER 'custom'@'localhost' IDENTIFIED BY 'custom1234';
GRANT SELECT,INSERT,UPDATE,DELETE,LOCK TABLES on asterisk.* TO custom@'%' IDENTIFIED BY 'custom1234';
GRANT SELECT,INSERT,UPDATE,DELETE,LOCK TABLES on asterisk.* TO cron@localhost IDENTIFIED BY '1234';
GRANT SELECT,INSERT,UPDATE,DELETE,LOCK TABLES on asterisk.* TO custom@localhost IDENTIFIED BY 'custom1234';
GRANT RELOAD ON *.* TO cron@'%';
GRANT RELOAD ON *.* TO cron@localhost;
GRANT RELOAD ON *.* TO custom@'%';
GRANT RELOAD ON *.* TO custom@localhost;
flush privileges;
use asterisk;
\. /usr/src/astguiclient/trunk/extras/MySQL_AST_CREATE_tables.sql
\. /usr/src/astguiclient/trunk/extras/first_server_install.sql
update servers set asterisk_version='13.29.2';
quit
MYSQLCREOF
read -p 'Press Enter to continue: '
echo 'Continuing...'
#Get astguiclient.conf file
echo "" > /etc/astguiclient.conf
wget -O /etc/astguiclient.conf https://raw.githubusercontent.com/jaganthoutam/vicidial-install-scripts/main/astguiclient.conf
echo "Replace IP address in Default"
echo "%%%%%%%%%Please Enter This Server IP ADD%%%%%%%%%%%%"
read serveripadd
sed -i 's/$serveripadd/'$serveripadd'/g' /etc/astguiclient.conf
echo "Install VICIDIAL"
echo "Copy sample configuration files to /etc/asterisk/ SET TO  Y*"
perl install.pl
#Secure Manager 
sed -i s/0.0.0.0/127.0.0.1/g /etc/asterisk/manager.conf
echo "Populate AREA CODES"
/usr/share/astguiclient/ADMIN_area_code_populate.pl
echo "Replace OLD IP. You need to Enter your Current IP here"
/usr/share/astguiclient/ADMIN_update_server_ip.pl --old-server_ip=10.10.10.15

#Install Crontab
wget -O /root/crontab-file https://raw.githubusercontent.com/jaganthoutam/vicidial-install-scripts/main/crontab
crontab /root/crontab-file
crontab -l

#Install rc.local
wget -O /etc/rc.local https://raw.githubusercontent.com/jaganthoutam/vicidial-install-scripts/main/rc.local
chmod +x /etc/rc.local
systemctl start rc-local
read -p 'Press Enter to Reboot: '
echo "Restarting Debian"
reboot
