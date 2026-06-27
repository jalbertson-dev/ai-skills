#!/usr/bin/env bash
#
# Nightly local backup of OpenClaw state (config, workspace, auth — including
# the WhatsApp Web session once paired). Run by a systemd timer. Keeps the last
# 7 archives and prunes older ones.
#
# NOTE: this is a LOCAL backup on the same disk — good for "oops I broke the
# config" recovery, NOT for total host loss. For offsite durability, also enable
# Hetzner's automated Backups in the Cloud Console (see DEPLOY.md), or push the
# archive to object storage (rclone/aws s3) by extending this script.

set -euo pipefail

SRC_DIRS=(/opt/openclaw/config /opt/openclaw/workspace /opt/openclaw/auth)
DEST="/opt/openclaw/backups"
KEEP=7
STAMP="$(date +%F-%H%M)"
ARCHIVE="$DEST/openclaw-$STAMP.tgz"

mkdir -p "$DEST"
tar czf "$ARCHIVE" "${SRC_DIRS[@]}" 2>/dev/null
echo "Wrote $ARCHIVE ($(du -h "$ARCHIVE" | cut -f1))"

# Prune all but the newest $KEEP archives.
ls -1t "$DEST"/openclaw-*.tgz 2>/dev/null | tail -n +$((KEEP + 1)) | xargs -r rm -f
