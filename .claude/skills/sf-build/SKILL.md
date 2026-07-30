---
name: sf-build
description: Execute a change's tasks.md top-to-bottom, writing code and marking checkboxes [x] as each task completes. Resumable — skips tasks already marked done.
---

# /sf-build

You are implementing a change by working through its `tasks.md` in order.
For each unchecked task, you make the code changes that satisfy it, mark
the checkbox as `[x]`, and move to the next.

This skill is stateful via the file itself — the checkbox state IS the
progress marker. If the session is interrupted and resumed, you pick up
where you left off by scanning for the next `- [ ]`.

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

## Step 0 — Locate the change

The user invokes this skill one of three ways:

1. **With a name:** `/sf-build add-jwt` → read `sugar/changes/add-jwt/`.
2. **No argument, one active change:** list `sugar/changes/` (excluding
   `archive/`). If exactly one, use it.
3. **No argument, multiple active changes:** `AskUserQuestion` to pick one.
4. **No active changes:** stop. Tell the user to run `/sf-plan` first.

Read in order: `proposal.md`, `design.md`, all delta specs under
`specs/<capability>/spec.md`, then `tasks.md`. Also read `CLAUDE.md` at the
repo root for project conventions.

## Step 1 — Detect progress

Scan `tasks.md`:

- Count total tasks (lines matching `^- \[[ x]\] \d+\.\d+ `).
- Count completed (`^- \[x\] `).
- Find the first unchecked task (`^- \[ \] `).

Report in one line: "Change `<name>`, X / Y tasks complete. Starting with
task Z.W." Then proceed without waiting for confirmation.

If all tasks are already checked, stop and tell the user to run `/sf-review`
next.

## Step 2 — The execution loop

For each unchecked task, in order:

### 2a. Understand the task

Read the task line. If its description is ambiguous, check the relevant
section of `design.md` and the delta specs to infer intent. If still
ambiguous, stop and ask the user what the task means — do NOT guess.

### 2b. Make the code changes

Implement ONLY what the task describes. Rules:

- Don't bundle work from future tasks. "While I'm here" is a trap.
- If you discover the task is wrong (specs contradict it, dependency
  missing), stop and tell the user. Don't silently do something different.
- Use the project's existing patterns — check neighboring files before
  inventing new conventions. `CLAUDE.md` is a starting point, not the
  complete picture.
- Run targeted tests after each task group if the project has a fast test
  command (check `CLAUDE.md`). If tests fail on a change you just made,
  stop and diagnose — do NOT mark the task done.

### 2c. Mark the task complete

After the code change is written and (if applicable) tests pass, edit
`tasks.md`:

- Change `- [ ] N.Y` to `- [x] N.Y` for that task.
- Do NOT reorder, reword, or renumber tasks.
- Do NOT mark future tasks.

### 2d. Continue

Move to the next unchecked task and repeat.

## Step 3 — Handling surprises

### Task reveals a missing prerequisite

If implementing task N.Y requires something that should have been an earlier
task, stop. Tell the user what's missing and ask whether to:
1. Insert a new task before N.Y and do that first.
2. Mark N.Y as blocked and skip to N.(Y+1).
3. Abort and revise `tasks.md` via `/sf-plan`.

Use `AskUserQuestion`. Don't silently reorder.

### Task can't be done as written

If a task is wrong (spec says X but the code can only do Y), stop. Explain
the conflict, quote the relevant spec/task text, and ask whether the task,
spec, or both need to change. Editing specs is out of scope for `/sf-build`
— stop and hand back to `/sf-plan` for revision.

### Getting stuck on a single task

If you've made three attempts and the task still isn't working, stop. State
what you tried, what failed, what you think the root cause might be. Ask
the user for guidance. Do not thrash.

## Step 4 — Finish

When the last task's checkbox is marked `[x]`:

1. Report: "All X tasks complete. Change `<name>` is ready for review."
2. Tell the user: "run `/sf-review` to audit the diff".

Stop. Do NOT invoke `/sf-review` yourself. Do NOT archive.

---

## What NOT to do in this skill

- Do NOT edit any file other than the task-related code changes and
  `tasks.md` itself. No edits to `proposal.md`, `design.md`, or specs —
  those are locked once `/sf-plan` writes them.
- Do NOT mark a task complete without real code to show for it. A task
  with no diff is a task not done.
- Do NOT batch-check multiple tasks at once. Mark each as you complete it.
- Do NOT skip ahead. Tasks have order for a reason.
- Do NOT refactor adjacent code opportunistically. Stay in the task's
  scope. Cleanup work belongs in its own change.
- Do NOT create git commits automatically — the user commits when they're
  ready.
