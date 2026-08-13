#!/usr/bin/env bash
set -euo pipefail

REPO="${REPO:-mariomsamy/Proxmox-VE-LXC-Update-Scripts-Automation}"
BRANCH="main"
RAW="https://raw.githubusercontent.com/${REPO}/${BRANCH}"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_root() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "run this installer as root on the Proxmox VE host"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

download() {
  local src="$1"
  local dest="$2"
  curl --proto '=https' --tlsv1.2 --fail --show-error --silent --location "$src" --output "$dest"
}

install_file() {
  local src="$1"
  local dest="$2"
  local mode="$3"
  install -o root -g root -m "$mode" "$src" "$dest"
}

require_root
require_cmd curl
require_cmd install
require_cmd systemctl

download "${RAW}/lxc-auto-update.sh" "${TMP_DIR}/lxc-auto-update.sh"
download "${RAW}/config/lxc-auto-update.conf" "${TMP_DIR}/lxc-auto-update.conf"
download "${RAW}/systemd/lxc-auto-update.service" "${TMP_DIR}/lxc-auto-update.service"
download "${RAW}/systemd/lxc-auto-update.timer" "${TMP_DIR}/lxc-auto-update.timer"

bash -n "${TMP_DIR}/lxc-auto-update.sh"
bash -n "${TMP_DIR}/lxc-auto-update.conf"

install_file "${TMP_DIR}/lxc-auto-update.sh" /usr/local/sbin/lxc-auto-update.sh 0755

# Install config only if not existing (preserve user edits on upgrades)
if [[ ! -f /etc/lxc-auto-update.conf ]]; then
  install_file "${TMP_DIR}/lxc-auto-update.conf" /etc/lxc-auto-update.conf 0640
else
  chown root:root /etc/lxc-auto-update.conf
  chmod go-w /etc/lxc-auto-update.conf
fi

install_file "${TMP_DIR}/lxc-auto-update.service" /etc/systemd/system/lxc-auto-update.service 0644
install_file "${TMP_DIR}/lxc-auto-update.timer" /etc/systemd/system/lxc-auto-update.timer 0644

install -d -o root -g root -m 0755 /var/log/lxc-auto-update

systemctl daemon-reload
systemctl enable --now lxc-auto-update.timer

echo "Installed: /usr/local/sbin/lxc-auto-update.sh"
echo "Config:    /etc/lxc-auto-update.conf"
echo "Timer:     lxc-auto-update.timer (daily 06:30)"
echo "Log:       /var/log/lxc-auto-update/daily.log"
echo
systemctl list-timers --all | grep lxc-auto-update || true
