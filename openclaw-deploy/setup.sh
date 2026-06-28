#!/usr/bin/env bash
#
# Provision a fresh Ubuntu 24.04 VPS (Hetzner CX22/CX32) to run OpenClaw with
# as little long-term maintenance as possible. Run as root on the new server:
#
#     bash setup.sh
#
# It automates every recurring chore so you don't have to babysit the box:
#   1. Non-root sudo user + locked-down SSH (key-only, no root, no passwords).
#   2. Firewall (ufw) + fail2ban.
#   3. Docker Engine + Compose v2, with log rotation and live-restore.
#   4. Tailscale (private access to the Control UI).
#   5. Unattended security upgrades WITH automatic reboot in a night window.
#   6. systemd timers: nightly local backup + a health heartbeat (dead-man's
#      switch) that pings an external monitor so you're told if the host dies.
#
# It does NOT pull OpenClaw or write secrets — do that with .env + docker compose
# (see DEPLOY.md). Re-running is safe; steps are idempotent where practical.

set -euo pipefail

NEW_USER="${NEW_USER:-openclaw}"
ENABLE_HTTP="${ENABLE_HTTP:-no}"      # set "yes" only if fronting the UI with Caddy on 80/443
REBOOT_TIME="${REBOOT_TIME:-04:00}"   # auto-reboot window for kernel updates
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\n\033[1;33m[!]\033[0m %s\n' "$*"; }

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
fi
# Copy root's authorized_keys so you can SSH in as the new user.
if [[ -f /root/.ssh/authorized_keys ]]; then
  install -d -m 700 -o "$NEW_USER" -g "$NEW_USER" "/home/$NEW_USER/.ssh"
  install -m 600 -o "$NEW_USER" -g "$NEW_USER" \
    /root/.ssh/authorized_keys "/home/$NEW_USER/.ssh/authorized_keys"
fi

log "Hardening SSH"
HAS_KEY=no
[[ -s "/home/$NEW_USER/.ssh/authorized_keys" ]] && HAS_KEY=yes
if [[ "$HAS_KEY" == "yes" ]]; then
  cat > /etc/ssh/sshd_config.d/99-openclaw.conf <<EOF
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
KbdInteractiveAuthentication no
# Allow local forwards only (needed for the SSH-tunnel UI access pattern);
# block remote forwarding abuse. Per the official OpenClaw Hetzner guide.
AllowTcpForwarding local
AllowAgentForwarding no
X11Forwarding no
EOF
  systemctl restart ssh || systemctl restart sshd || true
else
  warn "No SSH key found for '$NEW_USER' — leaving password auth ENABLED so you"
  warn "don't get locked out. Re-create the server with an SSH key attached, or"
  warn "add one and re-run, to disable password login. (See DEPLOY.md step 2.)"
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
systemctl enable --now fail2ban

log "Enabling unattended security upgrades with auto-reboot at $REBOOT_TIME"
cat > /etc/apt/apt.conf.d/20auto-upgrades <<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
EOF
cat > /etc/apt/apt.conf.d/51openclaw-reboot <<EOF
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-WithUsers "true";
Unattended-Upgrade::Automatic-Reboot-Time "$REBOOT_TIME";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOF
systemctl enable --now unattended-upgrades

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

log "Configuring Docker log rotation + live-restore"
install -d -m 755 /etc/docker
cat > /etc/docker/daemon.json <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "live-restore": true
}
EOF
systemctl restart docker

log "Installing Tailscale"
if ! command -v tailscale &>/dev/null; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi

log "Creating directories + installing maintenance scripts"
# Host-side dirs (used by root systemd timers / scripts).
install -d -o "$NEW_USER" -g "$NEW_USER" \
  /opt/openclaw /opt/openclaw/backups /opt/openclaw/bin
# Bind-mounted state dirs: the container runs as uid 1000 (node), so these MUST
# be owned by 1000:1000 or the agent can't write to them. Per the official
# OpenClaw Hetzner guide (chown -R 1000:1000).
install -d -o 1000 -g 1000 \
  /opt/openclaw/config /opt/openclaw/workspace /opt/openclaw/auth
for f in heartbeat.sh backup.sh; do
  if [[ -f "$SCRIPT_DIR/scripts/$f" ]]; then
    install -m 755 "$SCRIPT_DIR/scripts/$f" "/opt/openclaw/bin/$f"
  fi
done

log "Installing systemd timers (backup + health heartbeat)"
cat > /etc/systemd/system/openclaw-backup.service <<EOF
[Unit]
Description=OpenClaw state backup
[Service]
Type=oneshot
ExecStart=/opt/openclaw/bin/backup.sh
EOF
cat > /etc/systemd/system/openclaw-backup.timer <<EOF
[Unit]
Description=Nightly OpenClaw backup
[Timer]
OnCalendar=*-*-* 03:30:00
Persistent=true
[Install]
WantedBy=timers.target
EOF
cat > /etc/systemd/system/openclaw-heartbeat.service <<EOF
[Unit]
Description=OpenClaw health heartbeat (dead-man's switch)
[Service]
Type=oneshot
EnvironmentFile=-/opt/openclaw/.env
ExecStart=/opt/openclaw/bin/heartbeat.sh
EOF
cat > /etc/systemd/system/openclaw-heartbeat.timer <<EOF
[Unit]
Description=Run OpenClaw heartbeat every 5 minutes
[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
systemctl enable --now openclaw-backup.timer
[[ -f /opt/openclaw/bin/heartbeat.sh ]] && systemctl enable --now openclaw-heartbeat.timer || true

log "Done."
cat <<EOF

Next steps (as the '$NEW_USER' user):
  1. tailscale up --ssh         # join your tailnet; --ssh lets you drop port 22 later
  2. cp .env.example .env  &&  edit .env  (ANTHROPIC_API_KEY, token, HEALTHCHECKS_URL)
  3. docker compose up -d openclaw-gateway watchtower
  4. curl -fsS http://127.0.0.1:18789/readyz
  5. Reach the Control UI over Tailscale: http://<host-tailscale-name>:18789/

Self-managing pieces now active:
  - Security patches + auto-reboot nightly at $REBOOT_TIME
  - OpenClaw image auto-updates via Watchtower (weekly)
  - Docker logs capped (10m x3); daemon live-restore on
  - Nightly local backups (openclaw-backup.timer) -> /opt/openclaw/backups
  - Health heartbeat every 5 min (set HEALTHCHECKS_URL in .env to get alerts)
See DEPLOY.md for the manual checklist (Hetzner Backups, monitoring, WhatsApp).
EOF
