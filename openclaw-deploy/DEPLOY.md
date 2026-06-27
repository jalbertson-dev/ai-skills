# Deploying OpenClaw to Hetzner Cloud (low-maintenance edition)

A runbook for standing up [OpenClaw](https://github.com/openclaw/openclaw) — the
self-hosted personal AI assistant — on a single Hetzner VPS, set up so it
**runs itself**: security patches, reboots, image updates, backups, log
rotation, and host-down alerting are all automated at provision time. WhatsApp
is **not** required to get going and slots in later with no infra changes.

> UI access is kept private via **Tailscale** (nothing exposed to the public
> internet). A Caddy public-TLS alternative is included if you prefer.

---

## Who does what

| | |
|---|---|
| **Only you can do** (account, hardware, secrets) | Steps 1–4 below |
| **Already done for you** (committed in this folder) | Hardened `setup.sh`, `docker-compose.yml` w/ auto-updates, maintenance scripts, systemd timers, this runbook |

I can't provision the server, hold your API keys, or scan QR codes — those are
inherently yours. Everything that *can* be codified already is.

---

## What OpenClaw needs

| Requirement | Detail |
|---|---|
| Runtime | One always-on container, `ghcr.io/openclaw/openclaw:latest` |
| RAM | **4 GB** runs a text-only agent; **8 GB** if skills do browser automation |
| Port | `18789` Control UI — kept on `127.0.0.1`, reached via Tailscale |
| State | Persistent dirs for config, workspace, auth (WhatsApp session lives here) |
| Model | An Anthropic API key (docs default `model.primary` to a Claude model) |

Health endpoints: `GET /healthz` (liveness), `GET /readyz` (readiness).

---

## Your manual steps (~20 minutes, one time)

### 1. Hetzner account + server
- Sign up at [console.hetzner.cloud](https://console.hetzner.cloud), create a project.
- **Create server:**
  - Image: **Ubuntu 24.04**
  - Type: **CX32** (4 vCPU / 8 GB) recommended so browser-automation skills work
    later without resizing; **CX22** (2 vCPU / 4 GB) is fine for text-only.
  - Location: pick a US (Ashburn/Hillsboro) or EU region near you.
  - **SSH key: add yours at creation** ← important; it lets `setup.sh` lock down
    SSH safely. (Without it, password login is left on so you aren't locked out.)
  - **Backups: tick the "Backups" box** (automated offsite snapshots, ~20% surcharge).
    This is your protection against total host loss — don't skip it.

### 2. Get an Anthropic API key
From [console.anthropic.com](https://console.anthropic.com) → API Keys.

### 3. (Recommended, free) Create monitors
- **healthchecks.io** — make a check (period 5m, grace 5m), copy its ping URL.
  This is your "tell me if the host dies" alert.
- **Tailscale** account (free) if you don't have one — for private UI access.

### 4. Bootstrap the box
SSH in as `root` and run the provisioning script:

```bash
ssh root@<server-ip>
git clone https://github.com/jalbertson-dev/ai-skills.git
cd ai-skills/openclaw-deploy
bash setup.sh
```

`setup.sh` creates the `openclaw` user, locks down SSH, sets up the firewall,
Docker, Tailscale, auto-updates+reboot, log rotation, and the backup/heartbeat
timers. Then, **as the `openclaw` user**:

```bash
tailscale up --ssh                       # join tailnet (--ssh = you can drop port 22 later)
cp .env.example .env
openssl rand -hex 32                      # paste into OPENCLAW_GATEWAY_TOKEN
nano .env                                 # set ANTHROPIC_API_KEY, token, HEALTHCHECKS_URL
sudo cp .env /opt/openclaw/.env           # heartbeat timer reads it from here
docker compose up -d openclaw-gateway watchtower
curl -fsS http://127.0.0.1:18789/readyz   # expect 200
```

Open the Control UI at `http://<host-tailscale-name>:18789/` over Tailscale.
No tailnet? Tunnel instead: `ssh -L 18789:127.0.0.1:18789 openclaw@<server-ip>`.

### 5. (Optional) First channel — Telegram is easiest
Create a bot with @BotFather, then:
```bash
docker compose run --rm openclaw-cli channels add --channel telegram --token "<bot-token>"
```

---

## What runs itself (no babysitting)

| Chore | How it's handled |
|---|---|
| **OS security patches** | `unattended-upgrades`, auto-applied |
| **Kernel-update reboots** | Automatic, nightly at 04:00 |
| **OpenClaw image updates** | **Watchtower**, weekly, prunes old images |
| **Crash recovery** | `restart: unless-stopped` + healthcheck; Docker `live-restore` |
| **Disk from logs** | Docker logs capped at 10 MB × 3 per container |
| **Backups (local)** | Nightly tar of state → `/opt/openclaw/backups`, keeps 7 |
| **Backups (offsite)** | Hetzner Backups checkbox (step 1) — survives host loss |
| **Host-down alerting** | Heartbeat pings healthchecks.io every 5 min; silence → alert |
| **Brute-force SSH** | `fail2ban` + key-only SSH + `ufw` deny-all-but-SSH |

Realistic ongoing touch: **near zero**. The one thing automation can't decide
for you is whether to trust an auto-update — if you'd rather review releases,
pin `OPENCLAW_IMAGE` to a date tag in `.env` and skip the `watchtower` service.

---

## Adding WhatsApp later (no infra change)

```bash
docker compose run --rm openclaw-cli channels login   # scan the QR over SSH
# then allowlist your number in the config: channels.whatsapp.allowFrom: ["+1XXXXXXXXXX"]
docker compose up -d openclaw-gateway
```
The WhatsApp Web session persists in the auth volume and is included in backups.

## Wiring in your skills (later)

OpenClaw uses the same `SKILL.md` format as the rest of this repo. Make them
available to the assistant:
```bash
git clone https://github.com/jalbertson-dev/ai-skills.git /opt/openclaw/workspace/skills
```

---

## Verifying the automation is live

```bash
systemctl status unattended-upgrades                 # patching active
systemctl list-timers | grep openclaw                # backup + heartbeat timers
docker ps                                            # gateway + watchtower up
cat /etc/docker/daemon.json                           # log rotation + live-restore
sudo ufw status                                       # only SSH (+ 80/443 if Caddy)
```

## Security checklist

- [ ] SSH key added at server creation → password auth disabled by `setup.sh`
- [ ] Hetzner Backups enabled (offsite durability)
- [ ] `HEALTHCHECKS_URL` set so you're alerted on host death
- [ ] Control UI never published to `0.0.0.0`; reached via Tailscale
- [ ] Strong `OPENCLAW_GATEWAY_TOKEN` (`openssl rand -hex 32`)
- [ ] `.env` is `chmod 600` and git-ignored
- [ ] (Optional) once on Tailscale, drop the public SSH port for an even smaller surface

---

## Alternatives

| Swap | How |
|---|---|
| **Public HTTPS** instead of Tailscale | Run `setup.sh` with `ENABLE_HTTP=yes`, point DNS at the box, use the included `Caddyfile` (TLS + basic auth). |
| **Manual updates** instead of Watchtower | Pin `OPENCLAW_IMAGE` to a date tag; don't start the `watchtower` service. |
| **Official setup script** | OpenClaw's own `scripts/docker/setup.sh` auto-generates compose + onboarding; this compose mirrors it. |
