# skills-ci — pre-merge test harness for Agent Skills

This shifts OpenClaw's recommended "test before prod" beat **left into CI**: it
runs on every pull request (`.github/workflows/skills-ci.yml`) so a structurally
broken, oversized, or risky `SKILL.md` cannot be merged — and therefore cannot be
pulled to the live agent. The PR review *is* the gate.

## What it covers (deterministic, no secrets)

`validate.py` checks every `*/SKILL.md`:

**Errors (block merge)**
- Valid YAML frontmatter with required `name` + `description`
- `name` unique across skills
- Non-empty body; SKILL.md within OpenClaw's 40,000-byte ceiling
- No hardcoded secrets (Anthropic/AWS/GitHub/Slack tokens, private keys)

**Warnings (reported, non-blocking)**
- `name` != directory name
- description too short/long
- Risky instruction patterns (`curl | sh`, "ignore previous instructions",
  attempts to disable sandbox/approvals, destructive shell)

The workflow also runs `make` to confirm every skill still builds into its
`.skill` bundle.

## What it does NOT do

It does **not** prove a skill behaves correctly. LLM behavior is
non-deterministic, so true behavioral correctness still needs the **staging /
enable beat on the box** (pull in disabled → test with `openclaw agent
--message "..."` → enable). This harness raises the floor; it doesn't guarantee
quality.

## Run it locally

```bash
pip install pyyaml
python3 skills-ci/validate.py .
```

## Optional Tier B: behavioral smoke test (opt-in)

For a deeper gate you can add a second job that boots the OpenClaw container and
sends a known prompt to a skill via skill-testing mode, asserting it loads and
triggers without error. It needs an `ANTHROPIC_API_KEY` repo secret and is
best-effort (non-deterministic), so it's intentionally not enabled by default.
Sketch:

```yaml
  smoke:
    runs-on: ubuntu-latest
    # Guard so forks / secretless runs skip instead of failing:
    steps:
      - uses: actions/checkout@v4
      - name: Skip if no key
        id: gate
        run: |
          if [ -z "${{ secrets.ANTHROPIC_API_KEY }}" ]; then
            echo "run=false" >> "$GITHUB_OUTPUT"
          else
            echo "run=true" >> "$GITHUB_OUTPUT"
          fi
      - name: Smoke-test a skill
        if: steps.gate.outputs.run == 'true'
        env:
          ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
        run: |
          docker run --rm -e ANTHROPIC_API_KEY \
            -v "$PWD/product-research:/skill:ro" \
            ghcr.io/openclaw/openclaw:latest \
            agent --message "best kids ski goggles" --dry-run
```

Verify the exact `openclaw agent` / skill-testing flags against your installed
version before enabling.
