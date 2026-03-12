# London Art Show Research Skill

An Agent Skill that aggregates information, reviews, previews, and images for art shows and exhibitions in London — giving you a complete critical briefing before you visit.

## What it does

Give it the name of a London art exhibition and it will:

1. **Find key details** — venue, dates, ticket prices, opening hours, booking info
2. **Read every major review** — from The Guardian, FT, Telegraph, Time Out, Apollo, Frieze, and more
3. **Extract star ratings and key insights** from each critic
4. **Aggregate previews and features** — curator interviews, first looks, and behind-the-scenes pieces
5. **Identify standout works** — the must-see pieces highlighted across multiple reviews
6. **Summarise the art** — type, medium, period, themes, and who it will appeal to
7. **Provide practical tips** — best times to visit, how long to allow, nearby shows to combine

## Example prompts

- "Tell me about the Michelangelo show at the British Museum"
- "Reviews for the new Tate Modern exhibition"
- "Is the Serpentine Gallery show worth seeing?"
- "What's on at the Royal Academy right now?"
- "London art show reviews for the Van Gogh exhibition at the Courtauld"

## Output format

For each query you get:

- **Exhibition overview** — the headline critical consensus in 3-5 sentences
- **Key details** — venue, dates, tickets, hours, booking in a quick-reference table
- **About the art** — type, themes, scope, and who it's for
- **Reviews** — every major review listed with critic name, star rating, key quote, and paraphrased insights
- **Critical consensus** — where reviewers agree and disagree, overall rating range
- **Previews and features** — curator interviews, first looks, feature articles
- **Images and standout works** — must-see pieces with links where available
- **Visitor tips** — practical advice from reviews (quiet times, route suggestions, nearby shows)

## Review source tiers

| Tier | Sources | Why |
|------|---------|-----|
| **Tier 1 — National critics** | The Guardian, Financial Times, The Telegraph, The Times, The Observer | UK's leading art critics with established authority |
| **Tier 2 — Arts publications** | Time Out, Evening Standard, The Art Newspaper, Apollo, Frieze, ArtReview, Burlington Magazine, BBC Arts | Specialist arts coverage with editorial rigour |
| **Tier 3 — Specialist** | Expert art blogs, podcast reviews, curatorial commentary | Noted as single-source when used |

**Always excluded:** TripAdvisor, Google reviews, social media posts, AI-generated summaries, press releases.

## Installation

### Claude.ai

Download [`london-art-show.skill`](./london-art-show.skill) from this directory, then go to **Settings → Capabilities → Skills → Add → Upload a skill** and upload it.

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

## Design decisions

- **Professional criticism only.** TripAdvisor and user reviews are excluded — the skill aggregates expert critical opinion, not crowd sentiment.
- **Star ratings front and centre.** UK publications commonly use 5-star systems and these are always surfaced when available.
- **Balanced coverage.** Both positive and negative reviews are presented — the user decides whether to visit.
- **UK-aware.** Assumes a London-based visitor — pricing in GBP, UK membership schemes noted (Art Fund, National Art Pass, Tate Collective).
- **Copyright-respecting.** Direct quotes kept under 15 words with full attribution. The skill paraphrases and links rather than reproducing review content.

## Limitations

- Depends on web search access — works in Claude.ai (with web search enabled), Claude Code, and API with tools
- Quality of output depends on review coverage — major shows at big galleries will have extensive reviews; smaller shows may have limited coverage
- Cannot access paywalled content (e.g., some Times or Telegraph articles) — will note when a review is paywalled
- Focused on London only — not designed for exhibitions in other cities
- Best for current or recent exhibitions — historical show reviews may be harder to find

## Contributing

Suggestions for improving the skill are welcome! Key areas:

- **Additional trusted review sources** for London art criticism
- **Gallery-specific tips** (e.g., best times to visit the Tate, RA membership perks)
- **Output format improvements** based on your experience using the skill
