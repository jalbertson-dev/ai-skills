# claude-automations

Scheduled automations powered by **Claude Code headless** (`claude -p`), running
on the hardened VPS from [`../openclaw-deploy`](../openclaw-deploy). Each
automation is a self-contained folder with its own runner, prompt, MCP config,
systemd timer, and installer.

| Automation | What it does |
|---|---|
| [email-triage](./email-triage) | Classify recent Gmail into `Triage/*` labels + a digest. Read + label only (no send/delete). |

## Shared principles

- **Headless + scheduled:** `claude -p --bare` under a systemd timer (mirrors the
  timer pattern in `openclaw-deploy/setup.sh`).
- **Least privilege:** lock `--allowedTools` and MCP scopes to exactly what the
  job needs; `--permission-mode dontAsk` denies the rest.
- **Untrusted input is data, not instructions:** every automation that reads
  external content (email, web) must refuse instructions embedded in that
  content — the lethal-trifecta rule from `openclaw-deploy/SECURITY.md`.
- **Auditability:** append-only action logs; review before trusting unattended.
- **Same dev loop:** author here → PR → the `skills-ci` gate → merge → box pulls.
