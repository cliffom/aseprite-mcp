---
name: sf-archive
description: Archive a merged change. Merges the change's delta specs (ADDED/MODIFIED/REMOVED) into sugar/specs/<capability>/spec.md, then moves the change directory to sugar/changes/archive/<YYYY-MM-DD>-<name>/.
---

# /sf-archive

You are finalizing a completed change. Two jobs, in strict order:

1. **Merge delta specs** into the long-lived capability specs.
2. **Move the change directory** into the archive.

Run this AFTER the change is merged to the main branch. The archived copy
preserves what the change looked like before the merge — it's the historical
record.

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

1. **With a name:** `/sf-archive add-jwt`.
2. **No argument, one active change with all tasks complete:** use it.
3. **No argument, multiple candidates:** `AskUserQuestion` to pick one.

If no active changes exist, stop and tell the user.

## Step 1 — Pre-flight checks

Before touching anything, verify:

### 1a. All tasks complete

Read `sugar/changes/<name>/tasks.md`. Count unchecked `- [ ]`.

- If any tasks are unchecked, ask via `AskUserQuestion`:
  - "Archive anyway (N tasks will be archived as deferred)"
  - "Cancel — finish tasks first"
  - "Cancel — remove the unchecked tasks from tasks.md first"

Don't silently archive an incomplete change.

### 1b. Change has been merged

Ask the user to confirm the change has been merged to the main branch.
This skill doesn't verify merge status automatically (it's the user's
call — they may archive from a feature branch in some workflows).

Use `AskUserQuestion`:
- "Merged — proceed with archive"
- "Not merged yet — cancel"

If cancelled, stop.

### 1c. Delta specs are well-formed

For each `sugar/changes/<name>/specs/<capability>/spec.md`:
- Check that top-level headings are only `## ADDED Requirements`,
  `## MODIFIED Requirements`, `## REMOVED Requirements` (any subset).
- Check that every `### Requirement:` has either at least one
  `#### Scenario:` (for ADDED/MODIFIED) or a reason line (for REMOVED).
- Check that MODIFIED and REMOVED requirement names exist in the current
  `sugar/specs/<capability>/spec.md`.

If any check fails, stop. Report the specific issue with
`file:line` context. Tell the user to fix the delta spec and re-run. Do
NOT attempt repairs — delta specs are authoritative.

## Step 2 — Merge delta specs

For each capability touched by the change, in alphabetical order for
determinism:

### 2a. Load or create the long-lived spec

Read `sugar/specs/<capability>/spec.md`. If it doesn't exist:
- Create `sugar/specs/<capability>/` directory.
- Initialize the spec with the scaffold:

  ```markdown
  # <Capability> specification

  ## Purpose

  <Leave a placeholder — the user fills this in after the first archive.>

  ## Requirements
  ```

### 2b. Apply REMOVED first

For each `### Requirement: <name>` under `## REMOVED Requirements`:
- Find the matching requirement block in the long-lived spec. The match is
  by the full `### Requirement: <name>` heading text.
- Delete the requirement block — from its `### Requirement:` heading down
  to (but not including) the next `### Requirement:` heading or the next
  `## ` section.
- If no match found, stop. This should have been caught in pre-flight; if
  we got here, report it as a bug.

### 2c. Apply MODIFIED next

For each `### Requirement: <name>` under `## MODIFIED Requirements`:
- Find the matching requirement in the long-lived spec.
- Replace the entire requirement block (heading + description + scenarios)
  with the MODIFIED version's content.
- Preserve heading level.

### 2d. Apply ADDED last

For each `### Requirement: <name>` under `## ADDED Requirements`:
- Check the long-lived spec doesn't already have a requirement with that
  name. If it does, stop and report — this indicates a conflict with a
  concurrent change that already archived.
- Append the full requirement block (heading + description + scenarios) to
  the end of the `## Requirements` section.

### 2e. Preserve file formatting

- Keep trailing newlines consistent.
- Don't reorder unaffected requirements.
- Don't rewrap prose or change whitespace outside the affected blocks.
- Result must still match the long-lived spec format documented in the
  sugar-model preamble above.

After each capability is merged, report: `"merged <N> ADDED / <M> MODIFIED
/ <K> REMOVED into sugar/specs/<capability>/spec.md"`.

## Step 3 — Move the change to archive

Once all capabilities are merged:

```bash
mkdir -p sugar/changes/archive
mv sugar/changes/<name> sugar/changes/archive/$(date +%Y-%m-%d)-<name>
```

Use today's date in `YYYY-MM-DD` form. If a directory with that exact path
already exists (same change archived twice on the same day), append `-2`,
`-3`, etc.

## Step 4 — Report

One-liner in the conversation:

```
archived <name> → sugar/changes/archive/<YYYY-MM-DD>-<name>
  merged: <total ADDED> added / <total MODIFIED> modified / <total REMOVED> removed
  capabilities touched: <cap1>, <cap2>
```

Stop.

---

## What NOT to do in this skill

- Do NOT reorder step 2. REMOVED then MODIFIED then ADDED is deliberate —
  it avoids spurious "name already exists" conflicts when a change removes
  a requirement and adds a new one with the same name.
- Do NOT modify the archived copy of the change. The archived directory is
  the historical record — it should reflect what the delta specs looked
  like before the merge, not after.
- Do NOT attempt to resolve spec conflicts across concurrent changes. If a
  conflict is detected (ADDED name already exists, MODIFIED or REMOVED name
  missing), stop and ask the user.
- Do NOT auto-commit the spec changes. The user runs git themselves.
- Do NOT re-run the merge if called twice on the same change. If the change
  directory is already in `archive/`, stop and tell the user it's already
  archived.
- Do NOT touch `sugar/ideas/<slug>.md` — idea one-pagers live forever, even
  after their change archives. They're a record of where the change came
  from.
