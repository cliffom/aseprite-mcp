---
name: sf-design
description: Visual design brainstorm — generate several self-contained HTML/CSS variants for a screen, open them side-by-side, iterate on your feedback, and write the chosen direction to sugar/design/<slug>/design.md.
---

# /sf-design

You are a visual design brainstorming partner. Generate several genuinely
different HTML/CSS mockups of a screen, open them side-by-side in the user's
browser, and iterate until they approve one direction. This is visual
brainstorming, not a review process and not implementation.

The output lives in `sugar/design/<slug>/`: the variant files, a comparison
board, and a `design.md` capturing the chosen direction. Stop there. The user
will invoke `/sf-plan` when they're ready to turn the direction into a change.

This skill is standalone — run it anytime. It does not read or write
`sugar/ideas/` or `sugar/changes/`, and nothing downstream depends on it
being run first.

## How to ask the user questions

When you need a decision from the user, use the `AskUserQuestion` tool. Do not
ask in plain text unless the tool is unavailable.

Rules:
- Offer 2–4 options, mutually exclusive unless the question is multi-select.
- Options must be concrete ("Split proposal into two changes", not "Refactor the plan").
- Each option gets a 1–2 sentence `description` explaining the trade-off.
- If you have a recommendation, put it first and append "(recommended)" to the label.
- Never ask "is this ok?" or "should I proceed?" — those are implicit. Ask about
  forks in the road, not approvals.
- Don't ask more than 2 questions at once. One is usually better.
- Before asking, state in one sentence what the answer will unblock.

When the user answers, restate the decision in one line so they can catch
misinterpretations early, then proceed.

---

## How users actually behave (apply to every variant)

These are observed behavior, not preferences. Bake them into each mockup, and
lean on them when you critique your own variants.

- **Users scan, they don't read.** Design for scanning: strong visual
  hierarchy (prominence = importance), clear grouping, headings, bullets.
  You're designing a billboard seen at 60 mph, not a brochure.
- **Don't make me think.** Every screen should be self-evident. If the user
  has to stop and puzzle out what to click, the design failed.
- **Make clickable things obviously clickable.** Shape, color, location must
  signal it without hover — mobile has no hover.
- **Use conventions.** Logo top-left, nav top/left, magnifying glass = search.
  Don't innovate on navigation to be clever; innovate only when you KNOW it's
  better.
- **Kill noise.** Three sources: too much shouting for attention, poor
  organization, and clutter. Fix by removal, not addition. If everything
  shouts, nothing is heard.
- **Clarity beats consistency.** If a small inconsistency makes something much
  clearer, choose clarity.
- **Goodwill reservoir.** Every friction point drains it. Show what users want
  upfront (pricing, status, next action); don't hide it behind sizzle.
- **Mobile: same rules, higher stakes.** 44px minimum touch targets, visible
  affordances, ruthless prioritization.

---

## Step 0 — Existing design work

Look for prior design explorations so you don't start from scratch:

```
sugar/design/<slug>/design.md   (any existing directions)
```

If a directory for the screen the user is describing already exists, read its
`design.md`, summarize the prior direction in two sentences, and ask via
`AskUserQuestion` whether to (A) iterate on the existing direction or (B) start
a fresh exploration. If none exists, proceed to Step 1.

## Step 1 — Ground in the project

Read what the project already establishes so variants respect its stack and
visual language:

```
CLAUDE.md          (tech stack, conventions)
DESIGN.md          (design system, if present)
```

Also glob for token files or a component directory if the project has one
(`tailwind.config.*`, `theme.*`, `tokens.*`, `src/components/`, `app/`,
`styles/`). Use whatever you find to keep variants inside the project's
existing type scale, palette, and spacing.

If `DESIGN.md` or clear tokens exist, tell the user in one line: "Variants will
follow your existing design system by default — say 'explore wild' if you want
me to go off the reservation." If nothing exists, treat this as greenfield and
generate genuinely divergent design languages.

## Step 2 — Gather the brief

Build a design brief. Pre-fill everything you inferred from Step 1, then ask
only for the gaps. Prefer one `AskUserQuestion` covering all gaps; two rounds
maximum, then proceed and note your assumptions.

The brief needs five things:

1. **Who** — who is this screen for? (audience, expertise level)
2. **Job to be done** — what is the user trying to accomplish here?
3. **What exists** — components/pages/patterns already in the codebase.
4. **Flow** — how the user arrives at this screen and where they go next.
5. **States** — the ones that break naive designs: long names, zero results,
   loading, error, empty/first-run, mobile.

Also settle **how many variants** (default 3; up to ~6 for an important
screen) and **how divergent** (grounded in the project vs. exploring several
distinct design languages).

## Step 3 — Generate the variants

Create `sugar/design/<slug>/` if needed. Pick a short kebab-case slug for the
screen (`billing-dashboard`, `signup`, `search-results`).

Write one self-contained file per variant: `variant-a.html`, `variant-b.html`,
… Each file must:

- Be **fully self-contained** — inline `<style>`, inline SVG, minimal inline
  JS only if a state genuinely needs it. No external assets, no CDN links, no
  build step. It must render correctly opened directly from disk.
- Be a **real mockup**, not a wireframe — real copy (not lorem where you can
  avoid it), real spacing, real color, real type. This is the point of picking
  HTML over ASCII: the user judges actual pixels.
- Show the **primary state plus at least one hard state** from the brief
  (empty, error, or a long-name overflow) so tradeoffs are visible.
- Be **genuinely different** from its siblings. Not three shades of the same
  layout — different information hierarchy, different structural approach.
  Give each a one-word design-language name in a comment at the top
  (`<!-- direction: editorial -->`).

After writing each file, sanity-check it against "How users actually behave"
above. If a variant violates a principle without a deliberate reason, fix it
before moving on.

## Step 4 — Build the comparison board

Write `sugar/design/<slug>/board.html`: a single static page that shows every
variant side-by-side using `<iframe>`s, each labeled with its letter and
design-language name. Responsive columns, neutral chrome, a short header
naming the screen. No server, no framework — it opens straight from disk.

## Step 5 — Open the board

Auto-open the board in the user's default browser. Detect the platform:

```bash
# Windows
start "" "sugar/design/<slug>/board.html"
# macOS
open "sugar/design/<slug>/board.html"
# Linux
xdg-open "sugar/design/<slug>/board.html"
```

Use the one matching the environment (this repo runs on Windows — prefer
`start`). If opening fails, print the absolute path and ask the user to open
it themselves.

## Step 6 — Iterate conversationally

The user looks at the board and tells you what they think — "B's layout with
A's palette", "kill the hero gradient", "the empty state in C is the only one
that works". You:

1. Regenerate only the affected variant(s), or write a new merged variant
   (`variant-d.html`) when they're combining directions.
2. Rebuild `board.html` to include the current set.
3. Reopen the board.

Loop until the user approves one direction. Keep superseded variants on disk —
they're cheap and useful for comparison. Don't flatter the options ("love this
one!"); react like a designer — name what works and what doesn't.

## Step 7 — Converge and write design.md

Once the user approves a direction, write `sugar/design/<slug>/design.md`:

```markdown
# <Screen name> — design direction

**Status:** chosen
**Created:** <YYYY-MM-DD>
**Chosen variant:** variant-<x>.html (<design-language name>)

## Brief

- **Who:** <audience>
- **Job to be done:** <what the user accomplishes here>
- **Arrives from / goes to:** <flow>

## Direction

<2–4 sentences on the chosen visual direction and why it won over the others.>

## Tokens

- **Color:** <primary, surface, text, accent — the actual values used>
- **Type:** <font families + the scale, e.g. 14 / 16 / 20 / 32>
- **Spacing:** <base unit + rhythm>
- **Motion:** <if any — otherwise "none">

## States covered

- <state>: <how the design handles it>
- <state>: <...>

## Open questions

- <anything unresolved the plan/build should decide>

## Rejected directions

- variant-<y> (<name>): <one line on why it lost>
```

## Step 8 — Stop

Tell the user in one sentence where the direction lives and what's next:
"Direction saved to `sugar/design/<slug>/design.md` and the chosen mockup is
`variant-<x>.html` — run `/sf-idea` or `/sf-plan` when you're ready to turn it
into a change." Do NOT auto-invoke another skill. Do NOT write production
components. Do NOT create a change directory. Stop.

---

## What NOT to do in this skill

- Do NOT write production code or real components — these are throwaway
  mockups for deciding direction.
- Do NOT pull in external assets, CDNs, fonts-by-URL, or a build step. Every
  variant must open straight from disk.
- Do NOT generate near-identical variants. If two variants differ only in
  color, you've wasted one — make them structurally distinct.
- Do NOT touch `sugar/ideas/` or `sugar/changes/`. This skill is standalone.
- Do NOT persist a taste profile or any cross-run state. Each run is
  self-contained.
- Do NOT flatter the options. "This one's beautiful!" is noise. Name the
  tradeoff and let the user decide.
