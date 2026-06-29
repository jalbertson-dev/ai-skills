# Gmail Triage Skill

An Agent Skill that keeps a Gmail inbox sorted **unattended**. Each run it
scans for messages it hasn't seen yet, classifies them, routes each to its
destination, and labels it done so the next run skips it — designed to be
fired on a schedule with zero servers to maintain.

## What it does

For every unprocessed thread it:

1. **Classifies** it into one category: calendar event / ticket, receipt,
   health, news, action item, or none.
2. **Routes** it to that category's destination.
3. **Labels** it `triaged` (+ `triaged/<category>`) so it's never
   reprocessed — idempotency lives in Gmail, not in the session.

| Category | Default destination | Setup needed |
|----------|--------------------|--------------|
| Calendar events / tickets | Google Calendar event | ✅ None |
| Receipts / invoices | Google Drive log file | ✅ None |
| Health info | Separate (restricted) Drive log | ✅ None |
| News / newsletters | Read-later app (Readwise/Instapaper) | ⚠️ API token + egress |
| Action items | Todo app (Todoist/TickTick) | ⚠️ API token + egress |

The two Google destinations work out of the box with the Gmail / Calendar /
Drive connectors. The read-later and todo destinations are wired but
**off by default** — enable them in CONFIG once you've added an API token
and your environment allows egress to the provider. Until then those
categories are still classified and labeled, so the backlog is easy to find
later by its `triaged/<category>` label.

## Why label-based idempotency

Each scheduled run is a fresh, stateless session. The skill searches
`in:inbox ... -label:triaged`, acts, then applies `triaged` **only after**
the destination action succeeds. If a run dies halfway or a destination
errors, the affected threads stay unlabeled and are retried next run. That
makes every run safe to re-run and means you never need persistent state
between runs.

## Configuration

Everything you'd tune lives in the **CONFIG** block at the top of
[`SKILL.md`](./SKILL.md): the inbox search window, the per-category
destination map (set any to `off` to disable), calendar ID, Drive log
filenames, label names, and the per-run thread cap. Edit that block; leave
the rest.

Sensible first cut: keep `news` and `action` set to `off`, run with just the
Google destinations until you trust it, then enable the hooks.

## Running it always-on (Option A — Claude Code on the web)

This skill is built for **scheduled triggers** in Claude Code on the web —
no box to keep alive.

1. Make sure the **Gmail, Google Calendar, and Google Drive** connectors
   are enabled for the environment.
2. Create a **scheduled trigger** (e.g. every 30 minutes) whose prompt is
   simply: `/gmail-triage` (or "Run inbox triage"). Each firing starts a
   fresh session, runs this skill, and exits.
3. The session must be allowed to **act without prompting** (it creates
   calendar events and writes Drive files on its own). The skill's safety
   rails keep it non-destructive: it never sends mail, never deletes, never
   archives, and only appends to Drive logs.

See the trigger/session docs:
<https://code.claude.com/docs/en/claude-code-on-the-web>

> Prefer to self-host instead? The same skill runs unchanged from a cron job
> or `systemd` timer on a VPS — see [`../openclaw-deploy`](../openclaw-deploy)
> for a hardened always-on host you can point a headless `claude -p
> "/gmail-triage"` at.

## Installation

### Claude.ai
Download [`gmail-triage.skill`](./gmail-triage.skill) from this directory,
then go to **Settings → Capabilities → Skills → Add → Upload a skill**.

Or paste the contents of [`SKILL.md`](./SKILL.md) into
**Settings → Capabilities → Skills → Add → Write skill instructions**.

### Claude Code
```bash
git clone https://github.com/YOUR_USERNAME/ai-skills.git ~/.claude/skills
```

## Safety model

- **Never sends, replies, forwards, deletes, or archives** — labels only.
- **Drive logs are append-only** — never overwritten or emptied.
- **Health data is isolated** to its own restricted log and kept out of
  calendar titles, the receipts log, and the run summary.
- **Bounded** by `max_threads_per_run` per run.
- **Fails safe** — anything unclear or errored is left untriaged for retry,
  not guessed.

## Limitations

- Read-later and todo destinations need an API token and outbound network
  access to the provider — both are governed by your environment's network
  policy.
- Drive "append" is a read-modify-write of a Markdown log file; for very
  high volumes a Sheet or database would scale better (not wired here).
- Classification is best-effort. The priority rules bias toward not losing
  important items (calendar/health/action win ties), which can occasionally
  over-file a borderline newsletter as an action item.
- Scheduling granularity and run cost are bound by your Claude Code on the
  web plan.

## Contributing

Useful additions: more read-later / todo providers, a Google Sheets
destination for receipts, and category rules tuned to specific senders.
