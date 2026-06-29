#!/usr/bin/env bash
#
# Email triage automation — runs Claude Code headless to classify recent Gmail
# and apply Triage/* labels. Read + label only; it cannot send, reply, or delete
# (those tools are not in --allowedTools and the Gmail MCP scopes exclude them).
#
# Designed to run on a schedule via systemd (see systemd/claude-triage.timer).
# Keeps an append-only action log so you can audit everything it did.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Load config (.env next to this script). Required: ANTHROPIC_API_KEY.
# Optional: GMAIL_MCP_CONFIG, ALLOWED_TOOLS, TELEGRAM_BOT_TOKEN/_CHAT_ID, LOG_DIR.
[[ -f "$HERE/.env" ]] && set -a && . "$HERE/.env" && set +a

: "${ANTHROPIC_API_KEY:?set ANTHROPIC_API_KEY in .env}"
MCP_CONFIG="${GMAIL_MCP_CONFIG:-$HERE/mcp.gmail.json}"
PROMPT_FILE="${PROMPT_FILE:-$HERE/triage-prompt.md}"
LOG_DIR="${LOG_DIR:-/opt/claude-automations/email-triage/log}"
# Least privilege: ONLY the Gmail read/label tools. Match these names to your
# installed Gmail MCP server (placeholders below). No send/delete tool is listed.
ALLOWED_TOOLS="${ALLOWED_TOOLS:-mcp__gmail__search_messages,mcp__gmail__read_message,mcp__gmail__modify_labels}"

mkdir -p "$LOG_DIR"
STAMP="$(date -u +%FT%TZ)"
ACTION_LOG="$LOG_DIR/actions.ndjson"      # append-only audit trail
RUN_OUT="$LOG_DIR/last-run.json"

# --bare         : deterministic scripted run (no local hooks/CLAUDE.md/etc.)
# --permission-mode dontAsk : deny anything not explicitly allowed / not read-only
# --allowedTools : the only write capability is applying a Triage/* label
# --output-format json : parseable result + cost metadata
if ! claude -p "$(cat "$PROMPT_FILE")" \
      --bare \
      --permission-mode dontAsk \
      --allowedTools "$ALLOWED_TOOLS" \
      --mcp-config "$MCP_CONFIG" \
      --output-format json > "$RUN_OUT" 2>"$LOG_DIR/stderr.log"; then
  echo "{\"ts\":\"$STAMP\",\"status\":\"error\",\"see\":\"$LOG_DIR/stderr.log\"}" >> "$ACTION_LOG"
  echo "triage run FAILED — see $LOG_DIR/stderr.log" >&2
  exit 1
fi

DIGEST="$(jq -r '.result // "(no result)"' "$RUN_OUT")"
COST="$(jq -r '.total_cost_usd // 0' "$RUN_OUT" 2>/dev/null || echo 0)"

# Append-only audit entry.
jq -nc --arg ts "$STAMP" --arg digest "$DIGEST" --arg cost "$COST" \
  '{ts:$ts, status:"ok", cost_usd:($cost|tonumber), digest:$digest}' >> "$ACTION_LOG"

echo "[$STAMP] triage done (cost \$$COST)"
echo "$DIGEST"

# Optional: push the digest to your phone via Telegram (no Gmail send scope needed).
if [[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]]; then
  curl -fsS --max-time 15 \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=📬 Inbox triage ${STAMP}
${DIGEST}" >/dev/null || echo "warn: telegram push failed" >&2
fi
