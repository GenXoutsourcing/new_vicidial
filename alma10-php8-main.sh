#!/bin/bash
# AlmaLinux 10 VICIdial combined one-pass test installer
# Includes OS prep, repo setup, new_vicidial clone, Asterisk 18.21.0-vici,
# DAHDI 3.4.0 core-only build, Dynportal, VB-firewall, custom confbridge, WebRTC helper.
# No reboot is required between prep and install because kernel updates are excluded before DAHDI.
# TEST SCRIPT - run first on a disposable/snapshot server.
# Updated with validated AlmaLinux 10 fixes: PHP 8.3, DAHDI 3.4.0 core-only,
# perl-DBD-MySQL RPM, Net::Telnet CPAN, full VICIdial crontab, rc.local boot startup,
# Dynportal/VB-firewall, ConfBridge post-keepalive fix, and custom firewall rules.

set -Eeuo pipefail

trap 'echo "ERROR on line $LINENO. Last command: $BASH_COMMAND" >&2' ERR

echo "VICIdial AlmaLinux 10 test installer"
echo "**************************************************************************"

prompt() {
    local varname="$1"
    local prompt_text="$2"
    local default_value="${3:-}"
    local input=""
    read -r -p "$prompt_text [$default_value]: " input
    export "$varname=${input:-$default_value}"
}

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        echo "Run this script as root."
        exit 1
    fi
}

pause_continue() {
    echo
    if [[ "${AUTO_CONTINUE:-1}" == "1" ]]; then
        return 0
    fi
    read -r -p "Press Enter to continue..."
}

download_file() {
    local url="$1"
    local out="$2"
    echo "Downloading: $url"
    curl -fL --retry 3 --retry-delay 5 -o "$out" "$url"
}

require_root
export LC_ALL=C
export AUTO_CONTINUE="${AUTO_CONTINUE:-1}"

# ---------------------------------------------------------------------------
# One-pass OS prep - no reboot before DAHDI
# ---------------------------------------------------------------------------
echo "Running AlmaLinux 10 OS prep"

dnf install -y glibc-langpack-en dnf-plugins-core git curl wget nano tar unzip || true

localectl set-locale LANG=en_US.UTF-8 || true
timedatectl set-timezone America/New_York || true

# Disable SELinux immediately and persistently.
sed -i 's/^SELINUX=.*/SELINUX=disabled/g' /etc/selinux/config || true
setenforce 0 || true

dnf clean all
dnf makecache || true

# Important: do not update the kernel before DAHDI builds.
# DAHDI must build against the currently running kernel from uname -r.
dnf update -y --exclude=kernel* --exclude=kernel-core* --exclude=kernel-modules* --exclude=kernel-devel* --exclude=kernel-headers* || true

dnf config-manager --set-enabled crb || true
dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-10.noarch.rpm || true
dnf makecache || true
dnf update -y --exclude=kernel* --exclude=kernel-core* --exclude=kernel-modules* --exclude=kernel-devel* --exclude=kernel-headers* || true

cd /usr/src/
rm -rf new_vicidial
git clone https://github.com/GenXoutsourcing/new_vicidial

DEFAULT_HOSTNAME="$(hostname -f 2>/dev/null || hostname || true)"
prompt SERVER_HOSTNAME "Enter the hostname" "$DEFAULT_HOSTNAME"
hostnamectl set-hostname "$SERVER_HOSTNAME"

SERVER_HOSTNAME="$(hostname | awk '{print $1}')"
SERVER_IP="$(hostname -I | awk '{print $1}')"

echo "Hostname: $SERVER_HOSTNAME"
echo "IP Address: $SERVER_IP"
echo "**************************************************************************"
pause_continue

# ---------------------------------------------------------------------------
# URLs
# ---------------------------------------------------------------------------
ASTERISK_URL="https://download.vicidial.com/required-apps/asterisk-18.21.0-vici.tar.gz"
LIBPRI_URL="https://downloads.asterisk.org/pub/telephony/libpri/libpri-1.6.1.tar.gz"
DAHDI_VERSION="3.4.0"
DAHDI_URL="https://downloads.asterisk.org/pub/telephony/dahdi-linux-complete/dahdi-linux-complete-${DAHDI_VERSION}+${DAHDI_VERSION}.tar.gz"
JANSSON_URL="https://digip.org/jansson/releases/jansson-2.13.tar.gz"
LAME_URL="https://downloads.sourceforge.net/project/lame/lame/3.99/lame-3.99.5.tar.gz"
LIBSRTP_URL="https://github.com/cisco/libsrtp/archive/v2.1.0.tar.gz"

# Custom/private assets. Replace these later if you move them to a different host.
CUSTOM_BASE_URL="https://dialer.demo.genxcontactcenter.com"
DYNPORTAL_URL="${CUSTOM_BASE_URL}/dynportal.zip"
FIREWALL_ZIP_URL="${CUSTOM_BASE_URL}/firewall.zip"
AGGREGATE_URL="${CUSTOM_BASE_URL}/aggregate"
VB_FIREWALL_URL="${CUSTOM_BASE_URL}/VB-firewall"

# Optional custom files expected under /usr/src/new_vicidial:
# - certbot.sh
# - vicidial-enable-webrtc.sh
# - extensions.conf
# - confbridge-vicidial.conf

# ---------------------------------------------------------------------------
# Repositories and base packages
# ---------------------------------------------------------------------------
echo "Installing repositories and base packages"

dnf -y install dnf-plugins-core yum-utils curl wget tar unzip nano screen rsync git
dnf -y groupinstall "Development Tools" || dnf -y group install "Development Tools"

# AlmaLinux 10 repos: CRB may already exist; enable if available.
dnf config-manager --set-enabled crb || true

# EPEL for EL10, if available.
dnf -y install "https://dl.fedoraproject.org/pub/epel/epel-release-latest-10.noarch.rpm" || true

dnf -y makecache

# PHP 8.3 is expected on EL10. Do not force Remi here.
# Removed unavailable EL10 packages: php-imap, php-xmlrpc, php-mcrypt, python3-pip, sngrep, inxi.
dnf -y install \
php php-cli php-common php-devel php-gd php-curl php-mysqlnd \
php-ldap php-zip php-fileinfo php-opcache php-mbstring \
php-odbc php-pear php-xml \
httpd httpd-tools mod_ssl mariadb-server mariadb mariadb-devel \
kernel-devel-"$(uname -r)" kernel-headers-"$(uname -r)" elfutils-libelf-devel \
wget unzip make patch gcc gcc-c++ subversion gd-devel readline-devel \
curl-devel perl-libwww-perl ImageMagick newt-devel libxml2-devel \
sqlite-devel libuuid-devel sox sendmail lame-devel htop iftop atop mytop \
perl-File-Which initscripts pv bind-utils firewalld \
speex-devel postfix dovecot s-nail roundcubemail \
libedit-devel uuid-devel openssl-devel ncurses-devel libtermcap-devel \
perl-CPAN perl-YAML perl-CPAN-DistnameInfo perl-DBI perl-DBD-MySQL perl-DBD-MariaDB \
perl-devel perl-ExtUtils-MakeMaker perl-GD perl-Env perl-Term-ReadLine-Gnu \
perl-SelfLoader perl-open.noarch

echo "Installing Python pip safely from a valid working directory"
cd /root
python3 -m pip --version || true
python3 -m ensurepip --upgrade || true
python3 -m pip install --upgrade pip || true
python3 -m pip install mysql-connector-python || true

echo "Installing Net::Telnet from CPAN; no EL10 RPM package exists"
PERL_MM_USE_DEFAULT=1 cpan -T -i Net::Telnet || true

# Do not install sngrep on EL10 here; COPR/package not available during testing.

echo "PHP version:"
php -v || true
php -m | egrep 'mysqli|mysqlnd|curl|gd|ldap|mbstring|odbc|opcache|xml|zip' || true

# Root SSH login, matching previous installer behavior.
sed -i 's/^#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config || true
sed -i 's/^PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config || true
systemctl restart sshd || true

# ---------------------------------------------------------------------------
# PHP settings
# ---------------------------------------------------------------------------
echo "Configuring PHP"

cat >> /etc/php.ini <<EOF

; VICIdial installer settings
error_reporting = E_ALL & ~E_NOTICE & ~E_WARNING & ~E_DEPRECATED & ~E_STRICT
display_errors = Off
memory_limit = 448M
short_open_tag = On
max_execution_time = 3330
max_input_time = 3360
post_max_size = 448M
upload_max_filesize = 442M
default_socket_timeout = 3360
date.timezone = America/New_York
max_input_vars = 50000
EOF

sed -i 's/^display_errors = .*/display_errors = Off/' /etc/php.ini || true
sed -i 's/^error_reporting = .*/error_reporting = E_ALL \& ~E_NOTICE \& ~E_WARNING \& ~E_DEPRECATED \& ~E_STRICT/' /etc/php.ini || true

systemctl enable php-fpm
systemctl enable httpd
systemctl restart php-fpm || true
systemctl restart httpd

# ---------------------------------------------------------------------------
# Sendmail / MariaDB
# ---------------------------------------------------------------------------
echo "Configuring Sendmail and MariaDB"

dnf -y install sendmail || true
systemctl enable sendmail || true
systemctl start sendmail || true

systemctl enable mariadb

cp -a /etc/my.cnf /etc/my.cnf.original.$(date +%s) 2>/dev/null || true

cat > /etc/my.cnf <<'MYSQLCONF'
[mysql.server]
user = mysql

[client]
port = 3306
socket = /var/lib/mysql/mysql.sock

[mysqld]
socket = /var/lib/mysql/mysql.sock
max_connections=2000
key_buffer_size = 12G
log-error = /var/log/mysqld/mysqld.log
long_query_time = 3
slow_query_log = 1
slow_query_log_file = /var/log/mysqld/slow-queries.log
log_bin = /var/lib/mysql/mysql-bin
binlog_format=mixed
binlog_direct_non_transactional_updates=1
relay_log=/var/lib/mysql/mysql-relay-bin
datadir = /var/lib/mysql
server-id = 1
slave-skip-errors = 1032,1690,1062
slave_parallel_threads=20
slave-parallel-mode=optimistic
slave_parallel_max_queued=2M
skip-external-locking
skip-name-resolve
connect_timeout=60
max_allowed_packet = 16M
table_open_cache = 4096
table_definition_cache=16384
sort_buffer_size = 4M
net_buffer_length = 8K
read_buffer_size = 4M
read_rnd_buffer_size = 16M
myisam_sort_buffer_size = 128M
query-cache-size = 0
expire_logs_days = 3
concurrent_insert = 2
myisam_repair_threads = 4
myisam_recover_option=DEFAULT
tmpdir = /tmp/
thread_cache_size = 100
join_buffer_size = 1M
myisam_use_mmap=1
open_files_limit=24576
max_heap_table_size=512M
tmp_table_size = 32M
key_cache_segments=64
sql_mode=NO_ENGINE_SUBSTITUTION
log_warnings=1
default-storage-engine=MyISAM

innodb_buffer_pool_size = 128M
innodb_file_per_table = ON
innodb_flush_method=O_DIRECT
innodb_flush_log_at_trx_commit=2
innodb_log_buffer_size=8M

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
MYSQLCONF

mkdir -p /var/log/mysqld
touch /var/log/mysqld/slow-queries.log
chown -R mysql:mysql /var/log/mysqld
systemctl restart mariadb
systemctl restart httpd

# ---------------------------------------------------------------------------
# Perl modules
# ---------------------------------------------------------------------------
echo "Installing Perl modules"

dnf -y install \
perl-CPAN perl-YAML perl-CPAN-DistnameInfo perl-libwww-perl \
perl-DBI perl-DBD-MySQL perl-GD perl-Env perl-Term-ReadLine-Gnu \
perl-SelfLoader perl-open.noarch || true

mkdir -p /usr/src/new_vicidial
cd /usr/src/new_vicidial
curl -fsSL https://raw.githubusercontent.com/skaji/cpm/main/cpm | perl - install -g App::cpm || true
/usr/local/bin/cpm install -g || true

cd /usr/src
download_file "https://download.vicidial.com/required-apps/asterisk-perl-0.08.tar.gz" "asterisk-perl-0.08.tar.gz" || \
download_file "https://downloads.sourceforge.net/project/asterisk-perl/asterisk-perl/0.08/asterisk-perl-0.08.tar.gz" "asterisk-perl-0.08.tar.gz" || true

if [[ -f /usr/src/asterisk-perl-0.08.tar.gz ]]; then
    tar xzf asterisk-perl-0.08.tar.gz
    cd asterisk-perl-0.08
    perl Makefile.PL
    make all
    make install
fi

# ---------------------------------------------------------------------------
# Build LAME
# ---------------------------------------------------------------------------
echo "Installing LAME"

cd /usr/src
download_file "$LAME_URL" "lame-3.99.5.tar.gz"
tar -zxf lame-3.99.5.tar.gz
cd lame-3.99.5
./configure
make -j"$(nproc)"
make install

# ---------------------------------------------------------------------------
# Build Jansson
# ---------------------------------------------------------------------------
echo "Installing Jansson"

cd /usr/src
download_file "$JANSSON_URL" "jansson-2.13.tar.gz"
tar xvzf jansson-2.13.tar.gz
cd jansson-2.13
./configure
make clean
make -j"$(nproc)"
make install
ldconfig

# ---------------------------------------------------------------------------
# Running-kernel build dependency check
# ---------------------------------------------------------------------------
echo "Checking kernel-devel/kernel-headers for running kernel: $(uname -r)"
dnf install -y "kernel-devel-$(uname -r)" "kernel-headers-$(uname -r)"

if [[ ! -d "/lib/modules/$(uname -r)/build" ]]; then
    echo "ERROR: /lib/modules/$(uname -r)/build is missing."
    echo "Do not continue. Install kernel-devel for the running kernel or reboot into the installed kernel."
    exit 1
fi

# ---------------------------------------------------------------------------
# Build DAHDI 3.4.0 core-only
# ---------------------------------------------------------------------------
echo "Installing DAHDI ${DAHDI_VERSION}"

ln -sf "/usr/lib/modules/$(uname -r)/vmlinux.xz" /boot/ || true

cd /usr/src
rm -rf "dahdi-linux-complete-${DAHDI_VERSION}+${DAHDI_VERSION}"
download_file "$DAHDI_URL" "dahdi-linux-complete-${DAHDI_VERSION}+${DAHDI_VERSION}.tar.gz"
tar xzf "dahdi-linux-complete-${DAHDI_VERSION}+${DAHDI_VERSION}.tar.gz"
cd "dahdi-linux-complete-${DAHDI_VERSION}+${DAHDI_VERSION}"

DAHDI_DIR="/usr/src/dahdi-linux-complete-${DAHDI_VERSION}+${DAHDI_VERSION}"
KBUILD="$DAHDI_DIR/linux/drivers/dahdi/Kbuild"

cp "$KBUILD" "$KBUILD.orig"

# Disable legacy physical card drivers for SIP/VICIdial timing-only systems.
sed -i \
-e 's/^obj-$(DAHDI_BUILD_ALL)$(CONFIG_DAHDI_OCT612X)/#obj-$(DAHDI_BUILD_ALL)$(CONFIG_DAHDI_OCT612X)/' \
-e 's/^obj-$(DAHDI_BUILD_ALL)$(CONFIG_DAHDI_WCT4XXP)/#obj-$(DAHDI_BUILD_ALL)$(CONFIG_DAHDI_WCT4XXP)/' \
-e 's/^obj-$(DAHDI_BUILD_ALL)$(CONFIG_DAHDI_WCTC4XXP)/#obj-$(DAHDI_BUILD_ALL)$(CONFIG_DAHDI_WCTC4XXP)/' \
-e 's/^obj-$(DAHDI_BUILD_ALL)$(CONFIG_DAHDI_WCTDM24XXP)/#obj-$(DAHDI_BUILD_ALL)$(CONFIG_DAHDI_WCTDM24XXP)/' \
-e 's/^obj-$(DAHDI_BUILD_ALL)$(CONFIG_DAHDI_WCTE12XP)/#obj-$(DAHDI_BUILD_ALL)$(CONFIG_DAHDI_WCTE12XP)/' \
-e 's/^obj-$(DAHDI_BUILD_ALL)$(CONFIG_DAHDI_WCTE13XP)/#obj-$(DAHDI_BUILD_ALL)$(CONFIG_DAHDI_WCTE13XP)/' \
-e 's/^obj-$(DAHDI_BUILD_ALL)$(CONFIG_DAHDI_WCTE43X)/#obj-$(DAHDI_BUILD_ALL)$(CONFIG_DAHDI_WCTE43X)/' \
-e 's/^obj-$(DAHDI_BUILD_ALL)$(CONFIG_DAHDI_WCAXX)/#obj-$(DAHDI_BUILD_ALL)$(CONFIG_DAHDI_WCAXX)/' \
-e 's/^obj-$(DAHDI_BUILD_ALL)$(CONFIG_DAHDI_WCTDM)/#obj-$(DAHDI_BUILD_ALL)$(CONFIG_DAHDI_WCTDM)/' \
-e 's/^obj-$(DAHDI_BUILD_ALL)$(CONFIG_DAHDI_VOICEBUS)/#obj-$(DAHDI_BUILD_ALL)$(CONFIG_DAHDI_VOICEBUS)/' \
-e 's/^obj-$(DAHDI_BUILD_ALL)$(CONFIG_DAHDI_WCB4XXP)/#obj-$(DAHDI_BUILD_ALL)$(CONFIG_DAHDI_WCB4XXP)/' \
-e 's/^obj-$(DAHDI_BUILD_ALL)$(CONFIG_DAHDI_WCT1XXP)/#obj-$(DAHDI_BUILD_ALL)$(CONFIG_DAHDI_WCT1XXP)/' \
-e 's/^obj-$(DAHDI_BUILD_ALL)$(CONFIG_DAHDI_WCTE11XP)/#obj-$(DAHDI_BUILD_ALL)$(CONFIG_DAHDI_WCTE11XP)/' \
-e 's/^obj-$(DAHDI_BUILD_ALL)$(CONFIG_DAHDI_WCFXO)/#obj-$(DAHDI_BUILD_ALL)$(CONFIG_DAHDI_WCFXO)/' \
-e 's/^obj-$(DAHDI_BUILD_ALL)$(CONFIG_DAHDI_XPP)/#obj-$(DAHDI_BUILD_ALL)$(CONFIG_DAHDI_XPP)/' \
-e 's/^obj-$(DAHDI_BUILD_ALL)$(CONFIG_DAHDI_OPVXA1200)/#obj-$(DAHDI_BUILD_ALL)$(CONFIG_DAHDI_OPVXA1200)/' \
-e 's/^.*CONFIG_DAHDI_VPMADT032_LOADER.*$/#&/' \
"$KBUILD"

# EL9/EL10 kernel API compatibility patches already proven on EL9. Safe if strings exist; no-op otherwise.
sed -i 's/static int span_match(struct device \*dev, struct device_driver \*driver)/static int span_match(struct device *dev, const struct device_driver *driver)/' \
"$DAHDI_DIR/linux/drivers/dahdi/dahdi-sysfs.c" || true

sed -i 's/static int chan_match(struct device \*dev, struct device_driver \*driver)/static int chan_match(struct device *dev, const struct device_driver *driver)/' \
"$DAHDI_DIR/linux/drivers/dahdi/dahdi-sysfs-chan.c" || true

# from_timer fallback patches for drivers are mostly avoided by core-only Kbuild.
# Keep this available if core DAHDI ever exposes from_timer errors in a future kernel.
grep -n "^obj-\$(DAHDI_BUILD_ALL)" "$KBUILD" || true

make clean
make -j"$(nproc)"
make install
make install-config
depmod -a

# Do not install dahdi-tools-libs RPM. We are building DAHDI tools from source.
cd "$DAHDI_DIR/tools"
make clean
make -j"$(nproc)"
make install
make install-config
ldconfig

cp -f /etc/dahdi/system.conf.sample /etc/dahdi/system.conf || true

modprobe dahdi
# dahdi_dummy is not built in the core-only DAHDI 3.4.0 test path.

if command -v dahdi_test >/dev/null 2>&1; then
    timeout 15s dahdi_test -v || true
fi

systemctl enable dahdi || true
service dahdi start || true
service dahdi status || true

pause_continue

# ---------------------------------------------------------------------------
# Build libpri, libsrtp, Asterisk 18.21.0-vici
# ---------------------------------------------------------------------------
echo "Installing Asterisk and LibPRI"

mkdir -p /usr/src/asterisk
cd /usr/src/asterisk
download_file "$LIBPRI_URL" "libpri-1.6.1.tar.gz"
download_file "$ASTERISK_URL" "asterisk-18.21.0-vici.tar.gz"

tar -xvzf libpri-1.6.1.tar.gz
cd libpri-1.6.1
make -j"$(nproc)"
make install

cd /usr/src
download_file "$LIBSRTP_URL" "libsrtp-2.1.0.tar.gz"
tar xfv libsrtp-2.1.0.tar.gz
cd libsrtp-2.1.0
./configure --prefix=/usr --enable-openssl
make shared_library -j"$(nproc)"
make install
ldconfig

cd /usr/src/asterisk
tar -xvzf asterisk-18.21.0-vici.tar.gz
cd /usr/src/asterisk/asterisk-18.21.0-vici

: "${JOBS:=$(( $(nproc) + $(nproc) / 2 ))}"

./configure --libdir=/usr/lib64 --with-gsm=internal --enable-opus --enable-srtp \
--with-ssl --enable-asteriskssl --with-pjproject-bundled --with-jansson-bundled

make menuselect/menuselect menuselect-tree menuselect.makeopts
menuselect/menuselect --enable app_meetme menuselect.makeopts || true
menuselect/menuselect --enable res_http_websocket menuselect.makeopts || true
menuselect/menuselect --enable res_srtp menuselect.makeopts || true

make samples
sed -i 's|noload = chan_sip.so|;noload = chan_sip.so|g' /etc/asterisk/modules.conf || true
make -j "${JOBS}" all
make install

pause_continue

# ---------------------------------------------------------------------------
# Install astguiclient / VICIdial
# ---------------------------------------------------------------------------
echo "Installing astguiclient"

mkdir -p /usr/src/astguiclient
cd /usr/src/astguiclient
svn checkout svn://svn.eflo.net/agc_2-X/trunk
cd /usr/src/astguiclient/trunk

echo "Creating/importing VICIdial database"
mysql -u root <<'MYSQLCREOF'
CREATE DATABASE IF NOT EXISTS asterisk DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;

CREATE USER IF NOT EXISTS 'cron'@'localhost' IDENTIFIED BY '1234';
CREATE USER IF NOT EXISTS 'cron'@'%' IDENTIFIED BY '1234';
CREATE USER IF NOT EXISTS 'custom'@'localhost' IDENTIFIED BY 'custom1234';
CREATE USER IF NOT EXISTS 'custom'@'%' IDENTIFIED BY 'custom1234';

GRANT SELECT,CREATE,ALTER,INSERT,UPDATE,DELETE,LOCK TABLES ON asterisk.* TO 'cron'@'localhost';
GRANT SELECT,CREATE,ALTER,INSERT,UPDATE,DELETE,LOCK TABLES ON asterisk.* TO 'cron'@'%';
GRANT RELOAD ON *.* TO 'cron'@'localhost';
GRANT RELOAD ON *.* TO 'cron'@'%';

GRANT SELECT,CREATE,ALTER,INSERT,UPDATE,DELETE,LOCK TABLES ON asterisk.* TO 'custom'@'localhost';
GRANT SELECT,CREATE,ALTER,INSERT,UPDATE,DELETE,LOCK TABLES ON asterisk.* TO 'custom'@'%';
GRANT RELOAD ON *.* TO 'custom'@'localhost';
GRANT RELOAD ON *.* TO 'custom'@'%';

FLUSH PRIVILEGES;
SET GLOBAL connect_timeout=60;

USE asterisk;
SOURCE /usr/src/astguiclient/trunk/extras/MySQL_AST_CREATE_tables.sql;
SOURCE /usr/src/astguiclient/trunk/extras/first_server_install.sql;
UPDATE servers SET asterisk_version='18.21.0-vici';
MYSQLCREOF

pause_continue

cat > /etc/astguiclient.conf <<ASTGUI
# astguiclient.conf
PATHhome => /usr/share/astguiclient
PATHlogs => /var/log/astguiclient
PATHagi => /var/lib/asterisk/agi-bin
PATHweb => /var/www/html
PATHsounds => /var/lib/asterisk/sounds
PATHmonitor => /var/spool/asterisk/monitor
PATHDONEmonitor => /var/spool/asterisk/monitorDONE

VARserver_ip => ${SERVER_IP}
VARDB_server => localhost
VARDB_database => asterisk
VARDB_user => cron
VARDB_pass => 1234
VARDB_custom_user => custom
VARDB_custom_pass => custom1234
VARDB_port => 3306

VARactive_keepalives => 123456789EC
VARasterisk_version => 18.X

VARFTP_host => 10.0.0.4
VARFTP_user => cron
VARFTP_pass => test
VARFTP_port => 21
VARFTP_dir => RECORDINGS
VARHTTP_path => http://10.0.0.4

VARREPORT_host => 10.0.0.4
VARREPORT_user => cron
VARREPORT_pass => test
VARREPORT_port => 21
VARREPORT_dir => REPORTS

VARfastagi_log_min_servers => 3
VARfastagi_log_max_servers => 16
VARfastagi_log_min_spare_servers => 2
VARfastagi_log_max_spare_servers => 8
VARfastagi_log_max_requests => 1000
VARfastagi_log_checkfordead => 30
VARfastagi_log_checkforwait => 60

ExpectedDBSchema => 1743
ASTGUI

perl install.pl --no-prompt --copy_sample_conf_files=Y

# Secure Manager to localhost
sed -i 's/0.0.0.0/127.0.0.1/g' /etc/asterisk/manager.conf || true

# Force DAHDI timing for MeetMe, matching previous behavior, but use full path.
cat >> /etc/asterisk/modules.conf <<'EOF'

; VICIdial DAHDI timing preference
noload => res_timing_timerfd.so
noload => res_timing_kqueue.so
noload => res_timing_pthread.so
EOF

# Confbridge rows. Kept as previous installer behavior.
echo "Populate AREA CODES"
/usr/share/astguiclient/ADMIN_area_code_populate.pl || true

echo "Update server IP"
/usr/share/astguiclient/ADMIN_update_server_ip.pl --old-server_ip=10.10.10.15 --server_ip="$SERVER_IP" --auto || true

perl install.pl --no-prompt

# ---------------------------------------------------------------------------
# Crontab
# ---------------------------------------------------------------------------
cat > /root/crontab-file <<'CRONTAB'
###Audio Sync hourly
* 1 * * * /usr/share/astguiclient/ADMIN_audio_store_sync.pl --upload --quiet

### Daily Backups ###
0 2 * * * /usr/share/astguiclient/ADMIN_backup.pl

###certbot renew
@weekly /usr/src/new_vicidial/certbot.sh

### recording mixing/compressing/ftping scripts
#0,3,6,9,12,15,18,21,24,27,30,33,36,39,42,45,48,51,54,57 * * * * /usr/share/astguiclient/AST_CRON_audio_1_move_mix.pl
0,3,6,9,12,15,18,21,24,27,30,33,36,39,42,45,48,51,54,57 * * * * /usr/share/astguiclient/AST_CRON_audio_1_move_mix.pl --MIX
0,3,6,9,12,15,18,21,24,27,30,33,36,39,42,45,48,51,54,57 * * * * /usr/share/astguiclient/AST_CRON_audio_1_move_VDonly.pl
1,4,7,10,13,16,19,22,25,28,31,34,37,40,43,46,49,52,55,58 * * * * /usr/share/astguiclient/AST_CRON_audio_2_compress.pl --MP3 --HTTPS
#2,5,8,11,14,17,20,23,26,29,32,35,38,41,44,47,50,53,56,59 * * * * /usr/share/astguiclient/AST_CRON_audio_3_ftp.pl --MP3 --nodatedir --ftp-validate

### keepalive script for astguiclient processes
* * * * * /usr/share/astguiclient/ADMIN_keepalive_ALL.pl --cu3way

### kill Hangup script for Asterisk updaters
* * * * * /usr/share/astguiclient/AST_manager_kill_hung_congested.pl

### updater for voicemail
* * * * * /usr/share/astguiclient/AST_vm_update.pl

### updater for conference validator
* * * * * /usr/share/astguiclient/AST_conf_update.pl --no-vc-3way-check

### flush queue DB table every hour for entries older than 1 hour
11 * * * * /usr/share/astguiclient/AST_flush_DBqueue.pl -q

### fix the vicidial_agent_log once every hour and the full day run at night
33 * * * * /usr/share/astguiclient/AST_cleanup_agent_log.pl
50 0 * * * /usr/share/astguiclient/AST_cleanup_agent_log.pl --last-24hours

## uncomment below if using QueueMetrics
#*/5 * * * * /usr/share/astguiclient/AST_cleanup_agent_log.pl --only-qm-live-call-check

## uncomment below if using Vtiger
#1 1 * * * /usr/share/astguiclient/Vtiger_optimize_all_tables.pl --quiet

### updater for VICIDIAL hopper
* * * * * /usr/share/astguiclient/AST_VDhopper.pl -q

### adjust the GMT offset for the leads in the vicidial_list table
1 1,7 * * * /usr/share/astguiclient/ADMIN_adjust_GMTnow_on_leads.pl --debug

### reset several temporary-info tables in the database
2 1 * * * /usr/share/astguiclient/AST_reset_mysql_vars.pl

### optimize the database tables within the asterisk database
3 1 * * * /usr/share/astguiclient/AST_DB_optimize.pl

## adjust time on the server with ntp
#30 * * * * /usr/sbin/ntpdate -u pool.ntp.org 2>/dev/null 1>&amp;2

### VICIDIAL agent time log weekly and daily summary report generation
2 0 * * 0 /usr/share/astguiclient/AST_agent_week.pl
22 0 * * * /usr/share/astguiclient/AST_agent_day.pl

### VICIDIAL campaign export scripts (OPTIONAL)
#32 0 * * * /usr/share/astguiclient/AST_VDsales_export.pl
#42 0 * * * /usr/share/astguiclient/AST_sourceID_summary_export.pl

### remove old recordings
#24 0 * * * /usr/bin/find /var/spool/asterisk/monitorDONE -maxdepth 2 -type f -mtime +7 -print | xargs rm -f
#26 1 * * * /usr/bin/find /var/spool/asterisk/monitorDONE/MP3 -maxdepth 2 -type f -mtime +65 -print | xargs rm -f
#25 1 * * * /usr/bin/find /var/spool/asterisk/monitorDONE/FTP -maxdepth 2 -type f -mtime +1 -print | xargs rm -f
24 1 * * * /usr/bin/find /var/spool/asterisk/monitorDONE/ORIG -maxdepth 2 -type f -mtime +1 -print | xargs rm -f


### roll logs monthly on high-volume dialing systems
30 1 1 * * /usr/share/astguiclient/ADMIN_archive_log_tables.pl --DAYS=45

### remove old vicidial logs and asterisk logs more than 2 days old
28 0 * * * /usr/bin/find /var/log/astguiclient -maxdepth 1 -type f -mtime +2 -print | xargs rm -f
29 0 * * * /usr/bin/find /var/log/asterisk -maxdepth 3 -type f -mtime +2 -print | xargs rm -f
30 0 * * * /usr/bin/find / -maxdepth 1 -name "screenlog.0*" -mtime +4 -print | xargs rm -f

### cleanup of the scheduled callback records
25 0 * * * /usr/share/astguiclient/AST_DB_dead_cb_purge.pl --purge-non-cb -q

### GMT adjust script - uncomment to enable
#45 0 * * * /usr/share/astguiclient/ADMIN_adjust_GMTnow_on_leads.pl --list-settings

### Dialer Inventory Report
1 7 * * * /usr/share/astguiclient/AST_dialer_inventory_snapshot.pl -q --override-24hours

### inbound email parser
* * * * * /usr/share/astguiclient/AST_inbound_email_parser.pl

### Daily Reboot
#30 6 * * * /sbin/reboot

######TILTIX GARBAGE FILES DELETE
#00 22 * * * root cd /tmp/ && find . -name '*TILTXtmp*' -type f -delete

### Dynportal
@reboot /usr/bin/VB-firewall --whitelist=ViciWhite --dynamic --quiet
* * * * * /usr/bin/VB-firewall --whitelist=ViciWhite --dynamic --quiet
* * * * * sleep 10; /usr/bin/VB-firewall --white --dynamic --quiet
* * * * * sleep 20; /usr/bin/VB-firewall --white --dynamic --quiet
* * * * * sleep 30; /usr/bin/VB-firewall --white --dynamic --quiet
* * * * * sleep 40; /usr/bin/VB-firewall --white --dynamic --quiet
* * * * * sleep 50; /usr/bin/VB-firewall --white --dynamic --quiet

### url log delete
30 23 * * * /usr/share/astguiclient/ADMIN_archive_log_tables.pl --url-log-only --url-log-days=30
CRONTAB

crontab /root/crontab-file
crontab -l

# ---------------------------------------------------------------------------
# rc.local
# ---------------------------------------------------------------------------
cat > /etc/rc.d/rc.local <<'EOF'
#!/bin/bash

/usr/share/astguiclient/ip_relay/relay_control start 2>/dev/null 1>&2 || true

/usr/bin/setterm -blank || true
/usr/bin/setterm -powersave off || true
/usr/bin/setterm -powerdown || true

systemctl start mariadb.service
systemctl start php-fpm.service
systemctl start httpd.service

/usr/share/astguiclient/ADMIN_restart_roll_logs.pl || true
/usr/share/astguiclient/AST_reset_mysql_vars.pl || true

modprobe dahdi
/usr/sbin/dahdi_cfg -vvvvvvvvvvvvv || true

sleep 20
/usr/share/astguiclient/start_asterisk_boot.pl || true

exit 0
EOF

chmod +x /etc/rc.d/rc.local

cat > /etc/systemd/system/rc-local.service <<'EOF'
[Unit]
Description=/etc/rc.local Compatibility
ConditionPathExists=/etc/rc.d/rc.local
After=network-online.target mariadb.service httpd.service php-fpm.service
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/etc/rc.d/rc.local
TimeoutSec=0
StandardOutput=journal+console
StandardError=journal+console
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable rc-local.service

# ---------------------------------------------------------------------------
# Dynportal / VB-firewall custom section
# ---------------------------------------------------------------------------
echo "Installing Dynportal / VB-firewall custom files"

systemctl enable firewalld
systemctl start firewalld

cd /home
download_file "$DYNPORTAL_URL" "dynportal.zip"
download_file "$FIREWALL_ZIP_URL" "firewall.zip"
download_file "$AGGREGATE_URL" "aggregate"
download_file "$VB_FIREWALL_URL" "VB-firewall"

mkdir -p /var/www/vhosts/dynportal
\cp -f /home/dynportal.zip /var/www/vhosts/dynportal/
\cp -f /home/firewall.zip /etc/firewalld/

cd /var/www/vhosts/dynportal/
unzip -o dynportal.zip
chmod -R 755 .
chown -R apache:apache .

if [[ -f etc/httpd/conf.d/viciportal.conf ]]; then
    \cp -f etc/httpd/conf.d/viciportal.conf /etc/httpd/conf.d/
fi
if [[ -f etc/httpd/conf.d/viciportal-ssl.conf ]]; then
    \cp -f etc/httpd/conf.d/viciportal-ssl.conf /etc/httpd/conf.d/
fi

cd /etc/firewalld/
unzip -o firewall.zip
if [[ -d zones ]]; then
    cd zones
    rm -f public.xml trusted.xml
    cd /etc/firewalld
    mv -f public.xml trusted.xml /etc/firewalld/zones/ 2>/dev/null || true
fi

\cp -f /home/aggregate /usr/bin/
chmod +x /usr/bin/aggregate
\cp -f /home/VB-firewall /usr/bin/
chmod +x /usr/bin/VB-firewall

firewall-offline-cmd --add-port=446/tcp --zone=public || true

# ---------------------------------------------------------------------------
# ip_relay
# ---------------------------------------------------------------------------
echo "Building ip_relay"

cd /usr/src/astguiclient/trunk/extras/ip_relay/
unzip -o ip_relay_1.1.112705.zip
cd ip_relay_1.1/src/unix/
make
cp ip_relay ip_relay2
mv -f ip_relay /usr/bin/
mv -f ip_relay2 /usr/local/bin/ip_relay

# ---------------------------------------------------------------------------
# Optional G729 binary from legacy source
# ---------------------------------------------------------------------------
echo "Installing optional G729 codec"

mkdir -p /usr/lib64/asterisk/modules
cd /usr/lib64/asterisk/modules
curl -fL --retry 3 -o codec_g729.so "http://asterisk.hosting.lv/bin/codec_g729-ast160-gcc4-glibc-x86_64-core2-sse4.so" || true
chmod 755 codec_g729.so 2>/dev/null || true

# ---------------------------------------------------------------------------
# Apache recording alias and system limits
# ---------------------------------------------------------------------------
cat >> /etc/httpd/conf/httpd.conf <<'EOF'

CustomLog /dev/null common

Alias /RECORDINGS/MP3 "/var/spool/asterisk/monitorDONE/MP3/"

<Directory "/var/spool/asterisk/monitorDONE/MP3/">
    Options Indexes MultiViews
    AllowOverride None
    Require all granted
</Directory>
Timeout 600
EOF

cat >> /etc/systemd/system.conf <<'EOF'
DefaultLimitNOFILE=65536
EOF

# ---------------------------------------------------------------------------
# Sounds
# ---------------------------------------------------------------------------
echo "Installing Asterisk sounds"

cd /usr/src
for f in \
asterisk-core-sounds-en-ulaw-current.tar.gz \
asterisk-core-sounds-en-wav-current.tar.gz \
asterisk-core-sounds-en-gsm-current.tar.gz \
asterisk-extra-sounds-en-ulaw-current.tar.gz \
asterisk-extra-sounds-en-wav-current.tar.gz \
asterisk-extra-sounds-en-gsm-current.tar.gz \
asterisk-moh-opsound-gsm-current.tar.gz \
asterisk-moh-opsound-ulaw-current.tar.gz \
asterisk-moh-opsound-wav-current.tar.gz
do
    download_file "https://downloads.asterisk.org/pub/telephony/sounds/$f" "$f"
done

mkdir -p /var/lib/asterisk/sounds /var/lib/asterisk/mohmp3 /var/lib/asterisk/quiet-mp3

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
rm -f CHANGES* LICENSE* CREDITS*

cd /var/lib/asterisk/sounds
rm -f CHANGES* LICENSE* CREDITS*

cd /var/lib/asterisk/quiet-mp3
for base in \
macroform-cold_day \
macroform-robot_dity \
macroform-the_simplicity \
reno_project-system \
manolo_camp-morning_coffee
do
    [[ -f "../mohmp3/${base}.wav" ]] && sox "../mohmp3/${base}.wav" "${base}.wav" vol 0.25 || true
    [[ -f "../mohmp3/${base}.gsm" ]] && sox "../mohmp3/${base}.gsm" "${base}.gsm" vol 0.25 || true
    [[ -f "../mohmp3/${base}.ulaw" ]] && sox -t ul -r 8000 -c 1 "../mohmp3/${base}.ulaw" -t ul "${base}.ulaw" vol 0.25 || true
done

# ---------------------------------------------------------------------------
# Custom ConfBridge / WebRTC helper section
# ---------------------------------------------------------------------------
echo "Applying custom ConfBridge and WebRTC helper files"

if [[ -d /usr/src/new_vicidial ]]; then
    cd /usr/src/new_vicidial

    # Do not blindly overwrite /etc/asterisk/extensions.conf.
    # Replacing the whole file can remove current VICIdial-generated dialplan content.

    if [[ -f confbridge-vicidial.conf ]]; then
        \cp -f confbridge-vicidial.conf /etc/asterisk/confbridge-vicidial.conf
        grep -q "confbridge-vicidial.conf" /etc/asterisk/confbridge.conf ||         echo '#include "confbridge-vicidial.conf"' >> /etc/asterisk/confbridge.conf
    fi

    if [[ -f certbot.sh ]]; then
        chmod +x certbot.sh
    fi
fi

# Start Asterisk and run keepalive once so VICIdial generates configs, then re-copy ConfBridge
asterisk || true
sleep 5
/usr/share/astguiclient/ADMIN_keepalive_ALL.pl --cu3way || true

if [[ -f /usr/src/new_vicidial/confbridge-vicidial.conf ]]; then
    \cp -f /usr/src/new_vicidial/confbridge-vicidial.conf /etc/asterisk/confbridge-vicidial.conf
fi

asterisk -rx "module load app_confbridge.so" || true
asterisk -rx "reload app_confbridge.so" || true
asterisk -rx "module reload app_meetme.so" || true
asterisk -rx "dialplan reload" || true
asterisk -rx "sip reload" || true

# WebRTC DB updates compatible with SVN 4000/schema 1743.
mysql -u root -e "USE asterisk;
UPDATE system_settings SET default_webphone='1', webphone_url='https://phone.viciphone.com/viciphone.php', sounds_web_server='https://${SERVER_HOSTNAME}';
UPDATE phones SET is_webphone='Y', webphone_dialpad='Y', webphone_auto_answer='Y', webphone_dialbox='Y', webphone_mute='Y', webphone_volume='Y';" || true

if [[ -f /usr/src/new_vicidial/vicidial-enable-webrtc.sh && -f /var/www/vhosts/dynportal/inc/defaults.inc.php ]]; then
    cd /usr/src/new_vicidial
    chmod +x vicidial-enable-webrtc.sh
    ./vicidial-enable-webrtc.sh || true
fi

cat > /var/www/html/index.html <<'WELCOME'
<META HTTP-EQUIV=REFRESH CONTENT="1; URL=/vicidial/welcome.php">
Please Hold while I redirect you!
WELCOME
chown apache:apache /var/www/html/index.html || true
chmod 644 /var/www/html/index.html || true

chkconfig asterisk off || true

cat >> /etc/asterisk/manager.conf <<'EOF'

[confcron]
secret = 1234
read = command,reporting
write = command,reporting
eventfilter=Event: Meetme
eventfilter=Event: Confbridge
EOF

dnf -y install certbot || true
systemctl enable certbot-renew.timer || true
systemctl start certbot-renew.timer || true

# Firewall policy, copied from prior installer.
firewall-cmd --add-service=http --permanent --zone=trusted || true
firewall-cmd --permanent --add-rich-rule="rule family='ipv4' source address='74.208.178.234' accept" || true
firewall-cmd --permanent --add-rich-rule="rule family='ipv4' source address='12.170.243.178' accept" || true
firewall-cmd --permanent --add-rich-rule="rule family='ipv4' source address='74.208.129.213' accept" || true
firewall-cmd --permanent --add-rich-rule="rule family='ipv4' source address='45.3.191.82' accept" || true
firewall-cmd --permanent --add-rich-rule="rule family='ipv4' source address='167.99.6.117' accept" || true
firewall-cmd --permanent --remove-port=8089/tcp || true
firewall-cmd --permanent --remove-port=8089/udp || true
firewall-cmd --permanent --remove-service=http || true
firewall-cmd --permanent --remove-service=https || true
firewall-cmd --permanent --add-port=10000-20000/udp || true
firewall-cmd --permanent --remove-service=ssh || true
firewall-cmd --permanent --remove-service=cockpit || true
firewall-cmd --permanent --remove-service=dhcpv6-client || true
firewall-cmd --reload || true

chmod -R 777 /var/spool/asterisk/ || true
chown -R apache:apache /var/spool/asterisk/ || true

mysql -u root -e "USE asterisk; UPDATE system_settings SET active_voicemail_server='${SERVER_IP}', default_webphone='1', webphone_url='https://phone.viciphone.com/viciphone.php', sounds_web_server='https://${SERVER_HOSTNAME}';" || true

systemctl daemon-reload
systemctl enable php-fpm
systemctl enable httpd
systemctl enable mariadb
systemctl enable firewalld
systemctl enable rc-local.service
systemctl restart php-fpm || true
systemctl restart httpd
systemctl restart mariadb
systemctl restart firewalld || true
systemctl start rc-local.service || true

echo "Final DAHDI check:"
lsmod | grep dahdi || true
ls -l /dev/dahdi || true
timeout 10s dahdi_test -v || true


echo "Final service validation:"
systemctl is-enabled mariadb httpd php-fpm rc-local firewalld || true
systemctl is-active mariadb httpd php-fpm firewalld || true
asterisk -rx "core show version" || true
asterisk -rx "sip show peers" || true
asterisk -rx "module show like app_confbridge" || true
curl -k -I "https://localhost:446/valid8.php" || true
curl -I "http://127.0.0.1/vicidial/welcome.php" || true
crontab -l | grep ADMIN_keepalive_ALL || true

echo "VICIdial AlmaLinux 10 test installer complete."
read -r -p "Press Enter to reboot, or Ctrl+C to cancel."
reboot
