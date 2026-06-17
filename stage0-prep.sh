#!/bin/bash
set -euo pipefail

LOG=/var/log/genx-vicidial-stage0.log
exec > >(tee -a "$LOG") 2>&1

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  echo "Run as root."
  exit 1
fi

select_timezone() {
  echo "Select server timezone:"
  echo "  1) Eastern  - America/New_York"
  echo "  2) Central  - America/Chicago"
  echo "  3) Mountain - America/Denver"
  echo "  4) Pacific  - America/Los_Angeles"
  read -rp "Timezone [1]: " tz_choice
  case "${tz_choice:-1}" in
    1) TZ="America/New_York" ;;
    2) TZ="America/Chicago" ;;
    3) TZ="America/Denver" ;;
    4) TZ="America/Los_Angeles" ;;
    *) TZ="America/New_York" ;;
  esac
  echo "$TZ" > /root/.genx-vicidial-timezone
}

select_timezone

dnf install -y glibc-langpack-en
localectl set-locale en_US.UTF-8
timedatectl set-timezone "$(cat /root/.genx-vicidial-timezone)"

dnf check-update || true
dnf update -y
dnf install -y epel-release git curl wget tar gzip unzip sed gawk
dnf update -y

sed -i 's/^SELINUX=.*/SELINUX=disabled/g' /etc/selinux/config
setenforce 0 2>/dev/null || true

mkdir -p /usr/src
cd /usr/src
if [ -d /usr/src/new_vicidial/.git ]; then
  git -C /usr/src/new_vicidial pull --ff-only || true
else
  git clone https://github.com/GenXoutsourcing/new_vicidial
fi

touch /root/.genx-vicidial-stage0-complete

echo
echo "Stage 0 complete. Reboot is required before Stage 1."
echo "After reboot run: ./stage1-install.sh"
read -rp "Reboot now? [Y/n]: " ans
if [[ "${ans:-Y}" =~ ^[Yy]$ ]]; then
  reboot
fi
