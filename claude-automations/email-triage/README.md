# Email inbox triage (Claude Code automation)

Runs **Claude Code headless** on a schedule to classify recent Gmail into
`Triage/Reply-Needed`, `Triage/Review`, and `Triage/Noise` labels, and emits a
short digest. **Read + label only** — it cannot send, reply, forward, or delete.

This is the first of the `claude-automations/`. It reuses the hardened Hetzner
host, security posture, and dev loop from `openclaw-deploy/`.

> Defaults (the question tool dropped mid-setup, so these are the recommended
> options I went with — all easy to change):
> **scope** = label + digest (read/label-only) · **runner** = headless
> `claude -p` + systemd timer · **host** = the hardened Hetzner box.

## How it works

```
systemd timer → triage.sh → claude -p --bare --permission-mode dontAsk
                              --allowedTools <gmail read/label tools>
                              --mcp-config mcp.gmail.json
                            → applies Triage/* labels + prints a digest
                            → append-only log + optional Telegram push
```

- **`triage-prompt.md`** — the instructions, including hard anti-injection rules.
- **`triage.sh`** — the runner (locked tools, JSON output, audit log).
- **`mcp.gmail.example.json`** — Gmail MCP server config (least-privilege scopes).
- **`systemd/`** — service + timer (3×/day by default).
- **`install.sh`** — installs it onto the box.

## Why this is the safe shape (important)

Email triage is a **textbook prompt-injection target**: you feed an agent
untrusted content (emails) while it has tools and account access — the lethal
trifecta, pointed at your inbox. Mitigations are baked in:

1. **Gmail scopes = `gmail.readonly` + `gmail.labels` only.** No send, no delete.
   With read/label-only scopes a good Gmail MCP server exposes only a handful of
   tools, none destructive.
2. **`--allowedTools` lists only read + label tools**, and `--permission-mode
   dontAsk` denies everything else — so even a convincing injected instruction
   has no tool to act through.
3. **The prompt treats email content as untrusted data** and refuses to follow
   instructions found inside messages (flagging suspected injection as Noise).
4. **Append-only action log** (`log/actions.ndjson`) — full audit of every run.
5. Runs on the hardened box; route it through the egress allowlist proxy too.

## Setup

1. Provision + harden the host (see `../../openclaw-deploy/DEPLOY.md`).
2. `sudo bash install.sh`
3. `cp .env.example .env` → set `ANTHROPIC_API_KEY` and `ALLOWED_TOOLS` (match
   your Gmail MCP server's tool names).
4. `cp mcp.gmail.example.json mcp.gmail.json` → set a **vetted** Gmail MCP server
   (read its source first) and the **read + labels** scopes.
5. Authorize Gmail (OAuth) with those scopes; store creds in `secrets/`.
6. In Gmail, create labels: `Triage/Reply-Needed`, `Triage/Review`, `Triage/Noise`.
7. Dry run once: `sudo -u openclaw /opt/claude-automations/email-triage/triage.sh`
8. Watch it: `systemctl list-timers | grep claude-triage`, audit `log/actions.ndjson`.

## Tuning the cadence

Edit `systemd/claude-triage.timer` (`OnCalendar`). Default `08,13,18:07`;
hourly = `OnCalendar=*-*-* *:07`.

## Extending later (deliberately, not by default)

- **Draft replies** for Reply-Needed: add the `gmail.compose` scope + the draft
  tool to `ALLOWED_TOOLS`, and a prompt step. Drafts are not sends — you still
  review and send. (Never add `gmail.send`.)
- **Auto-archive noise:** add the modify/archive tool + scope, and an explicit
  approval/dry-run period first.

## Caveats (honest)

- **Tool names in `ALLOWED_TOOLS` / `mcp.gmail.json` are placeholders** — set
  them to your chosen server's actual names and verify against its docs.
- This validates structurally but the behavioral quality of triage is
  non-deterministic — run it in dry-run/observe mode for a few days, read the
  action log, and adjust the prompt before trusting it unattended.
