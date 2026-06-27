#!/usr/bin/env bash
#
# Provision a fresh Ubuntu 24.04 VPS (Hetzner CX22 or similar) to run OpenClaw.
# Run as root on the new server:  bash setup.sh
#
# What it does:
#   1. Creates a non-root sudo user (key auth only).
#   2. Firewall: allow SSH + (optionally) 80/443, deny everything else.
#   3. Installs Docker Engine + Compose v2.
#   4. Installs Tailscale (private access to the Control UI).
#   5. Creates persistent state dirs under /opt/openclaw.
#
# It does NOT pull OpenClaw or write secrets — do that with .env + docker compose
# (see DEPLOY.md). Re-running is safe; steps are idempotent where practical.

set -euo pipefail

NEW_USER="${NEW_USER:-openclaw}"
ENABLE_HTTP="${ENABLE_HTTP:-no}"   # set to "yes" if you front the UI with Caddy on 80/443

log() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }

if [[ $EUID -ne 0 ]]; then
  echo "Run as root (the script creates the unprivileged user itself)." >&2
  exit 1
fi

log "Updating base packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y
apt-get install -y ca-certificates curl gnupg ufw fail2ban unattended-upgrades

log "Creating user '$NEW_USER'"
if ! id "$NEW_USER" &>/dev/null; then
  adduser --disabled-password --gecos "" "$NEW_USER"
  usermod -aG sudo "$NEW_USER"
  # Copy root's authorized_keys so you can SSH in as the new user.
  if [[ -f /root/.ssh/authorized_keys ]]; then
    install -d -m 700 -o "$NEW_USER" -g "$NEW_USER" "/home/$NEW_USER/.ssh"
    install -m 600 -o "$NEW_USER" -g "$NEW_USER" \
      /root/.ssh/authorized_keys "/home/$NEW_USER/.ssh/authorized_keys"
  fi
fi

log "Configuring firewall (ufw)"
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
if [[ "$ENABLE_HTTP" == "yes" ]]; then
  ufw allow 80/tcp
  ufw allow 443/tcp
fi
ufw --force enable

log "Enabling unattended security upgrades"
dpkg-reconfigure -f noninteractive unattended-upgrades || true

log "Installing Docker Engine + Compose v2"
if ! command -v docker &>/dev/null; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  ARCH="$(dpkg --print-architecture)"
  CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")"
  echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu $CODENAME stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin
fi
usermod -aG docker "$NEW_USER"

log "Installing Tailscale"
if ! command -v tailscale &>/dev/null; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi
echo "Run 'tailscale up' as root to join your tailnet, then reach the UI at"
echo "http://<this-host-tailscale-name>:18789/ — keep it OFF the public internet."

log "Creating persistent state directories"
install -d -o "$NEW_USER" -g "$NEW_USER" \
  /opt/openclaw /opt/openclaw/config /opt/openclaw/workspace /opt/openclaw/auth

log "Done."
cat <<EOF

Next steps (as the '$NEW_USER' user):
  1. Copy this repo's openclaw-deploy/ files to the server.
  2. cp .env.example .env  &&  edit .env  (set ANTHROPIC_API_KEY + a token).
  3. docker compose up -d openclaw-gateway
  4. curl -fsS http://127.0.0.1:18789/readyz
  5. Access the Control UI over Tailscale or:  ssh -L 18789:127.0.0.1:18789 ...
See DEPLOY.md for the full runbook.
EOF
