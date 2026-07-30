---
name: sf-ship
description: Ship the current branch. Detect + merge the base branch, run the project's tests, bump VERSION and CHANGELOG if they exist, commit in bisectable chunks, push, and open a PR. Works with or without a sugar/changes/ directory — a change enriches the PR body but isn't required. Gates only on real decisions — conflicts, test failures, MINOR/MAJOR bumps. Points at /sf-archive when change-backed; does not archive.
---

# /sf-ship

You are landing a finished, already-reviewed change — taking it from a clean
branch to a pushed PR. The user said `/sf-ship`, which means **do it**. Run
straight through. Stop only at genuine decision gates: a merge conflict, a
failing test, or a MINOR/MAJOR version bump. Everything else is automatic.

You do NOT review code quality here — that was `/sf-review`. You do NOT archive
here — that's `/sf-archive`, after the PR merges. Your job is the mechanical,
high-stakes middle: merge base, verify, commit cleanly, push, open the PR.

Ship works on **any** branch. A `sugar/changes/<name>/` directory, if one
applies, enriches the PR body and adds a tasks-complete check — but it is never
required. A quick fix or a doc tweak that never went through `/sf-plan` ships
just the same.

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

## Step 0 — Detect the base branch and (optionally) the change

Ship is a git operation first. It works on **any** branch with commits to land —
a sugar-flow change directory is enrichment, not a requirement. Two modes:

**Change-backed mode** — there's a `sugar/changes/<name>/` for this work. Use it
for the unchecked-task warning and a richer PR body. Resolve which change:
1. **Named:** `/sf-ship add-jwt` → use `sugar/changes/add-jwt/`.
2. **No arg, branch name matches a change directory:** use that one.
3. **No arg, exactly one active change:** use it.

When change-backed, read its `tasks.md`. Count unchecked `- [ ]`. If any remain,
surface the unchecked task numbers and ask via `AskUserQuestion` whether to ship
anyway or stop. Don't silently ship a half-built change.

**Branch-only mode** — no change directory applies (none named, no match, no
`sugar/changes/` at all, or several active and none matches the branch). Do NOT
stop and do NOT force the user to pick one — just ship the branch as-is. Derive
everything from git: the branch name, the commit log, and the diff. Skip the
tasks check (there's no tasks.md). If active changes exist but none was selected,
mention once that passing a name (`/sf-ship <name>`) would enrich the PR body —
then proceed without it.

**The base branch.** Detect it:

```bash
git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@'
```

Fall back to `main`, then `master`. Allow override via a second argument
(`/sf-ship add-jwt develop`).

## Step 1 — Preflight

```bash
git rev-parse --abbrev-ref HEAD     # current branch — must NOT be the base
git status --porcelain              # uncommitted changes are fine; they ship too
git diff <base>...HEAD --stat
git log <base>..HEAD --oneline
```

If you're **on the base branch**, stop — there's nothing to ship and no feature
branch to push. Tell the user to check out their change branch first.

Print a one-block summary: branch, base, file/line counts, commit count, and
whether the tree has uncommitted changes that will be included.

## Step 2 — Merge the base branch

Bring the change up to date so the PR merges cleanly and tests run against the
latest base:

```bash
git fetch origin <base>
git merge origin/<base> --no-edit
```

**On a clean merge** (or "Already up to date"), continue.

**On a conflict — STOP.** Show the conflicted files and hunks with `file:line`:

```bash
git diff --name-only --diff-filter=U
```

Then offer, via `AskUserQuestion`:
- **Resolve now, you guide** — walk each hunk; you make the edit they direct,
  then `git add` + commit the merge, and continue.
- **Abort** — `git merge --abort`, leave the tree clean, stop the ship.

Never pick a side on your own. Simple, unambiguous conflicts in generated files
(`VERSION`, lockfiles, `CHANGELOG.md`) you may resolve mechanically — but say so
in the report. Anything touching source logic goes to the user.

## Step 3 — Run the project's tests

Sugar-flow has no test runner of its own. Read `CLAUDE.md` (repo root) for the
test command. If it names one (e.g. `npm test`, `pytest`, `cargo test`, `bun
test`), run it and capture the output.

- **Tests pass** → continue.
- **Tests fail** → STOP. Apply `## Root-cause discipline

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
pursue. Spinning in place wastes everyone's time.` — reproduce,
  read the real error, find the cause. Report it and ask whether to fix now or
  abort the ship. Do NOT push failing code.
- **No test command in CLAUDE.md and no obvious runner** → note "no tests run
  (none configured)" in the report and continue. Don't fabricate a command.

## Step 4 — Version + CHANGELOG (only if they already exist)

Sugar-flow imposes nothing. Touch these files **only if the repo already has
them** — check for a `VERSION` file (or a `version` field in
`package.json`/`Cargo.toml`/`pyproject.toml`) and a `CHANGELOG.md`. If neither
exists, skip this step silently.

If a version file exists:
1. Infer the bump level from the change: bugfix → PATCH, backward-compatible
   feature → MINOR, breaking change → MAJOR.
2. **PATCH auto-applies.** For **MINOR or MAJOR**, confirm the level via
   `AskUserQuestion` before writing — those are judgment calls the user owns.
3. Write the new version to the file(s) that already carry it. Keep
   `package.json` and `VERSION` in sync if both exist.

If `CHANGELOG.md` exists, prepend an entry for the new version dated today,
grouped into the headings the file already uses (Features / Fixes / Chores, or
whatever convention is present). Match the existing format — don't impose a new
one.

## Step 5 — Commit in bisectable chunks

Stage and commit the change as logical, independently-valid units, dependencies
first. A typical order:

1. Infrastructure / migrations / config.
2. Core logic (models, services).
3. Callers / UI / wiring.
4. Tests.
5. `VERSION` + `CHANGELOG.md` (if touched) as the final commit.

Each commit message: a concise imperative subject, a body only if the "why"
isn't obvious. End the final commit message with:

```
Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
```

Don't squash unrelated work into one mega-commit, and don't split a single
logical change across commits that wouldn't each build. If the tree was already
committed and clean, skip straight to Step 6 — there's nothing to commit.

## Step 6 — Verification gate

If you changed any code after Step 3 (conflict resolution, a test fix), **re-run
the tests**. No "should still pass" claims — run them. If the project has a build
step (in CLAUDE.md), run it too. Fail here → stop and report; don't push.

If nothing changed since Step 3, skip — the earlier run stands.

## Step 7 — Push

```bash
git push -u origin <current-branch>
```

If the branch is already pushed and up to date, skip the push but continue —
re-running `/sf-ship` should update the PR, not error out.

## Step 8 — Open (or update) the PR

If GitHub `gh` is available:

```bash
gh pr view --json url,state 2>/dev/null   # already a PR for this branch?
```

- **No PR** → `gh pr create --base <base> --title "<title>" --body "<body>"`.
- **PR exists** → update its body with `gh pr edit` rather than creating a new one.

**Title:** concise, change-shaped — e.g. `add-jwt: issue + verify JWTs on login`.
In branch-only mode, derive it from the branch name and the dominant commit.

**Body** — compose from whatever's available:
- *Change-backed:* one-paragraph summary from `proposal.md`, the capabilities
  touched (from the delta specs), and tasks complete (`X / Y`).
- *Branch-only:* a short summary synthesized from the commit log (`git log
  <base>..HEAD`) and the diff stat — what changed and why, in a couple of lines.

In both modes append: the test result from Step 3/6, and the new version if
bumped.

End the PR body with:

```
🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

If `gh` is not installed or the remote isn't GitHub, print the push result and
the compare URL (or `git remote -v` host) so the user can open the PR manually.

## Step 9 — Report and stop

One block in the conversation:

```
Shipped <change-name | branch>:
  branch    <branch> → <base>
  merged    base clean | resolved N conflicts
  tests     pass (<cmd>) | none configured
  version   <old> → <new> | unchanged
  commits   <N> pushed
  PR        <url> | manual: <compare-url>

Next: merge the PR[, then run /sf-archive <change-name>].
```

Then stop. Do NOT merge the PR yourself. Only mention `/sf-archive` in
**change-backed mode** — there's nothing to archive for a branch-only ship, so
omit that line.

---

## What NOT to do in this skill

- Do NOT push code with failing tests. The verification gate is the whole point.
- Do NOT resolve a source-logic merge conflict by picking a side. Surface it,
  get the user's call, then apply their resolution. Only generated files
  (VERSION, lockfiles, CHANGELOG) may be resolved mechanically — and say so.
- Do NOT create or impose `VERSION`/`CHANGELOG.md` if the repo doesn't already
  have them. Conditional, not mandatory.
- Do NOT bump MINOR or MAJOR without confirming the level with the user. PATCH
  auto-applies; the bigger calls are theirs.
- Do NOT review code quality or completeness — that's `/sf-review`. Ship assumes
  review already happened; it does not re-run it or gate on it.
- Do NOT archive the change or merge the PR. Ship ends at an open PR; the user
  drives what's next.
- Do NOT squash everything into one commit. Bisectable chunks, dependencies
  first, each independently valid.
- Do NOT force-push. If the branch diverged unexpectedly, stop and ask.
- Do NOT require a `sugar/changes/` directory. If none applies, ship the branch
  branch-only — derive the PR from git. Never block a ship for lack of a change.
