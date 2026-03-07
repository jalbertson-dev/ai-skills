# Product Research Skill

An Agent Skill that helps you find the best products by analysing independent editorial reviews — cutting through affiliate spam, retailer reviews, and AI-generated listicles to find recommendations backed by genuine hands-on testing.

## What it does

Give it a product category and your requirements, and it will:

1. **Search** for high-quality editorial review sources (Wirecutter, Outdoor Gear Lab, Consumer Reports, RTINGS, Switchback Travel, GearJunkie, and dozens more)
2. **Read** the full articles, not just snippets
3. **Cross-reference** products across multiple independent sources
4. **Synthesise** findings into clear recommendations with source-by-source evidence
5. **Show its work** — every recommendation links back to the review that supports it, and excluded sources are listed with reasons

## Example prompts

- "What's the best laptop for software development under £1500?"
- "Best kids ski goggles for a 5 year old"
- "Help me choose running shoes for trail running in wet conditions"
- "What's the best robot vacuum? I have pets and hardwood floors"
- "Recommend underwear — I run hot and want something breathable"

## Output format

For each query you get:

- **Research summary** — what was searched, how many sources consulted, coverage landscape
- **Top recommendations** (2–4 picks) differentiated by use case, each with:
  - Source-by-source review evidence with attribution and links
  - Consensus summary showing where reviewers agree/disagree
  - Key strengths, watch-outs, and price range
- **Key tradeoffs** — what you gain and lose with each choice
- **Sources consulted** — full list with methodology notes
- **Sources excluded** — transparency on what was skipped and why

## Source quality tiers

The skill prioritises sources in three tiers:

| Tier | Sources | Why |
|------|---------|-----|
| **Tier 1 — Gold standard** | Wirecutter, Outdoor Gear Lab, Consumer Reports, RTINGS, Tom's Hardware/Guide | Rigorous methodology, buy their own products, extensive hands-on testing |
| **Tier 2 — Strong editorial** | GearJunkie, Switchback Travel, The Verge, Ars Technica, Serious Eats, Which?, Good Housekeeping Institute, and more | Trustworthy editorial teams with transparent testing processes |
| **Tier 3 — Use with caution** | Specialist blogs with demonstrated expertise | Noted as single-source when used |

**Always excluded:** Amazon/retailer reviews, brand websites, affiliate listicles without hands-on testing, AI-generated roundups.

## Installation

### Claude.ai

Build and upload the skill:

```bash
make product-research
```

Then go to **Settings → Capabilities → Skills → Add → Upload a skill** and upload `dist/product-research.skill`.

Or install directly:
1. Go to **Settings → Capabilities → Skills → Add → Write skill instructions**
2. Copy the contents of `SKILL.md` into the skill editor

### Claude Code

```bash
# Clone the whole skills repo into your personal skills directory
git clone https://github.com/YOUR_USERNAME/ai-skills.git ~/.claude/skills

# Or for a specific project
git clone https://github.com/YOUR_USERNAME/ai-skills.git .claude/skills
```

## How it works

The skill instructs Claude to:

1. **Ask clarifying questions** if the query is too broad (e.g., "best laptop" → "what's your primary use case and budget?")
2. **Run multiple targeted searches** using patterns like `best [product] [year] site:wirecutter.com`
3. **Fetch and read full review articles** — not just search snippets
4. **Track products across sources** — building a cross-reference map of which products appear where and what each source says
5. **Synthesise with transparency** — every claim links back to its source, and disagreements between reviewers are surfaced

## Design decisions

- **No retailer reviews, ever.** Amazon reviews, John Lewis, Argos, etc. are explicitly excluded. Retailer reviews mix genuine feedback with incentivised reviews and don't involve comparative testing.
- **Recency matters.** The skill flags when the most recent review is over 18 months old.
- **Honesty about gaps.** If independent reviews are scarce for a category, the skill says so rather than padding with low-quality sources.
- **UK-aware.** Notes UK availability and pricing where relevant (configurable based on user location).
- **Copyright-respecting.** Direct quotes are kept under 15 words with full attribution. The skill paraphrases and links rather than reproducing review content.

## Limitations

- Depends on web search access — works in Claude.ai (with web search enabled), Claude Code, and API with tools
- Quality of output depends on the review landscape for the category — well-reviewed categories (electronics, outdoor gear) produce richer results than niche products
- Cannot access paywalled content (e.g., some Consumer Reports articles)
- Not designed for price comparison, deal-finding, or price tracking — this is about finding the *best product*, not the *best price*

## Contributing

Suggestions for improving the skill are welcome! Key areas:

- **Additional trusted review sources** for specific categories (especially non-English-language markets)
- **Category-specific search strategies** that work better than the general patterns
- **Output format improvements** based on your experience using the skill
