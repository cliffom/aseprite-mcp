---
name: sf-idea
description: Pressure-test a raw idea with 5–10 framing questions, then write a one-pager to sugar/ideas/<slug>.md.
---

# /sf-idea

You are helping the user turn a raw idea into a one-pager before they commit
to planning it. Your job is to ask enough questions to fill out a crisp
problem statement — not to validate, not to brainstorm solutions, not to
design the architecture. Just framing.

The output is `sugar/ideas/<slug>.md`. Stop there. The user will invoke
`/sf-plan` when they're ready to generate the change artifacts.

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

## The sugar-flow change model

Sugar-flow tracks work as **changes**. Each change lives in its own directory
under `sugar/changes/<name>/` while active, then archives to
`sugar/changes/archive/<YYYY-MM-DD>-<name>/` when done. Long-lived capability
specs live at `sugar/specs/<capability>/spec.md` and are the source of truth
for what the system does today.

### Directory shape

```
sugar/
├── ideas/
│   └── <slug>.md                          # /sf-idea output (pre-plan)
├── specs/                                  # long-lived, source of truth
│   └── <capability>/spec.md                # one capability per directory
└── changes/
    ├── <change-name>/                      # active change
    │   ├── proposal.md                     # why + scope + impact
    │   ├── design.md                       # how: architecture + decisions
    │   ├── tasks.md                        # numbered checkbox list
    │   └── specs/
    │       └── <capability>/spec.md        # DELTA spec (ADDED/MODIFIED/REMOVED)
    └── archive/
        └── <YYYY-MM-DD>-<change-name>/     # merged + moved by /sf-archive
```

### tasks.md format — exact

Tasks are parsed by `/sf-build`. Stick to this format strictly:

```markdown
## 1. <Group name>

- [ ] 1.1 Short task description
- [ ] 1.2 Another task

## 2. <Next group>

- [ ] 2.1 First task in group 2
```

Rules:
- Groups: `## N. <Name>` — numeric prefix, dot, space, name.
- Tasks: `- [ ] N.Y <Description>` — checkbox, two-part number, description.
- No nested tasks (no 1.1.1).
- A task should be completable in one step — a file write, a function added,
  a migration run. If it's "Build the whole API", split it.
- Order matters. Tasks within a group run in order. Groups run in order.
- `/sf-build` updates `- [ ]` to `- [x]` as it completes tasks.

### Delta spec format — exact

Change-local specs at `sugar/changes/<name>/specs/<capability>/spec.md` are
NOT full specs. They're deltas. Use these top-level headings:

```markdown
## ADDED Requirements

### Requirement: <Name>
<1–2 sentence description. Use SHALL/MUST/SHOULD per RFC 2119.>

#### Scenario: <Name>
- **WHEN** <precondition>
- **THEN** <observable outcome>

## MODIFIED Requirements

### Requirement: <Existing name — must match the spec in sugar/specs/>
<Updated description. Explain what changed and why.>

#### Scenario: <Name>
- **WHEN** ...
- **THEN** ...

## REMOVED Requirements

### Requirement: <Name>
<1 sentence on why this is being removed. No scenarios needed.>
```

Rules:
- Every ADDED/MODIFIED requirement must have at least one scenario.
- Scenario names must be unique within a requirement.
- REMOVED entries are requirement name + reason only.
- If a section is empty (e.g., no MODIFIED requirements), omit the heading.
- A change can touch multiple capabilities — write one delta file per
  capability under `sugar/changes/<name>/specs/<capability>/spec.md`.

### Long-lived spec format

At `sugar/specs/<capability>/spec.md`:

```markdown
# <Capability> specification

## Purpose
<1 paragraph. What this capability does for the system.>

## Requirements

### Requirement: <Name>
<Description with SHALL/MUST/SHOULD.>

#### Scenario: <Name>
- **WHEN** ...
- **THEN** ...
```

These files are long-lived. `/sf-archive` merges delta specs into them at
archive time:
- `ADDED Requirements` → append to `## Requirements`.
- `MODIFIED Requirements` → replace the matching requirement block.
- `REMOVED Requirements` → delete the matching requirement block.

If the capability spec doesn't exist yet, `/sf-archive` creates it and
promotes all `ADDED` requirements into the initial `## Requirements` section.

### Capabilities

Capabilities are directories under `sugar/specs/`. Name them after domains,
not features: `auth/`, `billing/`, `ui/`, `search/`. Not `login-flow/` or
`add-credit-card/` — those are changes, not capabilities.

`/sf-plan` lists existing capabilities and asks the user which the current
change touches. New capabilities are created only with explicit user
confirmation to prevent drift (`auth/` vs `authentication/` vs `authn/`).

### Change names

Kebab-case, action-oriented, unique within `sugar/changes/`. Good: `add-jwt`,
`fix-session-timeout`, `refactor-billing-webhook`. Bad: `auth-stuff`,
`change-123`, `jwt` (not a verb).

### The archive transform

When `/sf-archive <name>` runs:
1. Merges every delta file at `sugar/changes/<name>/specs/<capability>/spec.md`
   into `sugar/specs/<capability>/spec.md` per the rules above.
2. Moves the entire `sugar/changes/<name>/` directory to
   `sugar/changes/archive/<YYYY-MM-DD>-<name>/` using today's date.
3. Leaves the archived copy untouched — it's the historical record of what
   this change looked like before the merge.

### CLAUDE.md awareness

Sugar-flow reads `CLAUDE.md` (project root) for tech stack, conventions, and
patterns. If present, use it to inform every artifact you generate — spec
language, task granularity, test style, naming. If absent, don't fabricate
conventions — ask or leave the defaults minimal.

---

## Step 1 — Understand the idea

If the user's opening message doesn't describe the idea, ask them to. Listen
for:

- Who's the user? (Themselves, their team, customers, public?)
- What problem does it solve, concretely?
- What's the status quo — what do they do today without this?
- Is this new capability or replacing something existing?

If any of the above is unclear, ask. Use `AskUserQuestion` when there are
discrete options; plain prose when you just need a free-form answer.

## Step 2 — Pressure-test (5–10 questions total across the whole flow)

Once you have the basics, ask targeted questions to fill gaps. Pick from
these dimensions, but ONLY ask what's actually unknown — don't march through
the list mechanically:

1. **User / audience.** Who specifically? How many? How often would they hit this?
2. **Success criteria.** How will we know this worked? What's the measurable signal?
3. **Non-goals.** What's explicitly NOT in scope? What would be nice but we're skipping?
4. **Narrowest wedge.** What's the smallest version of this that still delivers value?
5. **Rough shape.** Web app, CLI, library, agent, background job, script? Just the shape.
6. **Dependencies.** Anything this blocks on — external service, another project, a decision?
7. **Kill criteria.** Under what conditions would we abandon this? What would make it a dud?

Prefer `AskUserQuestion` with concrete options when you can. For freeform
answers ("describe the user"), just ask in prose.

Stop asking when you have enough to write the one-pager. 5–8 questions is
usually the sweet spot. Fewer if the user gave a rich opening.

## Step 3 — Generate a slug

Pick a short kebab-case slug — 2–4 words max. Examples: `csv-import-v2`,
`team-mentions`, `slack-digest`.

Confirm the slug with the user via `AskUserQuestion` if you're unsure, but
usually just announce it and proceed.

## Step 4 — Write the one-pager

Create `sugar/ideas/` if it doesn't exist. Write `sugar/ideas/<slug>.md`:

```markdown
# <Idea name>

**Status:** draft
**Created:** <YYYY-MM-DD>

## Problem

<2–4 sentences. Who has the problem, what the problem is, what they do today.>

## Proposed solution

<1–3 sentences. The shape of the thing, not the implementation.>

## Success criteria

- <Measurable signal 1>
- <Measurable signal 2>
- <Measurable signal 3>

## Non-goals

- <Thing we are explicitly NOT doing>
- <Another thing we are explicitly NOT doing>

## Narrowest wedge

<1–2 sentences. The smallest version that still delivers value. This is what
/sf-plan will plan against — write it with intent.>

## Open questions

- <Thing we don't yet know>
- <Thing that might kill this>

## Kill criteria

<Under what conditions would we abandon this? 1–2 sentences.>
```

If a file at that slug already exists, ask the user whether to overwrite or
pick a new slug.

## Step 5 — Stop

Tell the user in one sentence where the one-pager is and what the next step
is ("run `/sf-plan sugar/ideas/<slug>.md` when you're ready to lock the
architecture"). Do NOT auto-invoke `/sf-plan`. Do NOT start drafting
architecture. Do NOT create `sugar/changes/`. Stop.

---

## What NOT to do in this skill

- Do NOT design the solution in detail. That's `/sf-plan`'s job.
- Do NOT write code, even stubs.
- Do NOT create a change directory under `sugar/changes/`.
- Do NOT generate specs, tasks, or proposals — those belong to `/sf-plan`.
- Do NOT run more than ~10 questions. If you're asking the 11th, you're in
  the wrong skill — the idea isn't mature enough yet, say so and stop.
- Do NOT flatter the idea. "Interesting concept!" is noise. Just do the work.
