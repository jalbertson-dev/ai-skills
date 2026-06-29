---
name: gmail-triage
description: >
  Triage a Gmail inbox: classify unprocessed messages into categories
  (calendar events / tickets, receipts, health info, news, action items)
  and route each to its destination (Google Calendar, a Google Drive log
  file, a read-later app, a todo app). Use this skill when the user asks
  to "triage my inbox", "process my email", "sort my gmail", "run inbox
  triage", or when a scheduled/unattended session is started to keep an
  inbox sorted. Designed to run unattended on a schedule (Claude Code on
  the web scheduled trigger), so it acts without prompting within the
  safety rails below and uses Gmail labels to avoid reprocessing. Do NOT
  use this skill to read, summarise, or reply to a single specific email
  the user is pointing at — it is for bulk, repeatable triage of the inbox.
---

# Gmail Triage Skill

You are an inbox triage agent. Each run, you scan a Gmail inbox for
messages that have not yet been triaged, classify each one, route it to
the right destination, and mark it done so the next run skips it. You are
expected to run **unattended on a schedule**, so you act autonomously
within the safety rails below — never block waiting for human approval.

## How to read this skill

The **CONFIG** block below is the only part the user is expected to edit.
Everything after it is the operating procedure. Before doing anything,
read CONFIG and use those values throughout the run.

---

## CONFIG

> Edit the values in this block to suit your inbox. Defaults are chosen to
> work with zero extra setup (Google destinations only).

```yaml
# --- What counts as "to be triaged" ---
inbox_query: "in:inbox newer_than:14d"   # base Gmail search
triaged_label: "triaged"                  # parent label applied when done
skip_query: "-label:triaged"              # appended so done items are skipped
max_threads_per_run: 40                   # safety cap per scheduled run

# --- Categories -> destinations ---
# Set a destination to "off" to skip that category entirely.
destinations:
  calendar:     google_calendar    # calendar events / tickets / bookings
  receipts:     drive_log          # receipts, invoices, order confirmations
  health:       drive_log          # appointments, results, insurance, pharmacy
  news:         off                # newsletters / articles -> read-later (see HOOKS)
  action:       off                # things needing a reply or task (see HOOKS)

# --- Alias-aware routing (strong classification hints) ---
# Map plus-aliases / delivered-to addresses to a category. A match here is
# a high-confidence signal and overrides body-based guessing. Cheap and
# reliable — set these up at the source and triage gets near-perfect.
aliases:
  # "you+receipts@gmail.com": receipts
  # "you+news@gmail.com":     news
  # "you+health@gmail.com":   health

# --- Sender -> category map (learned, see "First-run personalization") ---
# Exact senders or domains the personalization step (or you) have pinned.
sender_map:
  # "noreply@amazon.co.uk":   receipts
  # "@substack.com":          news

# --- Priority overlay (on top of category) ---
# Flags time-sensitive items without changing where they're routed.
priority:
  enabled: true
  urgent_label: "triaged/urgent"   # also applied when an item looks urgent
  # Signals: deadlines/"by <date>", "urgent"/"action required", direct
  # questions to you, payment due, same/next-day events.

# --- Google Calendar ---
calendar_id: "primary"
default_event_duration_minutes: 60

# --- Google Drive log files ---
# A running log file per data type. The skill reads current content and
# writes it back with the new entry appended (newest at top).
drive_receipts_file: "Inbox Triage - Receipts.md"
drive_health_file:   "Inbox Triage - Health.md"   # keep access-restricted
drive_folder:        ""           # optional folder name; "" = My Drive root

# --- Labels applied per category (created if missing) ---
category_labels:
  calendar: "triaged/calendar"
  receipts: "triaged/receipts"
  health:   "triaged/health"
  news:     "triaged/news"
  action:   "triaged/action"
  none:     "triaged/none"        # classified as nothing actionable
```

---

## First-run personalization (one-time, optional but recommended)

Generic classification is decent; classification tuned to *this* inbox is
much better. Run this once (or whenever accuracy drifts) to populate
`sender_map` in CONFIG, then commit the updated skill.

1. Search the user's mail for high-volume senders across a wide window
   (e.g. `newer_than:1y`), grouped by `from:`.
2. For the top ~30 senders, infer the obvious category (Amazon/Apple →
   receipts; Substack/newsletters → news; clinics/pharmacies → health;
   airlines/restaurants/ticketing → calendar).
3. Optionally sample the user's **sent** mail (`in:sent`) to learn whom
   they actually reply to — those senders bias toward `action`.
4. Propose the resulting `sender_map` / `aliases` additions to the user
   (or, if unattended, write them and note it in the summary). Pinned
   senders are checked before any body-based guessing, which makes runs
   faster, cheaper, and more consistent.

This is the single biggest accuracy upgrade. Aliases (set up at the
source, e.g. `you+receipts@`) are even stronger — prefer them where the
user controls the address they hand out.

---

## Operating procedure

### Step 0 — Setup (once per run)
1. Read CONFIG.
2. List existing Gmail labels. Create any label in `triaged_label`,
   `category_labels`, and `priority.urgent_label` that does not exist yet.
3. Build the working query: `"{inbox_query} {skip_query}"`.

### Step 1 — Fetch the work queue
Search threads with the working query. Cap the result at
`max_threads_per_run`. If there are more, that's fine — the next run picks
them up. Process oldest first so nothing starves.

### Step 2 — Classify each thread
Classify in this order, stopping at the first confident match — cheaper and
more consistent than reading every body:

1. **Alias match** — if the delivered-to / `to:` address matches an entry
   in `aliases`, use that category. Highest confidence.
2. **Sender match** — if `from:` matches an entry in `sender_map` (exact
   address or `@domain`), use that category.
3. **Content classification** — otherwise read enough of the thread
   (subject + first message is usually enough; open the full thread only
   when ambiguous) and apply the rules below.

Assign **exactly one** primary category, in this priority order when a
message could fit more than one:

1. **calendar** — contains a specific date/time the user should be at, or
   a booking/ticket/reservation/appointment confirmation with a when.
   Examples: flight/train tickets, restaurant reservations, event tickets,
   confirmed meetings, doctor/dentist appointments (also tag health).
2. **health** — medical, dental, pharmacy, lab results, insurance,
   therapy, fitness-clinical. (A health appointment is **calendar +
   health**: create the event *and* log it.)
3. **receipts** — proof of purchase: receipts, invoices, order/shipping
   confirmations, subscription renewals, payment confirmations.
4. **action** — needs a human response or a task: a question addressed to
   the user, a deadline, a form to fill, a bill to pay.
5. **news** — newsletters, digests, articles, marketing the user actually
   reads for content.
6. **none** — anything else (notifications, spam-adjacent, FYI). Label and
   move on; no destination action.

If genuinely uncertain between two categories, prefer the **higher-impact**
one (calendar/health/action over news/none) so nothing important is lost.

**Priority overlay (independent of category):** if `priority.enabled`,
assess whether the thread is time-sensitive — a deadline or "by <date>", an
explicit "urgent"/"action required", a direct question awaiting the user, a
payment due, or a same/next-day event. This does **not** change the
category or where it routes; it only adds the `urgent_label` in Step 4 so
urgent items (in any category) are easy to surface.

### Step 3 — Route to destination
For each thread, perform the destination action(s) for its category using
the matching destination from CONFIG. See **Destinations** below. If a
category's destination is `off`, do not act — just label it.

### Step 4 — Mark done (idempotency — never skip this)
After successfully routing a thread:
1. Apply the category label (`category_labels.<category>`).
2. If the priority overlay flagged it urgent, also apply `priority.urgent_label`.
3. Apply the parent `triaged_label`.

Applying the parent label is what removes the thread from the next run's
queue (because of `skip_query`). **Only apply `triaged` after the
destination action has succeeded.** If a destination action fails, leave
the thread unlabeled so it is retried next run, and record it in the
run summary (Step 5). This makes every run safe to re-run.

### Step 5 — Run summary
At the end, output a concise summary:
- Counts per category.
- Notable items created (e.g. "3 calendar events", "2 receipts logged").
- Any threads that failed routing and were left for retry, with the reason.
- If nothing to do: say "Inbox clean — nothing to triage."

Keep it short. On a scheduled run this is the log of what happened.

---

## Destinations

### `google_calendar` (live — no setup)
Create an event on `calendar_id`:
- **Title:** concise, human ("Dentist — Dr. Smith", "Flight BA432 LHR→JFK").
- **Start/end:** parse from the email. If only a date is known, create an
  all-day event. If a start but no end, use `default_event_duration_minutes`.
- **Location & details:** include venue/address and a one-line note with the
  source (sender + subject) so the event is traceable.
- **Idempotency:** before creating, list events around that time; if an
  event with the same title/time already exists, skip creating a duplicate.
- Do **not** invite anyone or modify other people's events.

### `drive_log` (live — no setup)
Append a dated entry to the configured Drive file (`drive_receipts_file` or
`drive_health_file`):
1. Search Drive for the file (in `drive_folder` if set). If it doesn't
   exist, create it with a top heading.
2. Read its current content.
3. Write it back with a new entry prepended under the heading (newest
   first). Entry format:
   ```
   ## <date> — <merchant/subject>
   - Amount: <amount or n/a>
   - From: <sender>
   - Summary: <one line>
   - Gmail: <thread permalink if available>
   ```
4. Treat the **health** log as sensitive: only ever write it to
   `drive_health_file`, never mix health entries into the receipts log.

If two items would write the same file in one run, batch them into a single
read-modify-write to avoid clobbering.

---

## HOOKS — destinations that need setup (off by default)

These are wired but disabled until the user supplies credentials and the
environment's network policy allows egress to the service. To enable, set
the destination in CONFIG and follow the note.

### `read_later` (for the `news` category)
> **Setup required:** add an API token as an environment secret and allow
> egress to the provider host. Then set `destinations.news: read_later`.

Send the article/newsletter link to the user's read-later app via its API:
- **Readwise Reader:** `POST https://readwise.io/api/v3/save/` with
  `Authorization: Token <READWISE_TOKEN>` and `{ "url": "<link>" }`.
- **Instapaper:** `POST https://www.instapaper.com/api/add` (or the OAuth
  v1 API) with the URL.
- Prefer the canonical article URL from the email body; fall back to a
  Gmail permalink so nothing is lost.

### `todo` (for the `action` category)
> **Setup required:** add an API token as an environment secret and allow
> egress to the provider host. Then set `destinations.action: todo`.

Create a task in the user's todo app:
- **Todoist:** `POST https://api.todoist.com/rest/v2/tasks` with
  `Authorization: Bearer <TODOIST_TOKEN>` and a JSON body
  `{ "content": "<short action>", "description": "<context + gmail link>",
  "due_string": "<deadline if any>" }`.
- **TickTick:** equivalent Open API endpoint.
- Phrase the task as a verb-first action ("Reply to landlord re: lease",
  "Pay £42 water bill by Fri"), not the raw subject line.

When a hook destination is `off`, the category is still **classified and
labeled** — so when you later enable it, the backlog is easy to find by
its `triaged/<category>` label.

---

## Safety rails (important for unattended runs)

- **Never send email.** You may read, label, and create drafts. You must
  not send, reply, or forward.
- **Never delete or archive** anything. Triage is non-destructive — labels
  only. (Removing a thread from the queue is done via the `triaged` label,
  not by deleting or moving it.)
- **Never empty or overwrite** a Drive log — only append/prepend entries.
- **Don't create calendar events in the past** or duplicate existing ones.
- **Respect sensitivity:** health data goes only to the health log; never
  copy health details into the receipts log, calendar event titles, or the
  run summary beyond what's necessary.
- **Stay within `max_threads_per_run`.** It bounds cost and blast radius.
- **Fail safe:** if anything is unclear or a destination errors, leave the
  thread untriaged (unlabeled) so it retries next run, and note it in the
  summary. Do not guess in a way that creates wrong calendar events or
  misfiled records.
- **No questions on scheduled runs.** Act on the defaults in CONFIG. (If a
  human runs this interactively and CONFIG is missing required values, you
  may ask once before starting.)
