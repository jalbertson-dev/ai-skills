#!/usr/bin/env bash
#
# Health heartbeat / dead-man's switch. Run every 5 min by a systemd timer.
# Checks the gateway is ready, then pings an external monitor (healthchecks.io
# or any URL). If the host dies or the gateway stops, the ping stops arriving
# and the monitor alerts you — no need to watch the box yourself.
#
# Configure by setting HEALTHCHECKS_URL in /opt/openclaw/.env, e.g.
#   HEALTHCHECKS_URL=https://hc-ping.com/your-uuid
# Create a free check at https://healthchecks.io (period 5m, grace 5m).

set -uo pipefail

URL="${HEALTHCHECKS_URL:-}"
[[ -z "$URL" ]] && exit 0   # no monitor configured; nothing to do

if curl -fsS --max-time 10 http://127.0.0.1:18789/readyz >/dev/null 2>&1; then
  curl -fsS --max-time 10 "$URL" >/dev/null 2>&1 || true
else
  # Signal failure to the monitor (healthchecks.io supports /fail).
  curl -fsS --max-time 10 "${URL%/}/fail" >/dev/null 2>&1 || true
fi
