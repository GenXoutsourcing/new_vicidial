#!/bin/sh

echo "Reinstall packages needed for ViciDial"

yum groupinstall "Development Tools" -y

yum -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-8.noarch.rpm
yum -y install yum-utils
dnf install https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm -y
dnf install https://rpms.remirepo.net/enterprise/remi-release-9.rpm -y
dnf module enable php:remi-7.4 -y
dnf module enable mariadb:10.5 -y

dnf -y install dnf-plugins-core

yum install -y php screen php-mcrypt subversion php-cli php-gd php-curl php-mysql php-ldap php-zip php-fileinfo php-opcache -y 
sleep 2
yum in -y wget unzip make patch gcc gcc-c++ subversion php php-devel php-gd gd-devel readline-devel php-mbstring php-mcrypt 
sleep 2
yum in -y php-imap php-ldap php-mysqli php-odbc php-pear php-xml php-xmlrpc curl curl-devel perl-libwww-perl ImageMagick 
sleep 3
yum in -y newt-devel libxml2-devel kernel-devel sqlite-devel libuuid-devel sox sendmail lame-devel htop iftop perl-File-Which
sleep 2
yum in -y php-opcache libss7 mariadb-devel libss7* libopen*
sleep 1
yum in -y initscripts
yum copr enable irontec/sngrep -y
dnf install sngrep -y


dnf --enablerepo=crb install libsrtp-devel -y
dnf config-manager --set-enabled crb
yum install libsrtp-devel -y

yum in -y sqlite-devel httpd mod_ssl nano chkconfig htop atop mytop iftop
yum in -y libedit-devel uuid* libxml2* speex-devel speex* postfix dovecot s-nail roundcubemail inxi
dnf install -y mariadb-server mariadb

dnf -y install dnf-plugins-core
dnf config-manager --set-enabled powertools

yum install -y perl-CPAN perl-YAML perl-CPAN-DistnameInfo perl-libwww-perl perl-DBI perl-DBD-MySQL perl-GD perl-Env perl-Term-ReadLine-Gnu perl-SelfLoader perl-open.noarch 

#CPM install
cd /usr/src/vicidial-install-scripts
curl -fsSL https://raw.githubusercontent.com/skaji/cpm/main/cpm | perl - install -g App::cpm
/usr/local/bin/cpm install -g

yum install libsrtp-devel -y
yum install -y elfutils-libelf-devel libedit-devel

yum in newt* -y

yum in libuuid-devel libxml2-devel -y

