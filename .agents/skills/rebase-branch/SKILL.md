---
name: rebase-branch
description: Rebase the current branch — or the whole stack it belongs to — onto its freshly-fetched base, losing no work from either side. Use when asked to 'rebase this branch', 'rebase onto <base>', 'update my branch', or 'restack my stack'. Not for merging or squashing.
---

# rebase-branch

This file holds the pre-flight and the mechanics both paths share. The ordered steps live in one
of two path files, and **pre-flight picks which** — you always read exactly one of them:

- [references/gh-stack-cascade.md](references/gh-stack-cascade.md) — `gh-stack` tracks this
  branch's stack, so the whole chain can be cascaded in dependency order.
- [references/plain-rebase.md](references/plain-rebase.md) — nothing tracks the relationship, so
  you rebase the branch in front of you. Branches may still be stacked on top of it by hand;
  that path detects them and says what they'll need, but it doesn't cascade.

The axis is **who owns the chain**, not how many branches there are.

## Prime directive

**Preserve every change from both sides.** Every step is subordinate to this. When a choice is
between "more automatic" and "provably loses nothing," choose the latter. The loss gate below is
the backstop that enforces it.

## Safety

- A hidden backup ref is written for **every** branch about to be rewritten, before any
  history rewrite; the loss gate restores from it on any detected loss. `ORIG_HEAD` and the
  reflog are the fallback net.
- Never reach for blanket `-X ours` / `-X theirs` or `git checkout --ours/--theirs`: each drops
  one side wholesale, so a rebase that finishes clean that way has almost certainly lost work.
  Resolve from both sides' content instead.
- Pushing rewritten history is outward-facing. Only ever `--force-with-lease`. A plain
  force-push clobbers teammate commits pushed after your last fetch. The push set is exactly
  the branches this run rebased.
- Compare read-only — `diff <(git show A:path) <(git show B:path)` — rather than dumping to
  temp files; reach for a `/tmp` file only when the extraction must outlive a single command,
  or is large enough that re-extracting would be wasteful.

## Pre-flight (no rebase yet)

Base-independent guards, in this order — the rebase-in-progress checks come **first**, because
a paused rebase leaves HEAD detached and would otherwise trip the current-branch abort below:

- **Rebase already in progress** — check the **cascade** (`gh stack`'s multi-branch rebase)
  state before the plain-git one: a paused cascade leaves the plain-git state dirs too, and the
  plain-git commands there advance one branch and orphan the rest.
  - `test -e "$(git rev-parse --git-common-dir)/gh-stack-rebase-state"` ⇒ a paused **cascade**.
    Report it, then **read [references/gh-stack-cascade.md](references/gh-stack-cascade.md) in
    full** and resume from its recovery section — a `--continue` still owes you conflict
    resolution for the next pause and the loss gate before any push.
  - Else if `test -d "$(git rev-parse --git-path rebase-merge)"` or
    `test -d "$(git rev-parse --git-path rebase-apply)"` ⇒ **resume the existing rebase**:
    report it and offer `git rebase --continue` or `git rebase --abort`. (These are existence
    tests: `git rev-parse --git-path <name>` merely joins a path and always succeeds. Rebase
    state is **per-worktree**, so `--git-path` is the right root for these two.)
- **Current branch**: `git branch --show-current`. Empty ⇒ detached HEAD with no rebase in
  progress ⇒ **abort gracefully** ("not on a branch; check one out first").
- **Fetch**: `git fetch origin` — every path needs fresh refs. If the repo has no `origin`,
  fetch the remote it does have; on failure, report and stop, since nothing below can run on
  stale refs.
- **Pick the path** — `test -e "$(git rev-parse --git-common-dir)/gh-stack"`. **Use
  `--git-common-dir`, not `--git-path`**: the metadata is per-repository, so from a linked
  worktree `--git-path` resolves to the worktree's private dir, finds nothing, and sends a
  stacked repo down the plain path — a silent fail-open into the exact orphaning this
  guards against.
  - **Absent** ⇒ **read [references/plain-rebase.md](references/plain-rebase.md) in full and
    follow it.** Absent means only that `gh-stack` isn't tracking anything here — branches may
    still be stacked on this one by hand, which that file checks for. If the user says `gh-stack`
    manages the branch anyway, read the cascade file instead and let its S1 settle membership.
  - **Present** ⇒ **run no further command until you have read
    [references/gh-stack-cascade.md](references/gh-stack-cascade.md) in full**, then follow it.
    Beyond the two recovery commands named above, it is the only source for `gh stack`
    invocations — treat any others you recall from memory as wrong.

  Either way: **read the path file before running anything else.** Both replace the ordered work
  entirely; this file only holds what they have in common.

## Dirty tree

Run `git status --porcelain` before any rewrite (the path file says when — the cascade path's
S1 replaces this guard with its own handling). If non-empty ⇒ **ask** (single
`AskUserQuestion`): **stash & restore** (autostash — restored after) · **commit & push, then
rebase** (commit the working tree onto the current branch, then `git push` it — setting
upstream if needed — so the pre-rebase state is safely on the remote before any history
rewrite; propose a message) · **abort**.

## Backup refs

`<run-id>` = `date +%Y%m%d-%H%M%S`. Don't use an ISO-8601 timestamp: its `:` separators are
illegal in ref names, so `update-ref` would fail mid-loop with the safety net half-built.

**First** check `git for-each-ref refs/rebase-skill/`. Anything left over means an earlier run
never completed, and its refs are the only pointer to that run's pre-rebase state, so **ask**
before proceeding rather than writing over it:

- **adopt** — reuse that run's id in the loss gate's commands for the branches it covers, and
  don't write a fresh snapshot for them;
- **discard** — delete them (command below) and snapshot afresh;
- **abort**.

Then snapshot each branch about to be rewritten, namespaced by run so a second run can never
overwrite the first one's snapshot:
`git update-ref refs/rebase-skill/<run-id>/<branch> <branch>`. This is the source the loss gate
restores from. Where a branch name contains `/`, two refs in one run can collide as a directory
and a file (`feat` vs `feat/x`) — flatten the leaf by replacing each `/` with `--`, and if the
flattened name matches one already written this run (`feat/x` vs a literal `feat--x`), stop and
ask rather than overwrite a snapshot. Use that same flattened name in **every**
`refs/rebase-skill/…` command downstream, not just in your
report.

**Keep every ref until the push resolves** — landed and verified, denied, or declined by the
user. A ref deleted at the gate leaves the force-push with no net. Then delete the run's refs in
one go:

```
git for-each-ref --format='delete %(refname)' refs/rebase-skill/<run-id>/ | git update-ref --stdin
```

## Resolving conflicts (preserve both sides)

When the rebase stops on a conflict, work **each** conflicted hunk until both sides' intent is
present in the file:

- Read **both** sides. In a rebase, `ours` = the **base** being replayed onto, `theirs` =
  **your** commit being replayed (reversed from a merge). Read each side cleanly with
  `git show :2:path` (ours/base) / `git show :3:path` (theirs/your commit), or the Read tool for
  the marked-up working file. Understand each side's _intent_ from the surrounding code and the
  commit message.
- **Auto-resolve only when both sides' intent can be preserved with high confidence** —
  e.g. non-overlapping concerns in the same hunk, mechanical/format/import reconciliations.
  Then `git add` the file(s) and `git rebase --continue`.

**Escalate** a conflict when: the two sides are **mutually exclusive** (keeping both is
impossible, so the user must choose), one side's **intent is unclear**, or the file is
**dangerous to auto-merge** (lockfiles, generated code, schema/migrations). On escalation:

- Leave the rebase **paused** at the conflicted commit (earlier resolutions are preserved; the
  backup ref guards against loss).
- **Batch all uncertain conflicts in the current commit into one `AskUserQuestion`.** For
  each, give a structured **both-sides summary**: what each side changed and why, and **why they
  collide** — plus concrete candidate resolutions as options when you have them (free-form
  fallback).
- Apply the chosen resolution, `git add`, continue, and repeat for later commits.
- In a cascade, every escalation also offers **abort the whole stack** (see the stacked file's
  recovery precedence) — many branches otherwise means many prompts with no way out.

## The loss gate (range-diff)

After the rebase completes, verify content preservation. The plain path runs this once; the
stacked path runs it once per moved branch, under that file's per-branch rules.

```
git range-diff --creation-factor=999 <MB>..refs/rebase-skill/<run-id>/<branch>  <newbase>..<branch>
```

- **Use `--creation-factor=999`.** The default (60) often _fails to pair_ a commit whose
  diff context shifted during conflict resolution (e.g. a one-line change now sitting on a
  moved base), printing it as a spurious **drop (`<`) + add (`>`)** instead of a matched
  `!`. That artifact looks exactly like a lost commit and would trip a false abort. The
  high factor makes range-diff pair aggressively and show the real diff-of-diff instead.
- Every genuinely-new commit must map to a counterpart with no unexplained content change
  (context-only shifts are fine — e.g. a `!` whose only delta is the line a hunk _replaced_,
  with its added result identical, is a base-movement artifact, not loss). A commit absent on
  the right is acceptable **only** if `git cherry <newbase> refs/rebase-skill/<run-id>/<branch>`
  marks it `-`, or it appears in neither column (already reachable from `<newbase>`, so never
  this branch's to replay) — dropping a patch-equal commit is what `--onto` and plain rebase are
  *for*.
- **Before concluding loss, rule out a pairing artifact.** A drop+add of the **same commit
  subject**, or an unpaired drop, is not loss by itself — confirm by checking the commit's
  net additions are actually present in the final tree/`HEAD`. Only a genuinely vanished
  change is loss.
- **Any _confirmed_ unexpected drop or content alteration** ⇒ do **not** keep the result:
  restore with `git reset --hard refs/rebase-skill/<run-id>/<branch>` (or abort the rebase if
  still mid-flight), report **exactly** which commit/hunk didn't map, and **ask for help**.
  `reset --hard` is the restore for the **checked-out** branch; for any other branch it's
  `git update-ref refs/heads/<branch> refs/rebase-skill/<run-id>/<branch>`, since `update-ref`
  on the current branch would move the ref without touching index or worktree and leave the repo
  looking like one enormous uncommitted diff.
- **On pass**: the branch is verified. Keep the refs (they're deleted only once the push
  resolves) and go on to the push.
