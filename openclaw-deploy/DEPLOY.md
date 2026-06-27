# Deploying OpenClaw to the cloud

A runbook for standing up [OpenClaw](https://github.com/openclaw/openclaw) — the
self-hosted personal AI assistant gateway — on a single cloud VM. WhatsApp is
**not** required to get going; this setup leaves the door open to add it (or any
other channel) later with zero rearchitecting.

> Defaults chosen here: **Hetzner VPS + Docker Compose**, with the Control UI
> kept private via **Tailscale**. Both are easy to swap — see
> [Alternatives](#alternatives).

---

## What OpenClaw needs

| Requirement | Detail |
|---|---|
| Runtime | Single always-on container, `ghcr.io/openclaw/openclaw:latest` |
| Resources | ≥ 2 GB RAM (CX22's 4 GB is comfortable) |
| Port | `18789` — the gateway / Control UI (keep it OFF the public internet) |
| State | Persistent dirs for config, workspace, and auth profile |
| Model | A provider key; docs default `model.primary` to an Anthropic Claude model |
| WhatsApp (later) | Pairing scans a QR over `channels login` and stores a WhatsApp Web session on disk — this is why a box with SSH + a persistent volume is the easy path |

Health endpoints (unauthenticated): `GET /healthz` (liveness), `GET /readyz` (readiness).

---

## Why this layout

- **VPS over PaaS** — OpenClaw is stateful and always-on, and adding WhatsApp
  later means an interactive QR pairing plus a long-lived session on disk. A VM
  with SSH and a real volume makes that trivial; ephemeral PaaS makes it fiddly.
- **Hetzner CX22** — 2 vCPU / 4 GB / 40 GB for ~€4/mo is the best price/perf for
  a single container of this size.
- **Tailscale for the UI** — the Control UI on `18789` is sensitive. Keeping it
  bound to `127.0.0.1` and reaching it over a private tailnet means **nothing is
  publicly exposed**. (Caddy + TLS + basic auth is provided as an alternative.)

---

## Steps

### 1. Provision

Create a Hetzner Cloud **CX22**, image **Ubuntu 24.04**, and add your SSH key.
Pick a region near you (Ashburn/US or any EU site).

### 2. Bootstrap the box

SSH in as `root` and run the provisioning script (creates a non-root user,
firewall, Docker + Compose, Tailscale, and the state dirs):

```bash
# copy setup.sh up first, or paste it, then:
bash setup.sh
tailscale up        # join your tailnet
```

### 3. Configure

As the `openclaw` user, drop this directory's files on the server and create the
env file:

```bash
cp .env.example .env
openssl rand -hex 32        # paste into OPENCLAW_GATEWAY_TOKEN
nano .env                   # set ANTHROPIC_API_KEY + the token
```

### 4. Launch

```bash
docker compose up -d openclaw-gateway
docker compose logs -f openclaw-gateway      # watch it come up
curl -fsS http://127.0.0.1:18789/readyz      # expect a 200
```

### 5. Reach the Control UI

Over Tailscale, browse to `http://<host-tailscale-name>:18789/`. No tailnet yet?
Tunnel over SSH instead:

```bash
ssh -L 18789:127.0.0.1:18789 openclaw@<server-ip>
# then open http://127.0.0.1:18789/ in your local browser
```

### 6. First channel (optional, recommended for testing)

Telegram is the lowest-friction first channel — create a bot with @BotFather and:

```bash
docker compose run --rm openclaw-cli channels add --channel telegram --token "<bot-token>"
```

Message the bot; you should get a reply from your assistant.

### 7. Backups

Nightly tar of the state dir to object storage (or enable Hetzner snapshots):

```bash
tar czf /opt/openclaw/backup-$(date +%F).tgz \
  /opt/openclaw/config /opt/openclaw/workspace /opt/openclaw/auth
```

---

## Adding WhatsApp later

No infra changes — when Meta access and a spare number are ready:

```bash
docker compose run --rm openclaw-cli channels login   # scan the QR
# then allowlist your number in the config:
#   channels.whatsapp.allowFrom: ["+1XXXXXXXXXX"]
docker compose up -d openclaw-gateway                 # reload
```

The WhatsApp Web session persists in the auth volume, so it survives restarts
and image upgrades.

---

## Wiring in your skills (later)

OpenClaw consumes AgentSkills-compatible `SKILL.md` folders — the **same format
the rest of this repo uses** (`london-art-show/`, `product-research/`). To make
them available to the assistant, mount or copy them into the workspace skills
dir, e.g.:

```bash
git clone https://github.com/jalbertson-dev/ai-skills.git \
  /opt/openclaw/workspace/skills
```

Then reference them from the workspace config. (OpenClaw can also pull skills
on demand from its ClawHub registry.)

---

## Alternatives

| Swap | How |
|---|---|
| **Fly.io** instead of Hetzner | `fly launch` with a 2 GB machine + a volume mounted at `/home/node/.openclaw`; use `fly ssh console` for the WhatsApp QR step. |
| **Railway/Render** | Deploy the image with a persistent volume; works, but the interactive pairing and always-on cost are less convenient. |
| **Caddy public TLS** instead of Tailscale | Point DNS at the box, run `setup.sh` with `ENABLE_HTTP=yes`, and use the included `Caddyfile` (TLS + basic auth). |
| **Official setup script** instead of this compose | On the box, run OpenClaw's `scripts/docker/setup.sh`, which auto-generates compose + onboarding. This file mirrors what it produces. |

---

## Security checklist

- [ ] Control UI (`18789`) never published to `0.0.0.0` without a proxy
- [ ] `.env` is git-ignored and `chmod 600`
- [ ] Strong `OPENCLAW_GATEWAY_TOKEN` (`openssl rand -hex 32`)
- [ ] `OPENCLAW_SANDBOX=1` so the agent runs sandboxed
- [ ] Firewall denies all inbound except SSH (+ 80/443 only if using Caddy)
- [ ] SSH is key-only; consider moving it behind Tailscale too
- [ ] Backups verified to restore
