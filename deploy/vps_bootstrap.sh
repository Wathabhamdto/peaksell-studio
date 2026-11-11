#!/usr/bin/env bash
# One-time preparation of a fresh Ubuntu 22.04/24.04 VPS for PeakSell Studio.
# Run as root:  bash vps_bootstrap.sh
# Idempotent: safe to re-run.
set -euo pipefail

echo "== Packages =="
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl git ufw unattended-upgrades fail2ban

echo "== Docker =="
if ! command -v docker >/dev/null; then
  curl -fsSL https://get.docker.com | sh
fi
systemctl enable --now docker
docker compose version

echo "== Firewall: SSH only (Cloudflare Tunnel is outbound, no ports needed) =="
ufw allow OpenSSH
ufw --force enable
ufw status

echo "== Swap (2 GB) for video processing peaks =="
if ! swapon --show | grep -q /swapfile; then
  fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
  grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

echo "== Automatic security updates =="
dpkg-reconfigure -f noninteractive unattended-upgrades

echo "== Docker log rotation =="
mkdir -p /etc/docker
if [ ! -f /etc/docker/daemon.json ]; then
  cat > /etc/docker/daemon.json <<'JSON'
{ "log-driver": "json-file", "log-opts": { "max-size": "20m", "max-file": "5" } }
JSON
  systemctl restart docker
fi

echo "Bootstrap done."
