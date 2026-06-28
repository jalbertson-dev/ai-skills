# AI Skills

A collection of Agent Skills for Claude and compatible AI tools, using the open [Agent Skills](https://agentskills.io) SKILL.md standard.

## Skills

| Skill | Description |
|-------|-------------|
| [product-research](./product-research) | Find the best products by analysing independent editorial reviews |

## Deployment

| Guide | Description |
|-------|-------------|
| [openclaw-deploy](./openclaw-deploy) | Stand up a self-hosted [OpenClaw](https://github.com/openclaw/openclaw) personal AI assistant in the cloud (Docker Compose on a VPS), ready to load these skills |

## Installation

### Claude.ai

Download the `.skill` file for the skill you want from its directory (e.g. `product-research/product-research.skill`), then go to **Settings → Capabilities → Skills → Add → Upload a skill** and upload it.

Or install any skill directly without building:
1. Go to **Settings → Capabilities → Skills → Add → Write skill instructions**
2. Copy the contents of `<skill-name>/SKILL.md` into the skill editor

### Claude Code

```bash
# Clone the whole repo into your personal skills directory
git clone https://github.com/YOUR_USERNAME/ai-skills.git ~/.claude/skills

# Or for a specific project
git clone https://github.com/YOUR_USERNAME/ai-skills.git .claude/skills
```

### Other compatible tools

All skills use the open [Agent Skills](https://agentskills.io) SKILL.md standard and are compatible with Codex CLI, Gemini CLI, Cursor, and other supporting tools.

## Authoring a new skill

1. **Create a directory** for your skill:
   ```bash
   mkdir my-skill
   ```

2. **Write the skill definition** in `my-skill/SKILL.md` with frontmatter:
   ```markdown
   ---
   name: my-skill
   description: >
     Describe when to trigger this skill. The AI uses this to decide when
     to activate it, so be specific about trigger phrases and use cases.
   ---

   # My Skill

   Your skill instructions here...
   ```

3. **Document it** in `my-skill/README.md` covering what it does, example prompts, and any limitations.

4. **Build it**:
   ```bash
   make my-skill
   # outputs dist/my-skill.skill
   ```

5. **Add it to the table** in this README.

## Building

```bash
make          # build all skills
make <name>   # build a single skill (e.g. make product-research)
make clean    # remove built artifacts
```

Built `.skill` files are written into each skill's directory (e.g. `product-research/product-research.skill`) and committed to the repo so they can be downloaded and shared directly.

## SKILL.md format

Each skill requires a `SKILL.md` file with a YAML frontmatter block followed by the skill instructions in Markdown:

```markdown
---
name: skill-name
description: >
  Natural language description of when to trigger this skill. Include
  specific trigger phrases and use cases. Also describe what NOT to use
  it for to reduce false positives.
---

# Skill Name

The instructions Claude will follow when this skill is active...
```

See any existing skill's `SKILL.md` for a complete example.

## Contributing

Contributions of new skills or improvements to existing ones are welcome. Please open a PR with:

- A new skill directory following the structure above, or
- Improvements to an existing skill's `SKILL.md` or `README.md`

## License

MIT — use it however you like.
