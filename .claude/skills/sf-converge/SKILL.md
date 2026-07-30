---
name: sf-converge
description: Merge the worktree branches from a /sf-parallel run back into the base branch, one at a time in dependency order. Stops on the first conflict with file:line context; never auto-resolves. Verifies each change's tasks.md is complete before counting it landed.
---

# /sf-converge

You are reconciling a parallel build. `/sf-parallel` dispatched several changes
into isolated git worktrees; their build agents have (mostly) finished. Your
job is to bring those branches back together on the base branch **safely** —
one merge at a time, in order, stopping the moment a merge isn't clean.

You do NOT resolve conflicts silently and you do NOT review code quality.
Surface conflicts with `file:line` and hand them to the user. Code review is
`/sf-review`, run after convergence is clean.

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

## Step 0 — Load the run ledger

Read `sugar/changes/.parallel-run.md` (written by `/sf-parallel`). It lists the
changes, their worktree branches, the base branch, and a suggested merge order.

If the ledger is missing, the user may be converging a run from memory:
1. Ask for the change names and/or worktree branches via `AskUserQuestion`, or
2. Discover candidate branches with `git branch --list` / `git worktree list`
   and confirm the set with the user before touching anything.

Do not guess which branches belong to the run. Confirm the set explicitly —
merging the wrong branch is expensive to undo.

## Step 1 — Confirm readiness

For each change in the ledger, establish two things before merging:

### 1a. The agent finished

If a change is still `dispatched`/`queued` (its background agent hasn't
reported), do NOT merge it. Either:
- Proceed with the changes that ARE done and leave the rest for a later
  converge pass, or
- Stop and tell the user to wait for the outstanding agent.

Use `AskUserQuestion` if any change is unfinished. Never merge a half-built
branch.

### 1b. Resolve the merge order

Use the ledger's suggested order: independent changes first, then any change
marked `blocked-on: <other>` after the change it depends on. If two changes
share a capability and were run in parallel anyway (the user overrode the
gate), put the smaller / lower-risk one first so the conflict, if any, surfaces
against a smaller base.

Restate the final order in one line before merging.

## Step 2 — Merge, one change at a time

Make sure the working tree is clean and you're on the base branch:

```bash
git status --porcelain        # must be empty; if not, stop and tell the user
git checkout <base>
```

Then, for each change in the resolved order:

### 2a. Merge its branch

```bash
git merge --no-ff <worktree-branch>
```

Use `--no-ff` so each change lands as one identifiable merge commit — it keeps
the history legible and makes a single change easy to revert if review later
rejects it.

### 2b. On a clean merge

- Verify the change's `tasks.md` (read it from the now-merged tree at
  `sugar/changes/<name>/tasks.md`). Count unchecked `- [ ]`. If any remain, the
  agent didn't finish — record it as **landed-incomplete** and list the
  unchecked task numbers. Don't block the run on it, but it must show in the
  final report.
- Mark the change `merged` in the ledger.
- Move to the next change.

### 2c. On a conflict — STOP

`git merge` reports conflicts. Do this and then halt the loop:

```bash
git diff --name-only --diff-filter=U     # the conflicted files
```

Report each conflicted file with the conflicting hunks (`file:line`), in one
block. Then offer, via `AskUserQuestion`:
- **I'll resolve it now, you guide** — walk the user through each conflicted
  hunk; you make the edit they direct, then `git add` + `git commit` to
  complete the merge, and continue the loop.
- **Abort this merge** — `git merge --abort`, leave the base branch clean,
  mark the change `conflict` in the ledger, and continue with the remaining
  changes (they may still merge cleanly).
- **Stop the whole converge** — `git merge --abort` and halt entirely so the
  user can rework the change.

Never resolve a conflict by picking a side on your own. You don't know which
change's intent wins — the user does.

## Step 3 — Update the ledger

After the loop, update `sugar/changes/.parallel-run.md`:
- Set each change's `State` to `merged`, `landed-incomplete`, `conflict`, or
  `deferred`.
- Set the run `Status` to `converged` (all merged) or `partial` (some
  conflicted/deferred).

The ledger is scratch state — once the user is satisfied the run is fully
landed, it can be deleted. Don't archive it.

## Step 4 — Report

One block in the conversation:

```
Converged into <base>:
  ✓ refactor-billing   merged            (billing)
  ✓ add-jwt            merged            (auth)
  ⚠ fix-timeout        landed-incomplete (auth, session) — tasks 3.2, 3.3 unchecked
  ✗ <change>           conflict — aborted, needs rework

Run status: partial
Next: run /sf-review on the combined diff, then /sf-archive each merged change.
```

Then stop. Point at `/sf-review` for the combined diff and `/sf-archive` per
change. Do NOT review, fix, or archive here.

---

## What NOT to do in this skill

- Do NOT resolve a merge conflict by choosing a side automatically. Surface it,
  get the user's call, then apply their resolution.
- Do NOT continue merging after a conflict without an explicit decision. A dirty
  index poisons every following merge.
- Do NOT merge a branch whose build agent hasn't finished. Half-built code on
  the base branch is worse than waiting.
- Do NOT fast-forward. Use `--no-ff` so each change is one revertible merge
  commit.
- Do NOT mark a change `merged` if its tasks.md still has unchecked tasks — that
  status is `landed-incomplete`, and the report must say so.
- Do NOT run `/sf-review` or `/sf-archive` yourself. Convergence ends at a clean
  (or honestly-reported partial) base branch; the user drives what's next.
- Do NOT push or force-push. The user pushes when they're ready.
