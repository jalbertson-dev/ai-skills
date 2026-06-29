#!/usr/bin/env bash
#
# Install the email-triage automation on the (already-hardened) host.
# Run as root on the VPS after setup.sh has prepared the box:
#   sudo bash install.sh
#
# It copies the automation into /opt, installs Claude Code if missing, and
# enables the systemd timer. You still must create .env, mcp.gmail.json, and
# authorize Gmail (read+label scopes) before the first run — see README.md.

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="/opt/claude-automations/email-triage"
RUN_USER="${RUN_USER:-openclaw}"

[[ $EUID -eq 0 ]] || { echo "Run as root (sudo)." >&2; exit 1; }

echo "==> Installing Claude Code (if missing)"
if ! sudo -u "$RUN_USER" bash -lc 'command -v claude' >/dev/null 2>&1; then
  curl -fsSL https://claude.ai/install.sh | sudo -u "$RUN_USER" bash || {
    echo "Could not auto-install Claude Code; install it for $RUN_USER manually." >&2
  }
fi

echo "==> Copying automation to $DEST"
install -d -o "$RUN_USER" -g "$RUN_USER" "$DEST" "$DEST/log" "$DEST/secrets"
chmod 700 "$DEST/secrets"
for f in triage.sh triage-prompt.md mcp.gmail.example.json .env.example; do
  install -o "$RUN_USER" -g "$RUN_USER" -m 0644 "$SRC/$f" "$DEST/$f"
done
install -o "$RUN_USER" -g "$RUN_USER" -m 0755 "$SRC/triage.sh" "$DEST/triage.sh"

echo "==> Installing systemd timer"
install -m 0644 "$SRC/systemd/claude-triage.service" /etc/systemd/system/
install -m 0644 "$SRC/systemd/claude-triage.timer"   /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now claude-triage.timer

cat <<EOF

Installed. Before it can run, finish these (see README.md):
  1. cp $DEST/.env.example $DEST/.env   && edit (ANTHROPIC_API_KEY, ALLOWED_TOOLS)
  2. cp $DEST/mcp.gmail.example.json $DEST/mcp.gmail.json   && set your vetted server
  3. Authorize Gmail with READ + LABELS scopes only (creds in $DEST/secrets/)
  4. Create the Gmail labels: Triage/Reply-Needed, Triage/Review, Triage/Noise
  5. Dry run:  sudo -u $RUN_USER $DEST/triage.sh
Check schedule:  systemctl list-timers | grep claude-triage
Audit log:       $DEST/log/actions.ndjson
EOF
