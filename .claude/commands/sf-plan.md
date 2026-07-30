---
description: Run an architecture review on a one-pager, then generate the full change directory (proposal, design, delta specs, tasks) under sugar/changes/<name>/.
---

# /sf-plan

You are the engineering manager locking down a change before implementation
starts. Two jobs:

1. Walk the user through an interactive architecture review.
2. Once architecture is locked, generate the full change artifacts:
   `proposal.md`, `design.md`, `tasks.md`, and one or more delta specs
   under `sugar/changes/<name>/specs/<capability>/spec.md`.

After this skill runs, the user can invoke `/sf-build` to start
implementation from `tasks.md`.

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

## Root-cause discipline

No fixes without root cause. No "pre-existing" attribution without receipts.

**When something breaks (a test, a build, a runtime error):**

1. Reproduce it. Confirm the failure is real before theorizing.
2. Read the actual error. Not the summary, the full trace.
3. Form one specific hypothesis ("X happens because Y is null when Z runs before W").
4. Verify the hypothesis — `grep`, `git blame`, `git log -S`, run a probe. Don't guess.
5. Only then propose a fix. The fix should address the cause, not the symptom.

**When you're tempted to write `try { ... } catch {}`:** stop. A swallowed
exception is a future debugging nightmare. Either handle the specific error
class you expect, or let it throw.

**When you're tempted to say "this was pre-existing" or "not related to my change":**
prove it. Run the same check against the base branch. If it passes there and
fails here, it IS your change. If you can't run the check, say "unverified"
instead of claiming it's unrelated.

**When you get stuck for more than ~10 minutes on the same bug:** state what
you've ruled out, what's still possible, and ask the user which branch to
pursue. Spinning in place wastes everyone's time.

---

## Step 0 — Locate the one-pager

The user invokes this skill one of three ways:

1. **With an argument:** `/sf-plan sugar/ideas/<slug>.md` — read that file.
2. **No argument:** list files under `sugar/ideas/`. If there's only one,
   use it. Otherwise `AskUserQuestion` to pick.
3. **No one-pager exists:** if the user gave you enough inline context to
   plan against (a paragraph describing the work), proceed without one and
   note the gap in the proposal. Otherwise, tell them to run `/sf-idea`
   first and stop.

Read the one-pager fully. Also read `CLAUDE.md` at the repo root if it
exists — you'll use its conventions when writing artifacts.

## Step 1 — Pick a change name

Propose a kebab-case name. Usually derived from the one-pager slug with a
verb prefix if missing: `add-jwt`, `fix-session-timeout`, `refactor-billing`.

Confirm via `AskUserQuestion` if ambiguous. Check that
`sugar/changes/<name>/` doesn't already exist; if it does, prompt for a
different name or confirm overwrite.

## Step 2 — Pick affected capabilities

List existing capabilities:

```bash
ls sugar/specs/ 2>/dev/null
```

Use `AskUserQuestion` (multiSelect) to ask which capabilities this change
touches:
- Each existing capability is a checkbox option.
- Include an "Other (new capability)" option.

If the user picks "Other" or if `sugar/specs/` is empty, ask for the
capability name(s) — kebab-case, domain-level (e.g., `auth`, `billing`,
`ui`), not feature-level. Confirm before creating new directories; this is
the drift-prevention gate.

## Step 3 — Interactive architecture review

Walk the user through these dimensions one at a time. Skip any that don't
apply. Don't march through mechanically.

### 3a. Data flow

State the data flow in words. Where does data enter, where does it leave,
what transformations happen, which boundaries cross trust (user input,
external APIs, DB)?

Ask the user to confirm or correct. If you can't form a coherent data flow
from the one-pager, ask specific questions to fill gaps.

### 3b. Interface contract

For each public surface (HTTP endpoint, CLI flag, library export, DB table):
- Input shape.
- Output shape.
- Error cases and how they're surfaced.
- Idempotency / retry safety.

Use `AskUserQuestion` when there's a genuine fork. Otherwise propose a
contract and have the user react.

### 3c. Edge cases

List edge cases the one-pager doesn't address. At minimum:
- Empty input. Zero records.
- Huge input. What's the upper bound?
- Concurrent invocations. Race conditions?
- Partial failure. Mid-operation crash — recovery path?
- Auth / permissions. Who's allowed? How enforced?

For each, note "handled by X", "explicitly deferred", or "open question".

### 3d. Test plan

- Unit tests — which pure functions, what cases?
- Integration tests — which real dependencies exercised?
- End-to-end / smoke — is there a golden-path test?
- What can't be tested automatically?

If the answer is "manual verification for now," name it explicitly.

### 3e. Performance + resource shape

Only if relevant (large inputs, user-facing latency, background jobs):
- Expected input size / rate?
- Bottleneck likely to be?
- N+1 or O(n²) traps?

Skip silently for small internal tools.

## Step 4 — Generate the change directory

Create `sugar/changes/<name>/` and write these files.

### 4a. proposal.md

```markdown
# <Change name>

**Source:** sugar/ideas/<slug>.md  <!-- omit if none -->
**Created:** <YYYY-MM-DD>
**Capabilities:** <cap1>, <cap2>

## Why

<2–4 sentences. Problem, who has it, what they do today. Pull from the
one-pager but rewrite in your own words — don't copy-paste.>

## What

<2–4 sentences. The narrowest wedge — what this change ships.>

## Impact

- **Adds:** <new capability or behavior, if any>
- **Changes:** <existing behavior that shifts>
- **Removes:** <behavior going away, if any>
- **Out of scope:** <adjacent things NOT in this change>

## Open questions

- <thing still undecided, with a note on who/what resolves it>
```

### 4b. design.md (always generate)

```markdown
# <Change name> — design

## Architecture

### Data flow
<prose + a short mermaid diagram if it clarifies>

### Interface contract
<per-surface: input / output / errors / idempotency>

## Decisions

### <Decision 1>
- **Chose:** <approach>
- **Rejected:** <alternatives considered>
- **Why:** <1–2 sentence rationale>

### <Decision 2>
...

## Edge cases
- <case>: <handling>

## Test plan
- <test type>: <what it covers>
- <manual verification>: <what to check by hand>

## Performance
<only if relevant; skip the section entirely otherwise>
```

For trivial changes, the Decisions section may be one entry or empty — but
still generate the file. It's the record of what you thought about.

### 4c. Delta specs

For each affected capability, write
`sugar/changes/<name>/specs/<capability>/spec.md` in the delta format
documented in the sugar-model preamble above (`## ADDED Requirements`,
`## MODIFIED Requirements`, `## REMOVED Requirements`).

Before writing MODIFIED or REMOVED requirements, read the current spec at
`sugar/specs/<capability>/spec.md` to make sure the requirement names you
reference actually exist. If the capability spec doesn't exist yet, only
ADDED requirements are valid.

Every requirement needs at least one scenario (WHEN/THEN). No placeholders.

### 4d. tasks.md

Write numbered, ordered tasks in the exact format from the sugar-model
preamble. Rules:

- Group tasks logically (`## 1. Setup`, `## 2. Core logic`, `## 3. Tests`,
  `## 4. Docs`).
- Each task must be small enough to complete in one focused step.
- Order matters — tasks within a group run top-to-bottom, groups in order.
- End every change with at least a Tests group and (if user-facing) a Docs
  group.
- Default to 8–20 tasks total. If you have fewer than 5, the change is
  probably too small to warrant this ceremony; warn the user. If you have
  more than 30, split the change.

## Step 5 — Report and stop

Report in the conversation:

- Change name + directory (`sugar/changes/<name>/`).
- Affected capabilities.
- Task count and rough group breakdown.
- One sentence on next step: "run `/sf-build` to start implementation".

Stop. Do NOT start implementing. Do NOT invoke `/sf-build` yourself.

---

## What NOT to do in this skill

- Do NOT write code, even stubs.
- Do NOT check off any tasks — they start unchecked, `/sf-build` owns that.
- Do NOT create new capabilities without explicit user confirmation.
- Do NOT copy-paste from the one-pager into proposal.md — rewrite with
  intent. A proposal that reads like a paraphrase of the one-pager adds no
  value.
- Do NOT skip edge cases because they're "obvious". Obvious edge cases are
  the ones that ship broken.
- Do NOT fabricate requirements in the delta specs. Every requirement must
  trace to the one-pager or a decision made during architecture review.
