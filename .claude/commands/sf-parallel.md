---
description: Run several independent changes concurrently, each in its own git worktree, by dispatching one background build agent per change. Checks for capability overlap first; records a run ledger for /sf-converge to merge afterward. Does not merge.
---

# /sf-parallel

You are orchestrating several changes at once. Each change already has a full
`sugar/changes/<name>/` directory (proposal, design, delta specs, tasks.md)
from `/sf-plan`. Your job is to run their builds **concurrently** — one
isolated git worktree per change — instead of one after another.

You do three things and stop:

1. **Gate** — confirm the selected changes are safe to run in parallel
   (no two fighting over the same capability/files).
2. **Dispatch** — spawn one background build agent per change, each in its own
   worktree, each running the `/sf-build` flow to completion on its tasks.md.
3. **Ledger** — record which change maps to which branch/worktree so
   `/sf-converge` can merge them in order afterward.

You do NOT merge, resolve conflicts, or review. That's `/sf-converge` then
`/sf-review`. Each agent owns its whole `tasks.md`, so there are no
cross-agent checkbox races — the isolation is the point.

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

## Step 0 — Select the changes

The user invokes this skill one of two ways:

1. **With names:** `/sf-parallel add-jwt fix-timeout refactor-billing` → use
   exactly those changes.
2. **No argument:** list active changes (`sugar/changes/`, excluding
   `archive/`). Use `AskUserQuestion` (multiSelect) to pick which to run
   concurrently.

Validate each name:
- The directory `sugar/changes/<name>/` exists and has a `tasks.md`.
- The change has at least one unchecked task. If every task is already `[x]`,
  drop it from the run and say so — there's nothing to build.

If fewer than two valid changes remain, stop. Tell the user parallel mode
needs at least two — for a single change, run `/sf-build` directly.

Also read `CLAUDE.md` at the repo root if present; the agents will need its
conventions, and you'll pass them along.

## Step 1 — The overlap gate

Parallel changes are safe when they don't touch the same code. Your proxy for
"same code" is **shared capability**. For each selected change, read its delta
specs under `sugar/changes/<name>/specs/<capability>/spec.md` and collect the
set of capabilities it touches.

Build a capability → changes map. Any capability claimed by two or more
changes is a **collision risk** — those changes will likely edit overlapping
files and produce merge conflicts at converge time.

Report the map in one block:

```
Lanes:
  add-jwt          → auth
  fix-timeout      → auth, session     ⚠ shares `auth` with add-jwt
  refactor-billing → billing
```

If there are no collisions, say so and proceed to dispatch without asking.

If there ARE collisions, this is the drift-prevention gate. Use
`AskUserQuestion`:
- **Serialize the colliding changes** — run the non-colliding ones in
  parallel, and chain the colliding pair so one builds on the other's branch.
  (Recommended when the overlap is real.)
- **Run all in parallel anyway** — accept that `/sf-converge` may hit
  conflicts the user resolves by hand.
- **Drop a change from this run** — defer one to a separate pass.

Restate the chosen plan in one line before dispatching.

Skim `design.md` for each colliding pair only when you need to judge how bad
the overlap is — don't deep-read every change.

## Step 2 — Dispatch the build agents

Detect the base branch once (the branch the worktrees fork from and converge
back into):

```bash
git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@'
```

Fall back to `main`, then `master`.

For each change to run in parallel, spawn **one** agent with:
- `isolation: "worktree"` — gives the agent an isolated git worktree so its
  edits never collide with sibling agents or the user's working tree.
- `run_in_background: true` — true fan-out; you'll be notified as each
  finishes instead of blocking.

The agent's prompt instructs it to run the `/sf-build` flow on exactly one
change. Give it, verbatim, the essentials it can't infer cold:
- The change name and that its directory is `sugar/changes/<name>/`.
- "Read proposal.md, design.md, all delta specs, then tasks.md. Read
  `CLAUDE.md` at the repo root for conventions."
- "Work `tasks.md` top-to-bottom: implement each unchecked task, mark its
  checkbox `[x]`, do not batch. Resumable — skip tasks already `[x]`."
- "Stay strictly in this change's scope. Do not touch other changes' files.
  Do not commit unless you must to keep the worktree clean — if you do,
  commit on this worktree's branch only."
- "If you get stuck after three attempts on one task, or a task can't be done
  as written, stop and report — do not thrash and do not silently improvise."
- "When done, report: change name, X/Y tasks complete, the branch name of
  this worktree, and any tasks left blocked."

If Step 1 produced a **serialized** pair, do NOT dispatch the dependent change
now. Note it in the ledger as `blocked-on: <other>` so `/sf-converge` (or a
follow-up `/sf-parallel`) runs it after the first lands.

## Step 3 — Write the run ledger

Record the run so `/sf-converge` knows what to merge without re-deriving it.
Write `sugar/changes/.parallel-run.md`:

```markdown
# Parallel run — <YYYY-MM-DD HH:MM>

**Base branch:** <base>
**Status:** dispatched

| Change            | Capabilities   | Worktree branch        | State      | Notes              |
|-------------------|----------------|------------------------|------------|--------------------|
| add-jwt           | auth           | <branch-or-pending>    | dispatched |                    |
| refactor-billing  | billing        | <branch-or-pending>    | dispatched |                    |
| fix-timeout       | auth, session  | <branch-or-pending>    | queued     | blocked-on add-jwt |

**Merge order (suggested):** refactor-billing, add-jwt, fix-timeout
```

Rules:
- Suggested merge order: independent changes first; serialized/blocked
  changes after the change they depend on.
- The worktree branch name may not be known until the agent reports it — leave
  it `pending` and let `/sf-converge` reconcile from the agent results, or fill
  it in when the dispatch returns the branch.
- This ledger is scratch state for the current run. It is NOT part of any
  change's permanent record and is not archived.

## Step 4 — Report and stop

Print one block:

```
Dispatched N changes in parallel (base: <base>):
  • add-jwt          → building in worktree   (auth)
  • refactor-billing → building in worktree   (billing)
  • fix-timeout      → queued, blocked-on add-jwt  (auth, session)

Ledger: sugar/changes/.parallel-run.md
You'll be notified as each agent finishes. When they're done, run
/sf-converge to merge them in order.
```

Stop. Do NOT wait in a polling loop. Do NOT merge. Do NOT invoke
`/sf-converge` or `/sf-review` yourself — the user runs converge once the
background agents report in.

---

## What NOT to do in this skill

- Do NOT run two changes that share a capability in parallel without flagging
  it first. The overlap gate exists to prevent silent merge conflicts.
- Do NOT spawn more than one agent per change. One change, one worktree, one
  tasks.md owner — that's what keeps checkbox state race-free.
- Do NOT merge worktree branches here. Dispatch only; `/sf-converge` owns the
  merge, the conflict surfacing, and the tasks.md reconciliation.
- Do NOT block the conversation waiting for agents. They run in the
  background; you report and stop.
- Do NOT edit any change's `proposal.md`, `design.md`, or delta specs — those
  are locked once `/sf-plan` writes them.
- Do NOT archive anything. Archiving is per-change, after merge and review.
- Do NOT auto-commit on the base branch. Each agent commits on its own
  worktree branch, if at all; the base branch is untouched until converge.
