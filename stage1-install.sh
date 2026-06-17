#!/bin/bash
# GenX VICIdial role-based installer for AlmaLinux/Rocky 9
# v1: PHP 8.2, MariaDB, Asterisk 18.21.0, DAHDI 3.4, ViciBox-style roles
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSET_DIR="$BASE_DIR/assets"
LOG=/var/log/genx-vicidial-stage1.log
exec > >(tee -a "$LOG") 2>&1

ASTERISK_VERSION="18.21.0"
DAHDI_VERSION="3.4.0+3.4.0"
LIBPRI_VERSION="1.6.1"
VICI_DB="asterisk"
VICI_USER="cron"
VICI_PASS="1234"
VICI_CUSTOM_USER="custom"
VICI_CUSTOM_PASS="custom1234"
REPO_DIR="/usr/src/new_vicidial"

need_root(){ [ "${EUID:-$(id -u)}" -eq 0 ] || { echo "Run as root."; exit 1; }; }
run(){ echo "+ $*"; "$@"; }
append_once(){ local file="$1" marker="$2"; shift 2; grep -Fq "$marker" "$file" 2>/dev/null || cat >> "$file"; }

need_root

if [ ! -f /root/.genx-vicidial-stage0-complete ]; then
  echo "WARNING: Stage 0 marker missing. Run ./stage0-prep.sh first and reboot before Stage 1."
  read -rp "Continue anyway? [y/N]: " c
  [[ "${c:-N}" =~ ^[Yy]$ ]] || exit 1
fi

prompt_default(){ local var="$1" text="$2" def="$3" input; read -rp "$text [$def]: " input; printf -v "$var" '%s' "${input:-$def}"; }
require_domain(){
  while true; do
    read -rp "Enter the public FQDN/domain for SSL/WebRTC, required: " DOMAINNAME
    DOMAINNAME="${DOMAINNAME,,}"
    if [[ "$DOMAINNAME" =~ ^[a-z0-9.-]+\.[a-z]{2,}$ ]]; then break; fi
    echo "A valid domain is required, example: dialer.example.com"
  done
}
select_timezone(){
  local current="$(cat /root/.genx-vicidial-timezone 2>/dev/null || echo America/New_York)"
  echo "Select server timezone:"
  echo "  1) Eastern  - America/New_York"
  echo "  2) Central  - America/Chicago"
  echo "  3) Mountain - America/Denver"
  echo "  4) Pacific  - America/Los_Angeles"
  read -rp "Timezone [current: $current, Enter to keep]: " tz_choice
  case "${tz_choice:-keep}" in
    keep) TZ="$current" ;;
    1) TZ="America/New_York" ;;
    2) TZ="America/Chicago" ;;
    3) TZ="America/Denver" ;;
    4) TZ="America/Los_Angeles" ;;
    *) TZ="$current" ;;
  esac
  timedatectl set-timezone "$TZ"
}

select_role(){
  echo
  echo "========================================="
  echo " GenX VICIdial Installer - Alma/Rocky 9"
  echo "========================================="
  echo "  1) Express Server        DB + Web + Telephony"
  echo "  2) Database Master"
  echo "  3) Database Replica"
  echo "  4) Web Server"
  echo "  5) Telephony Server"
  echo "  6) Archive Server"
  echo "  7) Web + Telephony"
  echo "  8) Database + Web"
  echo "  9) Custom"
  read -rp "Install mode [1]: " mode
  ROLE_DB=0; ROLE_DBS=0; ROLE_WEB=0; ROLE_TEL=0; ROLE_ARCHIVE=0
  case "${mode:-1}" in
    1) ROLE_DB=1; ROLE_WEB=1; ROLE_TEL=1 ;;
    2) ROLE_DB=1 ;;
    3) ROLE_DBS=1 ;;
    4) ROLE_WEB=1 ;;
    5) ROLE_TEL=1 ;;
    6) ROLE_ARCHIVE=1 ;;
    7) ROLE_WEB=1; ROLE_TEL=1 ;;
    8) ROLE_DB=1; ROLE_WEB=1 ;;
    9)
      read -rp "Database Master? [y/N]: " a; [[ "$a" =~ ^[Yy]$ ]] && ROLE_DB=1
      read -rp "Database Replica? [y/N]: " a; [[ "$a" =~ ^[Yy]$ ]] && ROLE_DBS=1
      read -rp "Web Server? [y/N]: " a; [[ "$a" =~ ^[Yy]$ ]] && ROLE_WEB=1
      read -rp "Telephony Server? [y/N]: " a; [[ "$a" =~ ^[Yy]$ ]] && ROLE_TEL=1
      read -rp "Archive Server? [y/N]: " a; [[ "$a" =~ ^[Yy]$ ]] && ROLE_ARCHIVE=1
      ;;
    *) ROLE_DB=1; ROLE_WEB=1; ROLE_TEL=1 ;;
  esac
  if [ "$ROLE_DBS" = 1 ] && [ "$ROLE_DB" = 1 ]; then echo "Choose DB master OR replica, not both."; exit 1; fi
}

collect_inputs(){
  default_hostname="$(hostname -f 2>/dev/null || hostname 2>/dev/null || echo localhost)"
  prompt_default HOSTNAME_FQDN "Enter server hostname/FQDN" "$default_hostname"
  hostnamectl set-hostname "$HOSTNAME_FQDN"
  LOCAL_IP="$(hostname -I | awk '{print $1}')"
  prompt_default LOCAL_IP "Detected local/server IP" "$LOCAL_IP"
  require_domain
  if [ "$ROLE_DBS" = 1 ] || { [ "$ROLE_WEB" = 1 ] && [ "$ROLE_DB" = 0 ]; } || { [ "$ROLE_TEL" = 1 ] && [ "$ROLE_DB" = 0 ]; }; then
    prompt_default DB_HOST "Database host/IP" "127.0.0.1"
  else
    DB_HOST="localhost"
  fi
  if [ "$ROLE_DB" = 1 ]; then
    prompt_default MYSQL_SERVER_ID "MariaDB server-id" "1"
  elif [ "$ROLE_DBS" = 1 ]; then
    prompt_default MYSQL_SERVER_ID "MariaDB replica server-id, must be unique" "2"
  fi
  if [ "$ROLE_ARCHIVE" = 1 ]; then
    prompt_default ARCHIVE_USER "Archive FTP user" "cronarchive"
    prompt_default ARCHIVE_PASS "Archive FTP password" "$(openssl rand -hex 8 2>/dev/null || echo cronarchive1234)"
    prompt_default ARCHIVE_PORT "Archive FTP port" "21"
    prompt_default ARCHIVE_DIR "Archive directory" "RECORDINGS"
    prompt_default ARCHIVE_URL "Archive URL" "https://$DOMAINNAME/RECORDINGS"
  fi
}

install_repos_and_packages(){
  run dnf -y install dnf-plugins-core yum-utils epel-release
  run dnf -y install https://rpms.remirepo.net/enterprise/remi-release-9.rpm
  run dnf -y module reset php
  run dnf -y module enable php:remi-8.2
  run dnf -y config-manager --set-enabled crb
  run dnf -y groupinstall "Development Tools"
  run dnf -y install wget curl git subversion tar gzip unzip zip make patch gcc gcc-c++ kernel-devel-$(uname -r) kernel-headers-$(uname -r) \
    perl perl-CPAN perl-YAML perl-libwww-perl perl-DBI perl-DBD-MySQL perl-GD perl-Env perl-Term-ReadLine-Gnu perl-SelfLoader perl-File-Which \
    httpd mod_ssl certbot python3-certbot-apache php php-cli php-devel php-gd php-curl php-mysqlnd php-ldap php-zip php-fileinfo php-opcache php-imap php-odbc php-pear php-xml php-mbstring \
    mariadb-server mariadb mariadb-devel libxml2-devel sqlite-devel libuuid-devel uuid-devel readline-devel ncurses-devel newt newt-devel slang-devel \
    libsrtp-devel elfutils-libelf-devel libedit-devel speex-devel sox sendmail lame-devel ImageMagick htop iftop atop mytop initscripts pv python3-pip firewalld ftp vsftpd bind-utils nano chkconfig postfix dovecot s-nail inxi rsync
  pip3 install mysql-connector-python || true
  dnf -y copr enable irontec/sngrep || true
  dnf -y install sngrep || true
}

configure_php(){
  cat > /etc/php.d/99-vicidial.ini <<PHPINI
; VICIdial Alma/Rocky 9 settings
error_reporting = E_ALL & ~E_NOTICE
memory_limit = 448M
short_open_tag = On
max_execution_time = 3330
max_input_time = 3360
post_max_size = 448M
upload_max_filesize = 442M
default_socket_timeout = 3360
date.timezone = $(timedatectl show -p Timezone --value)
max_input_vars = 50000
PHPINI
}

configure_mariadb(){
  [ "$ROLE_DB" = 1 ] || [ "$ROLE_DBS" = 1 ] || return 0
  systemctl enable mariadb

  # ViciBox-style MariaDB layout:
  #   /etc/my.cnf keeps only the include directory
  #   role tuning lives in /etc/my.cnf.d/*.cnf
  #   datadir is /srv/mysql/data, matching the ViciBox general.cnf
  cp -n /etc/my.cnf /etc/my.cnf.original 2>/dev/null || true
  cat > /etc/my.cnf <<'MYSQLCONF'
!includedir /etc/my.cnf.d
MYSQLCONF

  mkdir -p /etc/my.cnf.d/originals
  for f in /etc/my.cnf.d/mariadb-server.cnf /etc/my.cnf.d/server.cnf; do
    [ -f "$f" ] && mv -n "$f" /etc/my.cnf.d/originals/ || true
  done

  install -m 0644 "$ASSET_DIR/mysql/cache-buffers.cnf" /etc/my.cnf.d/cache-buffers.cnf
  install -m 0644 "$ASSET_DIR/mysql/general.cnf" /etc/my.cnf.d/general.cnf
  install -m 0644 "$ASSET_DIR/mysql/innodb.cnf" /etc/my.cnf.d/innodb.cnf
  install -m 0644 "$ASSET_DIR/mysql/README.txt" /etc/my.cnf.d/README.txt

  # replication.cnf is ViciBox's replica-oriented file, but its log_bin/relay/binlog settings
  # are useful for master readiness too. For masters/Express, keep the replicate filters disabled.
  if [ "$ROLE_DBS" = 1 ]; then
    install -m 0644 "$ASSET_DIR/mysql/replication.cnf" /etc/my.cnf.d/replication.cnf
    : ${MYSQL_SERVER_ID:=2}
  else
    sed -E 's/^(replicate[-_].*)/#\1/' "$ASSET_DIR/mysql/replication.cnf" > /etc/my.cnf.d/replication.cnf
    : ${MYSQL_SERVER_ID:=1}
  fi

  cat > /etc/my.cnf.d/99-genx-server-id.cnf <<MYSQLROLE
[mysqld]
server-id = ${MYSQL_SERVER_ID}
MYSQLROLE

  systemctl stop mariadb 2>/dev/null || true
  mkdir -p /srv/mysql/data /var/log/mysqld
  if [ -d /var/lib/mysql/mysql ] && [ ! -d /srv/mysql/data/mysql ]; then
    rsync -a /var/lib/mysql/ /srv/mysql/data/
  fi
  touch /srv/mysql/data/mysqld-slow.log
  chown -R mysql:mysql /srv/mysql /var/log/mysqld
  systemctl restart mariadb
}

install_asterisk_perl(){
  cd /usr/src
  if [ ! -d asterisk-perl-0.08 ]; then
    curl -L -o asterisk-perl-0.08.tar.gz https://cpan.metacpan.org/authors/id/J/JU/JUNKY/Asterisk-perl-0.08.tar.gz || curl -L -o asterisk-perl-0.08.tar.gz https://cpan.metacpan.org/authors/id/J/JU/JUNKY/asterisk-perl-0.08.tar.gz
    tar xzf asterisk-perl-0.08.tar.gz
  fi
  cd /usr/src/asterisk-perl-0.08
  perl Makefile.PL && make all && make install
}

install_lame_jansson_srtp(){
  cd /usr/src
  if [ ! -d lame-3.99.5 ]; then
    curl -L -o lame-3.99.5.tar.gz https://downloads.sourceforge.net/project/lame/lame/3.99/lame-3.99.5.tar.gz
    tar xzf lame-3.99.5.tar.gz
  fi
  cd /usr/src/lame-3.99.5 && ./configure && make && make install
  cd /usr/src
  if [ ! -d jansson-2.13 ]; then
    curl -L -o jansson-2.13.tar.gz https://digip.org/jansson/releases/jansson-2.13.tar.gz
    tar xzf jansson-2.13.tar.gz
  fi
  cd /usr/src/jansson-2.13 && ./configure && make clean && make && make install && ldconfig
  cd /usr/src
  if [ ! -d libsrtp-2.1.0 ]; then
    curl -L -o libsrtp-2.1.0.tar.gz https://github.com/cisco/libsrtp/archive/v2.1.0.tar.gz
    tar xzf libsrtp-2.1.0.tar.gz
  fi
  cd /usr/src/libsrtp-2.1.0 && ./configure --prefix=/usr --enable-openssl && make shared_library && make install && ldconfig
}

install_dahdi(){
  [ "$ROLE_TEL" = 1 ] || return 0
  ln -sf /usr/lib/modules/$(uname -r)/vmlinux.xz /boot/ || true
  cd /usr/src
  if [ ! -f dahdi-linux-complete-${DAHDI_VERSION}.tar.gz ]; then
    curl -L -o dahdi-linux-complete-${DAHDI_VERSION}.tar.gz https://downloads.asterisk.org/pub/telephony/dahdi-linux-complete/dahdi-linux-complete-${DAHDI_VERSION}.tar.gz
  fi
  rm -rf dahdi-linux-complete-${DAHDI_VERSION}
  tar xzf dahdi-linux-complete-${DAHDI_VERSION}.tar.gz
  cd dahdi-linux-complete-${DAHDI_VERSION}

  # Alma/Rocky 9.5+ DAHDI 3.4 kernel compatibility patches, no external dahdi-9.5-fix.zip
  grep -rl 'DEFINE_SEMAPHORE(' linux/ | xargs -r sed -i 's/DEFINE_SEMAPHORE(\([a-zA-Z0-9_]\+\))/DEFINE_SEMAPHORE(\1, 1)/g'
  grep -rl 'from_timer' linux/drivers/dahdi | xargs -r sed -i 's/from_timer(\([^,]*\), \([^,]*\), \([^)]*\))/timer_container_of(\1, \2, \3)/g'
  sed -i 's|static int astribank_uevent(struct device \*dev, struct kobj_uevent_env \*kenv)|static int astribank_uevent(const struct device *dev, struct kobj_uevent_env *kenv)|' linux/drivers/dahdi/xpp/xbus-sysfs.c || true
  sed -i 's|static int span_uevent(struct device \*dev, struct kobj_uevent_env \*kenv)|static int span_uevent(const struct device *dev, struct kobj_uevent_env *kenv)|' linux/drivers/dahdi/dahdi-sysfs.c || true
  sed -i 's|static int device_uevent(struct device \*dev, struct kobj_uevent_env \*kenv)|static int device_uevent(const struct device *dev, struct kobj_uevent_env *kenv)|' linux/drivers/dahdi/dahdi-sysfs.c || true
  grep -rl "static int .*_match(struct device \*dev, struct device_driver \*driver)" linux/drivers/dahdi | xargs -r sed -i 's|\(static int [a-zA-Z0-9_]*_match(struct device \*dev, \)struct device_driver \*driver)|\1const struct device_driver *driver)|g'
  sed -i 's/class_create(THIS_MODULE, "dahdi")/class_create("dahdi")/' linux/drivers/dahdi/dahdi-sysfs-chan.c || true

  make clean
  make all
  make install
  make install-config
  ldconfig
  cd tools
  make clean && make && make install && make install-config
  ldconfig
  mkdir -p /etc/dahdi
  touch /etc/dahdi/assigned-spans.conf
  [ -f /etc/dahdi/system.conf.sample ] && cp -f /etc/dahdi/system.conf.sample /etc/dahdi/system.conf
  modprobe dahdi || true
  modprobe dahdi_dummy || true
  /usr/sbin/dahdi_cfg -vvvvvvvvvvvvv || true
  systemctl enable dahdi || true
  systemctl restart dahdi || service dahdi start || true
}

install_asterisk(){
  [ "$ROLE_TEL" = 1 ] || return 0
  install_lame_jansson_srtp
  mkdir -p /usr/src/asterisk
  cd /usr/src/asterisk
  [ -f libpri-${LIBPRI_VERSION}.tar.gz ] || curl -L -O https://downloads.asterisk.org/pub/telephony/libpri/libpri-${LIBPRI_VERSION}.tar.gz
  [ -f asterisk-${ASTERISK_VERSION}.tar.gz ] || curl -L -O https://downloads.asterisk.org/pub/telephony/asterisk/old-releases/asterisk-${ASTERISK_VERSION}.tar.gz
  rm -rf libpri-${LIBPRI_VERSION} asterisk-${ASTERISK_VERSION}
  tar xzf libpri-${LIBPRI_VERSION}.tar.gz
  tar xzf asterisk-${ASTERISK_VERSION}.tar.gz
  cd libpri-${LIBPRI_VERSION} && make && make install
  cd /usr/src/asterisk/asterisk-${ASTERISK_VERSION}
  ./configure --libdir=/usr/lib64 --with-gsm=internal --enable-opus --enable-srtp --with-ssl --enable-asteriskssl --with-pjproject-bundled --with-jansson-bundled
  make menuselect/menuselect menuselect-tree menuselect.makeopts
  menuselect/menuselect --enable app_meetme menuselect.makeopts || true
  menuselect/menuselect --enable res_http_websocket menuselect.makeopts || true
  menuselect/menuselect --enable res_srtp menuselect.makeopts || true
  make samples
  sed -i 's|noload = chan_sip.so|;noload = chan_sip.so|g' /etc/asterisk/modules.conf || true
  local jobs=$(( $(nproc) + $(nproc) / 2 ))
  make -j "$jobs" all
  make install
  make config || true
  ldconfig
}

checkout_vicidial(){
  mkdir -p /usr/src/astguiclient
  cd /usr/src/astguiclient
  if [ -d trunk/.svn ]; then svn update trunk; else rm -rf trunk; svn checkout svn://svn.eflo.net/agc_2-X/trunk trunk; fi
}

create_db_and_users(){
  [ "$ROLE_DB" = 1 ] || return 0
  mysql --force -u root <<MYSQL
CREATE DATABASE IF NOT EXISTS $VICI_DB DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;
CREATE USER IF NOT EXISTS '$VICI_USER'@'localhost' IDENTIFIED BY '$VICI_PASS';
CREATE USER IF NOT EXISTS '$VICI_USER'@'%' IDENTIFIED BY '$VICI_PASS';
GRANT SELECT,CREATE,ALTER,INSERT,UPDATE,DELETE,LOCK TABLES on $VICI_DB.* TO '$VICI_USER'@'%';
GRANT SELECT,CREATE,ALTER,INSERT,UPDATE,DELETE,LOCK TABLES on $VICI_DB.* TO '$VICI_USER'@'localhost';
GRANT RELOAD ON *.* TO '$VICI_USER'@'%';
GRANT RELOAD ON *.* TO '$VICI_USER'@'localhost';
CREATE USER IF NOT EXISTS '$VICI_CUSTOM_USER'@'localhost' IDENTIFIED BY '$VICI_CUSTOM_PASS';
CREATE USER IF NOT EXISTS '$VICI_CUSTOM_USER'@'%' IDENTIFIED BY '$VICI_CUSTOM_PASS';
GRANT SELECT,CREATE,ALTER,INSERT,UPDATE,DELETE,LOCK TABLES on $VICI_DB.* TO '$VICI_CUSTOM_USER'@'%';
GRANT SELECT,CREATE,ALTER,INSERT,UPDATE,DELETE,LOCK TABLES on $VICI_DB.* TO '$VICI_CUSTOM_USER'@'localhost';
GRANT RELOAD ON *.* TO '$VICI_CUSTOM_USER'@'%';
GRANT RELOAD ON *.* TO '$VICI_CUSTOM_USER'@'localhost';
FLUSH PRIVILEGES;
SET GLOBAL connect_timeout=60;
USE $VICI_DB;
\. /usr/src/astguiclient/trunk/extras/MySQL_AST_CREATE_tables.sql
\. /usr/src/astguiclient/trunk/extras/first_server_install.sql
UPDATE servers SET asterisk_version='18.21.0' WHERE server_ip='10.10.10.15' OR server_id='server';
CREATE TABLE IF NOT EXISTS vicibox (
  server_id tinyint(3) unsigned NOT NULL AUTO_INCREMENT,
  server varchar(32) NOT NULL,
  server_ip varchar(64) NOT NULL,
  server_type enum('Database','Web','Telephony','Archive') NOT NULL DEFAULT 'Telephony',
  field1 varchar(64) DEFAULT NULL, field2 varchar(64) DEFAULT NULL, field3 varchar(64) DEFAULT NULL,
  field4 varchar(64) DEFAULT NULL, field5 varchar(64) DEFAULT NULL, field6 varchar(64) DEFAULT NULL,
  field7 varchar(64) DEFAULT NULL, field8 varchar(64) DEFAULT NULL, field9 varchar(64) DEFAULT NULL,
  PRIMARY KEY (server_id)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
REPLACE INTO vicibox (server_id,server,server_ip,server_type,field1,field2,field3,field4,field5,field6,field7,field8,field9)
VALUES (1,'$HOSTNAME_FQDN','$LOCAL_IP','Database','0','$VICI_DB','trunk','$VICI_USER','$VICI_PASS','$VICI_CUSTOM_USER','$VICI_CUSTOM_PASS','slave','slave1234');
MYSQL
}

write_astguiclient_conf(){
  cat > /etc/astguiclient.conf <<ASTGUI
PATHhome => /usr/share/astguiclient
PATHlogs => /var/log/astguiclient
PATHagi => /var/lib/asterisk/agi-bin
PATHweb => /var/www/html
PATHsounds => /var/lib/asterisk/sounds
PATHmonitor => /var/spool/asterisk/monitor
PATHDONEmonitor => /var/spool/asterisk/monitorDONE
VARserver_ip => $LOCAL_IP
VARDB_server => $DB_HOST
VARDB_database => $VICI_DB
VARDB_user => $VICI_USER
VARDB_pass => $VICI_PASS
VARDB_custom_user => $VICI_CUSTOM_USER
VARDB_custom_pass => $VICI_CUSTOM_PASS
VARDB_port => 3306
VARactive_keepalives => $( [ "$ROLE_TEL" = 1 ] && echo 123456789ECS || echo X )
VARasterisk_version => 18.X
VARFTP_host => $LOCAL_IP
VARFTP_user => ${ARCHIVE_USER:-cronarchive}
VARFTP_pass => ${ARCHIVE_PASS:-archivepass}
VARFTP_port => ${ARCHIVE_PORT:-21}
VARFTP_dir => ${ARCHIVE_DIR:-RECORDINGS}
VARHTTP_path => ${ARCHIVE_URL:-https://$DOMAINNAME/RECORDINGS}
VARREPORT_host => $LOCAL_IP
VARREPORT_user => ${ARCHIVE_USER:-cronarchive}
VARREPORT_pass => ${ARCHIVE_PASS:-archivepass}
VARREPORT_port => ${ARCHIVE_PORT:-21}
VARREPORT_dir => REPORTS
VARfastagi_log_min_servers => 3
VARfastagi_log_max_servers => 16
VARfastagi_log_min_spare_servers => 2
VARfastagi_log_max_spare_servers => 8
VARfastagi_log_max_requests => 1000
VARfastagi_log_checkfordead => 30
VARfastagi_log_checkforwait => 60
ExpectedDBSchema => 1720
ASTGUI
}

install_vicidial(){
  [ "$ROLE_WEB" = 1 ] || [ "$ROLE_TEL" = 1 ] || [ "$ROLE_DB" = 1 ] || return 0
  checkout_vicidial
  [ "$ROLE_DB" = 1 ] && create_db_and_users
  write_astguiclient_conf
  cd /usr/src/astguiclient/trunk
  perl install.pl --no-prompt --copy_sample_conf_files=Y
  perl install.pl --no-prompt || true
  /usr/share/astguiclient/ADMIN_update_server_ip.pl --old-server_ip=10.10.10.15 --server_ip="$LOCAL_IP" --auto || true
  /usr/share/astguiclient/ADMIN_area_code_populate.pl || true
}

configure_ssl_webrtc(){
  [ "$ROLE_WEB" = 1 ] || [ "$ROLE_TEL" = 1 ] || return 0
  systemctl enable --now httpd
  cat > /etc/httpd/conf.d/${DOMAINNAME}.conf <<HTTPD
<VirtualHost *:80>
    ServerName ${DOMAINNAME}
    DocumentRoot /var/www/html
    ErrorLog logs/${DOMAINNAME}-error_log
    CustomLog logs/${DOMAINNAME}-access_log combined
</VirtualHost>
HTTPD
  certbot --apache -d "$DOMAINNAME"
  cat > /etc/asterisk/http.conf <<HTTP
[general]
enabled=yes
bindaddr=0.0.0.0
bindport=8088
tlsenable=yes
tlsbindaddr=0.0.0.0:8089
tlscertfile=/etc/letsencrypt/live/${DOMAINNAME}/cert.pem
tlsprivatekey=/etc/letsencrypt/live/${DOMAINNAME}/privkey.pem
HTTP
  sed -i "s|;externip = 192.168.1.1|externip = $LOCAL_IP|" /etc/asterisk/sip.conf 2>/dev/null || true
  mysql -u root <<MYSQL || true
USE $VICI_DB;
UPDATE servers SET web_socket_url='wss://${DOMAINNAME}:8089/ws', recording_web_link='ALT_IP', alt_server_ip='${DOMAINNAME}', conf_engine='CONFBRIDGE' WHERE server_ip='$LOCAL_IP';
UPDATE system_settings SET webphone_url='https://phone.viciphone.com/viciphone.php', sounds_web_server='https://${DOMAINNAME}';
UPDATE vicidial_conf_templates SET template_contents='type=friend
host=dynamic
context=default
trustrpid=yes
sendrpid=no
qualify=yes
qualifyfreq=600
transport=ws,wss,udp
encryption=yes
avpf=yes
icesupport=yes
rtcp_mux=yes
directmedia=no
disallow=all
allow=ulaw,opus,vp8,h264
nat=yes
dtlsenable=yes
dtlsverify=no
dtlscertfile=/etc/letsencrypt/live/${DOMAINNAME}/cert.pem
dtlsprivatekey=/etc/letsencrypt/live/${DOMAINNAME}/privkey.pem
dtlssetup=actpass' WHERE template_id='SIP_generic';
ALTER TABLE phones MODIFY COLUMN is_webphone ENUM('Y','N','Y_API_LAUNCH') default 'Y';
UPDATE phones SET template_id='SIP_generic';
MYSQL
  rasterisk -x reload || true
}

install_dynportal_firewall(){
  [ "$ROLE_WEB" = 1 ] || [ "$ROLE_ARCHIVE" = 1 ] || return 0
  systemctl enable --now firewalld
  mkdir -p /var/www/vhosts
  cp -a "$ASSET_DIR/dynportal" /var/www/vhosts/dynportal
  chown -R apache:apache /var/www/vhosts/dynportal
  chmod -R 755 /var/www/vhosts/dynportal
  cp -a "$ASSET_DIR/vicibox-firewall" /usr/share/vicibox-firewall
  install -m 755 "$ASSET_DIR/vicibox-firewall/VB-firewall.pl" /usr/bin/VB-firewall
  install -m 755 "$ASSET_DIR/vicibox-firewall/ipset-geoblock" /usr/bin/ipset-geoblock || true
  [ -f "$ASSET_DIR/vicibox-geoblock.conf" ] && cp -f "$ASSET_DIR/vicibox-geoblock.conf" /etc/vicibox-geoblock.conf
  cat > /etc/httpd/conf.d/viciportal.conf <<PORTAL
Listen 446
<VirtualHost *:446>
    ServerName ${DOMAINNAME}
    DocumentRoot /var/www/vhosts/dynportal
    <Directory /var/www/vhosts/dynportal>
        Options FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>
</VirtualHost>
PORTAL
  if [ -f /var/www/vhosts/dynportal/inc/defaults.inc.php ]; then
    sed -i "s|/etc/astguiclient.conf|/etc/astguiclient.conf|g" /var/www/vhosts/dynportal/inc/defaults.inc.php || true
  fi
  firewall-cmd --permanent --add-port=446/tcp || true
  firewall-cmd --permanent --add-port=10000-20000/udp || true
  firewall-cmd --permanent --add-service=http || true
  firewall-cmd --permanent --add-service=https || true
  firewall-cmd --reload || true
  systemctl restart httpd
}

configure_archive_role(){
  [ "$ROLE_ARCHIVE" = 1 ] || return 0
  systemctl enable --now vsftpd httpd
  mkdir -p "/var/spool/asterisk/monitorDONE/${ARCHIVE_DIR:-RECORDINGS}"
  useradd -r -d /var/spool/asterisk/monitorDONE -s /sbin/nologin "${ARCHIVE_USER:-cronarchive}" 2>/dev/null || true
  echo "${ARCHIVE_USER:-cronarchive}:${ARCHIVE_PASS:-archivepass}" | chpasswd || true
}

install_sounds(){
  [ "$ROLE_TEL" = 1 ] || return 0
  mkdir -p /var/lib/asterisk/sounds /var/lib/asterisk/mohmp3 /var/lib/asterisk/quiet-mp3
  cd /usr/src
  for f in asterisk-core-sounds-en-ulaw-current.tar.gz asterisk-core-sounds-en-wav-current.tar.gz asterisk-core-sounds-en-gsm-current.tar.gz asterisk-extra-sounds-en-ulaw-current.tar.gz asterisk-extra-sounds-en-wav-current.tar.gz asterisk-extra-sounds-en-gsm-current.tar.gz asterisk-moh-opsound-gsm-current.tar.gz asterisk-moh-opsound-ulaw-current.tar.gz asterisk-moh-opsound-wav-current.tar.gz; do
    [ -f "$f" ] || curl -L -O "http://downloads.asterisk.org/pub/telephony/sounds/$f"
  done
  cd /var/lib/asterisk/sounds
  tar -zxf /usr/src/asterisk-core-sounds-en-gsm-current.tar.gz
  tar -zxf /usr/src/asterisk-core-sounds-en-ulaw-current.tar.gz
  tar -zxf /usr/src/asterisk-core-sounds-en-wav-current.tar.gz
  tar -zxf /usr/src/asterisk-extra-sounds-en-gsm-current.tar.gz
  tar -zxf /usr/src/asterisk-extra-sounds-en-ulaw-current.tar.gz
  tar -zxf /usr/src/asterisk-extra-sounds-en-wav-current.tar.gz
  ln -sfn /var/lib/asterisk/mohmp3 /var/lib/asterisk/default
  cd /var/lib/asterisk/mohmp3
  tar -zxf /usr/src/asterisk-moh-opsound-gsm-current.tar.gz
  tar -zxf /usr/src/asterisk-moh-opsound-ulaw-current.tar.gz
  tar -zxf /usr/src/asterisk-moh-opsound-wav-current.tar.gz
  find /var/lib/asterisk -name 'CHANGES*' -o -name 'LICENSE*' -o -name 'CREDITS*' | xargs -r rm -f
}

configure_cron_rc(){
  cat > /root/crontab-file <<CRON
* 1 * * * /usr/share/astguiclient/ADMIN_audio_store_sync.pl --upload --quiet
0 2 * * * /usr/share/astguiclient/ADMIN_backup.pl
@weekly certbot renew --quiet
0,3,6,9,12,15,18,21,24,27,30,33,36,39,42,45,48,51,54,57 * * * * /usr/share/astguiclient/AST_CRON_audio_1_move_mix.pl --MIX
0,3,6,9,12,15,18,21,24,27,30,33,36,39,42,45,48,51,54,57 * * * * /usr/share/astguiclient/AST_CRON_audio_1_move_VDonly.pl
1,4,7,10,13,16,19,22,25,28,31,34,37,40,43,46,49,52,55,58 * * * * /usr/share/astguiclient/AST_CRON_audio_2_compress.pl --MP3 --HTTPS
* * * * * /usr/share/astguiclient/ADMIN_keepalive_ALL.pl --cu3way
* * * * * /usr/share/astguiclient/AST_manager_kill_hung_congested.pl
* * * * * /usr/share/astguiclient/AST_vm_update.pl
* * * * * /usr/share/astguiclient/AST_conf_update.pl --no-vc-3way-check
11 * * * * /usr/share/astguiclient/AST_flush_DBqueue.pl -q
33 * * * * /usr/share/astguiclient/AST_cleanup_agent_log.pl
50 0 * * * /usr/share/astguiclient/AST_cleanup_agent_log.pl --last-24hours
* * * * * /usr/share/astguiclient/AST_VDhopper.pl -q
1 1,7 * * * /usr/share/astguiclient/ADMIN_adjust_GMTnow_on_leads.pl --debug
2 1 * * * /usr/share/astguiclient/AST_reset_mysql_vars.pl
3 1 * * * /usr/share/astguiclient/AST_DB_optimize.pl
2 0 * * 0 /usr/share/astguiclient/AST_agent_week.pl
22 0 * * * /usr/share/astguiclient/AST_agent_day.pl
24 1 * * * /usr/bin/find /var/spool/asterisk/monitorDONE/ORIG -maxdepth 2 -type f -mtime +1 -print | xargs rm -f
30 1 1 * * /usr/share/astguiclient/ADMIN_archive_log_tables.pl --DAYS=45
28 0 * * * /usr/bin/find /var/log/astguiclient -maxdepth 1 -type f -mtime +2 -print | xargs rm -f
29 0 * * * /usr/bin/find /var/log/asterisk -maxdepth 3 -type f -mtime +2 -print | xargs rm -f
25 0 * * * /usr/share/astguiclient/AST_DB_dead_cb_purge.pl --purge-non-cb -q
1 7 * * * /usr/share/astguiclient/AST_dialer_inventory_snapshot.pl -q
* * * * * /usr/share/astguiclient/AST_inbound_email_parser.pl
@reboot /usr/bin/VB-firewall --whitelist=ViciWhite --dynamic --quiet
* * * * * /usr/bin/VB-firewall --whitelist=ViciWhite --dynamic --quiet
* * * * * sleep 10; /usr/bin/VB-firewall --white --dynamic --quiet
* * * * * sleep 20; /usr/bin/VB-firewall --white --dynamic --quiet
* * * * * sleep 30; /usr/bin/VB-firewall --white --dynamic --quiet
* * * * * sleep 40; /usr/bin/VB-firewall --white --dynamic --quiet
* * * * * sleep 50; /usr/bin/VB-firewall --white --dynamic --quiet
30 23 * * * /usr/share/astguiclient/ADMIN_archive_log_tables.pl --url-log-only --url-log-days=30
CRON
  crontab /root/crontab-file || true
  cat > /etc/rc.d/rc.local <<'RC'
#!/bin/bash
/usr/share/astguiclient/ip_relay/relay_control start 2>/dev/null 1>&2 || true
/usr/bin/setterm -blank 2>/dev/null || true
/usr/bin/setterm -powersave off 2>/dev/null || true
/usr/bin/setterm -powerdown 2>/dev/null || true
systemctl start mariadb.service || true
systemctl start httpd.service || true
/usr/share/astguiclient/ADMIN_restart_roll_logs.pl || true
/usr/share/astguiclient/AST_reset_mysql_vars.pl || true
modprobe dahdi || true
modprobe dahdi_dummy || true
/usr/sbin/dahdi_cfg -vvvvvvvvvvvvv || true
sleep 20
/usr/share/astguiclient/start_asterisk_boot.pl || true
exit 0
RC
  chmod +x /etc/rc.d/rc.local
  cat > /etc/systemd/system/rc-local.service <<'UNIT'
[Unit]
Description=/etc/rc.local Compatibility
ConditionPathExists=/etc/rc.d/rc.local
[Service]
Type=oneshot
ExecStart=/etc/rc.d/rc.local
TimeoutSec=0
StandardInput=tty
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
UNIT
  systemctl daemon-reload
  systemctl enable rc-local.service
}

final_tuning(){
  systemctl enable --now sendmail || true
  systemctl enable --now httpd || true
  [ "$ROLE_DB" = 1 ] && systemctl enable --now mariadb || true
  systemctl enable certbot-renew.timer || true
  systemctl start certbot-renew.timer || true
  grep -q '^DefaultLimitNOFILE=65536' /etc/systemd/system.conf || echo 'DefaultLimitNOFILE=65536' >> /etc/systemd/system.conf
  append_once /etc/httpd/conf/httpd.conf "# BEGIN VICIDIAL RECORDINGS ALIAS" <<'REC'

# BEGIN VICIDIAL RECORDINGS ALIAS
CustomLog /dev/null common
Alias /RECORDINGS/MP3 "/var/spool/asterisk/monitorDONE/MP3/"
<Directory "/var/spool/asterisk/monitorDONE/MP3/">
    Options Indexes MultiViews
    AllowOverride None
    Require all granted
</Directory>
Timeout 600
# END VICIDIAL RECORDINGS ALIAS
REC
  mkdir -p /var/spool/asterisk/monitorDONE/MP3
  chown -R apache:apache /var/spool/asterisk/ || true
  find /var/spool/asterisk -type d -exec chmod 775 {} \; || true
  find /var/spool/asterisk -type f -exec chmod 664 {} \; || true
  systemctl restart httpd || true
}

main(){
  select_timezone
  select_role
  collect_inputs
  echo "Installing roles: DB=$ROLE_DB DBS=$ROLE_DBS WEB=$ROLE_WEB TEL=$ROLE_TEL ARCHIVE=$ROLE_ARCHIVE"
  install_repos_and_packages
  configure_php
  configure_mariadb
  install_asterisk_perl
  install_dahdi
  install_asterisk
  install_vicidial
  install_sounds
  install_dynportal_firewall
  configure_archive_role
  configure_ssl_webrtc
  configure_cron_rc
  final_tuning
  echo
  echo "Stage 1 complete. Review $LOG. Reboot recommended."
  read -rp "Reboot now? [Y/n]: " ans
  [[ "${ans:-Y}" =~ ^[Yy]$ ]] && reboot
}
main "$@"
