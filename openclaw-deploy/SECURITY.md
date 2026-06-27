# OpenClaw security posture (read before you connect anything)

OpenClaw is a capable agent with shell, file, network, and account access. Its
**defaults are unsafe** (out of the box it can run any shell command with no
allowlist and no approval), and **prompt injection cannot be fully solved** at
the model layer — Anthropic, OpenAI, and Google DeepMind all say so. The goal of
this doc is not "make injection impossible" (you can't); it's **shrink the blast
radius to something you can tolerate.**

> The core threat: the **lethal trifecta** = access to private data
> (Gmail/Calendar) **+** ability to act (write/send/exec) **+** exposure to
> untrusted content (incoming mail, messages, web pages it browses). Hold all
> three and a single malicious email or web page can turn your assistant against
> you. Break the trifecta wherever you can.

---

## Defenses ranked by how much to trust them

### Tier 1 — Structural (trust most; hold regardless of what the model "decides")
These are hard constraints. An injected instruction to exfiltrate or `rm -rf`
simply *fails* if the capability was never granted.

- **Sandbox on** — `OPENCLAW_SANDBOX=1` (set in `.env`; already on in this repo).
- **Tool allowlist + shell approval** — restrict tools to what's needed; require
  human confirmation for shell/`exec`. See `openclaw.hardened.example.jsonc`.
- **Egress allowlisting** — route outbound through a default-deny proxy so a
  hijacked agent can't phone home to an arbitrary host. See
  [Egress hardening](#egress-hardening) — this repo ships it.
- **Least-privilege connectors** — Gmail **read/draft only, never send**; scope
  OAuth tightly; don't grant full filesystem unless a skill needs it.
- **Network isolation** — Control UI on `127.0.0.1` + Tailscale (already set up).

### Tier 2 — Probabilistic (helpful, NOT reliable alone)
- **Content delimiters** marking tool results / messages / web fetches as *data,
  not instructions*. Raises the bar; bypassable, and still maturing upstream
  (OpenClaw issue #62939). Don't depend on it.
- **AI injection filters/classifiers** — catch known patterns; OWASP notes these
  stay bypassable under persistent pressure.

### Tier 3 — Human-in-the-loop (good, with a catch)
- **Approval gates** on destructive/outbound actions. Strong — **but** can be
  defeated if the agent *misframes* the action ("approve this routine calendar
  sync" that's actually an exfil). Gates only help if you actually read them.

---

## Hardening checklist

- [ ] `OPENCLAW_SANDBOX=1` (Tier 1)
- [ ] Tool allowlist set; `exec`/shell requires approval (no auto-approve)
- [ ] **Skills: auto-install OFF**; install only skills whose source you've read
      (prefer your own from this repo). ClawHub has had large malicious-skill
      campaigns — treat it as hostile.
- [ ] Egress proxy enabled (see below); review its logs for unexpected destinations
- [ ] Connectors least-privilege (Gmail read/draft only; never grant send)
- [ ] `channels.*.allowFrom` locked to your own number(s) only
- [ ] No irreversible powers (send money, mass-email, delete) without a real,
      scrutinized human check
- [ ] Control UI never on `0.0.0.0`; reached via Tailscale
- [ ] Auto-patching on (unattended-upgrades + Watchtower) so CVEs close fast

---

## Egress hardening

A default-deny filtering proxy is the highest-value Tier-1 control after the
sandbox: even if the agent is injected, it can only reach allowlisted domains, so
exfiltration and "phone home" are blocked, and every attempt is logged.

Enable it by layering the overlay compose:

```bash
docker compose -f docker-compose.yml -f docker-compose.egress.yml up -d
```

This starts a Squid proxy and points the gateway's `HTTP(S)_PROXY` at it. Edit
the allowlist in `egress/squid.conf` to match the channels you enable (Anthropic
+ your messaging providers are pre-listed; WhatsApp is commented for later).
If a channel won't connect, check what got blocked and add its domain:

```bash
docker compose logs openclaw-egress-proxy
```

**Caveat:** this filters traffic that honors `HTTP(S)_PROXY` (OpenClaw/Node does).
It is a strong application-level control, not an airtight network jail — code that
deliberately dials raw IPs would bypass it, which is exactly why the **sandbox +
tool allowlist** (Tier 1) must also be on so such code can't run in the first
place. For an airtight version, also apply a host-level default-deny outbound
firewall allowing only the proxy, Tailscale, and DNS (advanced; tune per channel).

---

## If you suspect compromise

1. `docker compose stop openclaw-gateway` (halt the agent).
2. Rotate everything it touched: `ANTHROPIC_API_KEY`, `OPENCLAW_GATEWAY_TOKEN`,
   any connector OAuth tokens, and re-pair messaging channels.
3. Review `docker compose logs` and the egress proxy logs for exfil attempts.
4. Restore state from a known-good backup (`/opt/openclaw/backups`).
5. Audit installed skills; remove anything you didn't personally vet.

---

## Bottom line

Run sandboxed, not exposed, patched, egress-allowlisted, least-privilege, with
your own vetted skills and approval gates on anything irreversible — and the
residual risk drops to *"a crafted message could try to manipulate an agent whose
powers I deliberately kept narrow."* That's tolerable for a personal assistant.
The danger zone is the easy default: full account access + send/delete + raw
shell + auto-installed skills. Don't go there.
