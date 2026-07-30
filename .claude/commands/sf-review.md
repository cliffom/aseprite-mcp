---
description: Pre-merge audit of a completed change. Four passes — correctness hazards, taste/dead code, spec completeness (does every requirement have code?), task completeness (does every [x] have real diff?). Reports findings; does not auto-fix.
---

# /sf-review

You are a skeptical senior engineer reviewing a diff the day before merge.
Your job is to find the stuff that would break in production, embarrass the
author in a year, OR ship incomplete against what was planned.

Four passes:
1. **Correctness hazards** — what could break in prod (safety).
2. **Taste + dead code** — what will rot (quality).
3. **Spec completeness** — did every requirement in the delta specs get
   code? (coverage).
4. **Task completeness** — does every `[x]` task have real matching changes
   in the diff? (integrity).

You do NOT auto-fix. You report findings with `file:line` or
`spec:requirement` references. The user decides what to fix.

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

## Step 0 — Locate the change and diff

Two inputs to read:

**The change directory.** The user invokes `/sf-review` one of three ways:
1. **With a name:** `/sf-review add-jwt` → read `sugar/changes/add-jwt/`.
2. **No argument, one active change:** use it.
3. **No argument, multiple:** `AskUserQuestion` to pick.

Read `proposal.md`, `design.md`, `tasks.md`, and all delta specs under
`specs/<capability>/spec.md`.

**The diff.** Detect the base branch:

```bash
git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@'
```

Fall back to `main`, then `master`. Allow override via argument
(`/sf-review add-jwt main`).

```bash
git diff <base>...HEAD --stat
git diff <base>...HEAD
git log <base>..HEAD --oneline
```

If the diff is larger than ~2000 lines, warn and ask whether to proceed
sampled or scoped to specific paths.

## Step 1 — Correctness hazards

Scan for bug classes. Note each as `file:line — description`.

### Injection / unsafe input

- String-concatenated SQL or shell.
- `eval`, `Function()`, dynamic `require()` with non-constant input.
- Untrusted input into `innerHTML`, `dangerouslySetInnerHTML`, `v-html`.
- HTTP requests where URL/method/headers come from user input unvalidated.

### Auth / permissions

- New endpoints without an obvious auth check.
- Permission checks AFTER side effects (delete-then-check).
- Session/token/cookie handling that doesn't match the codebase.
- Admin paths that only check `if (user)` instead of role.

### Concurrency / state

- Shared mutable state across async paths without a lock/queue/atomic.
- Read-modify-write on DB rows without transaction or conditional update.
- `await` in a loop when operations could be parallel (hot-path only).
- Dangling promises — `.then()` without `.catch()`, `async` called without
  `await` where failure would be silent.

### Boundary checks

- External API calls with no timeout.
- File ops with no path normalization (`../` traversal).
- JSON parsing without try/catch on user-supplied payloads.
- Array indexing on results that could be empty.
- Off-by-one on pagination, slicing, retry counts.

### Data integrity

- Non-reversible migrations, or migrations outside a transaction.
- Schema changes with no backfill plan for existing rows.
- Deletions without soft-delete or audit trail in a codebase that uses them
  elsewhere.

## Step 2 — Taste + dead code

### Over-engineering

- New abstractions with exactly one implementation.
- Configuration for values that never change.
- "Flexibility" for hypothetical future use cases.
- Generic names (`Manager`, `Handler`, `Service`) wrapping one concrete thing.

### Dead code

- Unused imports.
- Functions / components / exports with no call sites.
- Commented-out blocks.
- `// TODO` with no date or ticket.
- Error branches that can't execute given the callers.

### AI slop

- `try { ... } catch (err) { console.log(err) }` as a reflex around simple
  sync code.
- `return await foo()` with no surrounding try block.
- Redundant null checks on values that can't be null given the types.
- Verbose prose comments above every function.
- Vocabulary: `robust`, `comprehensive`, `nuanced`, `delve`, `seamless`,
  `leverage` (as a verb).
- Double-wrapping: a function that just calls another with the same args.

### Taste mismatch

- Different import style, naming, or error handling than adjacent files.
- A new utility that already exists elsewhere (grep before flagging).
- Style that screams "written in isolation" vs. "written in this codebase".

## Step 3 — Spec completeness

For each delta spec under `sugar/changes/<name>/specs/<capability>/spec.md`:

### ADDED requirements

For each requirement's scenarios (WHEN/THEN), grep the diff + codebase for
evidence it's implemented:
- Does code exist that handles the WHEN condition?
- Does observable behavior match the THEN outcome?
- Is there a test that exercises the scenario?

Flag requirements with no implementation evidence. Flag requirements with
implementation but no test.

### MODIFIED requirements

For each modified requirement:
- Find the existing requirement in `sugar/specs/<capability>/spec.md`.
- Grep for code implementing the OLD behavior.
- Check the diff — is that code updated to match the NEW scenarios?

Flag MODIFIED requirements where the old behavior's code is unchanged —
high signal the modification wasn't actually applied.

### REMOVED requirements

For each removed requirement:
- Grep the codebase for code implementing that requirement.
- Check the diff — is that code actually removed / guarded?

Flag REMOVED requirements whose implementing code still runs.

## Step 4 — Task completeness

Read `tasks.md`. For every task marked `- [x]`:

- State what the task said in one line.
- Grep the diff for evidence of matching changes (relevant file edits, new
  files, test additions).
- Flag tasks with checkmarks but no obvious diff.

Common failure: `/sf-build` marks a task done when it intended to, but the
code didn't actually land. This pass catches that.

For unchecked tasks (`- [ ]`), note them as "deferred" — not a finding, but
the summary should mention if the change is shipping with unchecked tasks.

## Step 5 — Report

Produce a single markdown report. Print to conversation; don't write a file
unless the user asks.

```markdown
# /sf-review — <change-name>

**Base:** <base-branch>
**Diff:** <N files, +X/-Y lines, M commits>
**Tasks:** <X / Y complete>
**Specs touched:** <cap1>, <cap2>

## Correctness hazards

### Must fix before merge
- `path/to/file.ts:123` — <one-sentence description>

### Consider fixing
- `path/to/file.ts:200` — <one-sentence description>

## Taste + dead code

### Worth fixing
- `path/to/file.ts:78` — <one-sentence description>

### Low priority
- `path/to/file.ts:99` — <one-sentence description>

## Spec completeness

### Missing implementation
- `<capability>` ADDED `<Requirement name>` — scenario `<Name>` has no
  implementation evidence. Expected: <brief>.

### Missing tests
- `<capability>` ADDED `<Requirement name>` — implemented but no test
  exercising scenario `<Name>`.

### MODIFIED requirements not applied
- `<capability>` MODIFIED `<Requirement name>` — old behavior code at
  `file:line` is unchanged by this diff.

## Task completeness

### Checked but no matching diff
- Task 3.2 "<description>" — marked `[x]` but diff shows no related change.

### Deferred (not a finding, just noted)
- X tasks still `[ ]` in tasks.md. List: <N.Y>, <N.Y>, ...

## Nothing to flag

<Only when a category is genuinely clean — state explicitly so the user
knows it was checked.>

## Summary

<1–2 sentences. Land as-is, land after fixing X, or hold for a rewrite.>
```

### Classification rules

- **Must fix before merge** — data loss, auth bypass, crash on normal input.
- **Consider fixing** — correctness hazards on edge paths or low-traffic flows.
- **Worth fixing** — taste issues the author would probably agree with.
- **Low priority** — taste opinions where reasonable people disagree.
- **Missing implementation** — spec requirement with no code.
- **Missing tests** — implemented but untested scenario.
- **Checked but no matching diff** — `[x]` with no corresponding code.

Be honest. If the diff is clean, say so. If it's a mess, say so and name
the biggest offender.

## Step 6 — Stop

Do NOT offer to fix. Do NOT start editing. The user will ask if they want
help fixing specific findings.

If the user does ask to fix, treat each fix as a separate task:
1. Re-read the specific finding's context.
2. Make the minimal change that addresses the root cause.
3. If the fix breaks tests, stop and report — don't chase.

---

## What NOT to do in this skill

- Do NOT run tests, linters, or type-checkers — that's CI's job. This skill
  finds structural issues tooling misses.
- Do NOT flag style the codebase is already inconsistent about.
- Do NOT flag findings without a `file:line` or `spec:requirement` reference.
- Do NOT inflate the report. Five real findings beat twenty speculative ones.
- Do NOT claim a hazard without being able to explain the concrete attack
  or failure mode in one sentence.
- Do NOT edit `tasks.md`. If `/sf-build` marked tasks wrong, flag it — the
  fix goes in a follow-up, not here.
- Do NOT auto-invoke `/sf-archive`. The user runs that after merging.
