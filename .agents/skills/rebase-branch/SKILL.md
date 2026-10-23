---
name: rebase-branch
description: Rebase the current branch, or the whole stack it belongs to, onto its freshly-fetched base. Use when asked to 'rebase this branch', 'rebase onto <base>', 'update my branch', or 'restack my stack'. Not for merging or squashing.
---

# rebase-branch

This file holds the pre-flight and the mechanics both paths share. Pre-flight picks one of two
path files, which holds the ordered steps:

- [references/gh-stack-cascade.md](references/gh-stack-cascade.md) applies when `gh-stack`
  tracks this branch's stack, so the whole chain can be cascaded in dependency order.
- [references/plain-rebase.md](references/plain-rebase.md) applies when nothing tracks the
  relationship, so you rebase the branch in front of you. Branches may still be stacked on top of
  it by hand. That path detects them and says what they'll need, but it doesn't cascade.

The path depends on **who owns the chain**, not on how many branches there are.

## Prime directive

**Preserve every change from both sides.** Every step is subordinate to this. When a choice is
between "more automatic" and "provably loses nothing," choose the latter. The loss gate below is
the check that enforces it.

## Safety

- Before any history rewrite, write a hidden backup ref for **every** branch about to be
  rewritten. The loss gate restores from it on any detected loss. `ORIG_HEAD` and the reflog are
  the fallback.
- Never use blanket `-X ours` / `-X theirs` or `git checkout --ours/--theirs`. Each drops one
  side wholesale, so a rebase that finishes clean that way has almost certainly lost work.
  Resolve from both sides' content instead.
- Pushing rewritten history changes the remote that others read. Only ever `--force-with-lease`.
  A plain force-push overwrites teammate commits pushed after your last fetch. The push set is
  exactly the branches this run rebased, except that `gh stack push` sends every active member
  (the cascade path's S4 reports which).
- Compare read-only (`diff <(git show A:path) <(git show B:path)`) rather than dumping to temp
  files. Write to a file in the harness's scratch directory (else `mktemp -d`) only when output
  must outlive one command or is too long to read whole, as a long range-diff is.

## Pre-flight (no rebase yet)

Run these base-independent guards in this order. The rebase-in-progress checks come first,
because a paused rebase leaves HEAD detached and would otherwise trip the current-branch abort
below.

- **Rebase already in progress.** Check the cascade (`gh stack`'s multi-branch rebase) state
  before the plain-git one. A paused cascade leaves the plain-git state dirs too, and the
  plain-git commands there advance one branch and orphan the rest.
  - If `test -e "$(git rev-parse --git-common-dir)/gh-stack-rebase-state"` succeeds, a cascade
    is paused. Report it, then **read [references/gh-stack-cascade.md](references/gh-stack-cascade.md)
    in full** and resume from its recovery section. A `--continue` still owes you conflict
    resolution for the next pause and the loss gate before any push.
  - Else if `test -d "$(git rev-parse --git-path rebase-merge)"` or
    `test -d "$(git rev-parse --git-path rebase-apply)"` succeeds, resume the existing rebase.
    Report it and offer `git rebase --continue` or `git rebase --abort`. These are existence
    tests, because `git rev-parse --git-path <name>` only joins a path and always succeeds.
    Rebase state is per-worktree, so `--git-path` is the right root for these two.
- **Current branch.** Run `git branch --show-current`. Empty output means a detached HEAD with no
  rebase in progress, so abort gracefully ("not on a branch; check one out first").
- **Fetch.** Run `git fetch origin`, because every path needs fresh refs. If the repo has no
  `origin`, fetch the remote it does have. On failure, report and stop, since nothing below can
  run on stale refs.
- **Pick the path.** Read the local stack metadata for this branch with
  `bash ~/.agents/skills/workflow-profile/scripts/gh-stack-lookup.sh --branch "$(git branch --show-current)"`.
  It reads `gh stack`'s file from the git common dir (**`--git-common-dir`, not `--git-path`**).
  The metadata is per-repository, so the worktree's private dir finds nothing and would send a
  stacked repo down the plain path, silently causing the exact orphaning this check prevents.
  Its exit code picks the path. File presence alone picks nothing, because the file holds every
  stack the repo ever tracked, merged ones included.
  - **Exit 0, present.** The script prints one line per stack that lists this branch, members
    bottom to top. **Run no further command until you have read
    [references/gh-stack-cascade.md](references/gh-stack-cascade.md) in full**, then follow it
    from S1 (two lines mean two stacks, and S1 asks which). Apart from the two recovery commands
    named above, that file is the only source for `gh stack` invocations. Treat any others you
    recall from memory as wrong.
  - **Exit 3, absent** (file present, this branch not listed). Read the cascade file in full
    and enter S1 at its PR-graph probe, skipping `gh stack view --json`. A stack that
    `gh stack link` built on GitHub writes no local file, and the probe is what finds it. If the
    probe finds no chain, that file sends you to
    [references/plain-rebase.md](references/plain-rebase.md).
  - **Exit 4, absent** (no metadata file). **Read
    [references/plain-rebase.md](references/plain-rebase.md) in full and follow it.** If the user
    says `gh stack` manages the branch anyway, read the cascade file instead and let its S1
    settle membership.
  - **Exit 5, 2 or 127, unknown** (file unparsable, malformed call, or the script or `jq`
    missing). Say so and **ask** which path file to follow. Unknown never takes the plain path
    by default.

  In every case, **read the path file before running anything else.**

## Dirty tree

Run `git status --porcelain` before any rewrite. The path file says when, and the cascade path's
S1 replaces this guard with its own handling. If the output is non-empty, **ask** in a single
`AskUserQuestion` with these options:

- **stash & restore.** Run `git stash push --include-untracked`, record
  `git rev-parse refs/stash`, and run `git stash apply <sha>` only after the loss gate passes or
  its restore completes, since the gate's `reset --hard` would destroy edits restored earlier.
- **commit & push, then rebase.** Commit the working tree onto the current branch, then
  `git push` it, setting upstream if needed, so the pre-rebase state is on the remote before any
  history rewrite. Propose a message.
- **abort**.

## Backup refs

Set `<run-id>` to `date +%Y%m%d-%H%M%S`, never ISO-8601. `:` is illegal in ref names, so
`update-ref` would fail mid-loop with the backups half-written.

**First** check `git for-each-ref refs/rebase-skill/`. Anything left over means an earlier run
never completed, and its refs are the only pointer to that run's pre-rebase state, so **ask**
before proceeding rather than writing over it:

- **adopt**: reuse that run's id in the loss gate's commands for the branches it covers, and
  don't write a fresh snapshot for them;
- **discard**: delete them (command below) and snapshot afresh;
- **abort**.

Then snapshot each branch about to be rewritten, namespaced by run so a second run can never
overwrite the first one's snapshot:
`git update-ref refs/rebase-skill/<run-id>/<branch> <branch>`. The loss gate restores from this
ref. Where a branch name contains `/`, two refs in one run can collide as a directory and a file
(`feat` vs `feat/x`). Flatten the leaf by replacing each `/` with `--`. If the flattened name
matches one already written this run (`feat/x` vs a literal `feat--x`), stop and ask rather than
overwrite a snapshot. Use that same flattened name in **every** `refs/rebase-skill/…` command
downstream, not just in your report.

**Keep every ref until the push resolves**, meaning it landed and was verified, was denied, or
the user declined it. A ref deleted at the gate leaves the force-push with no backup. Then delete
the run's refs in one go:

```
git for-each-ref --format='delete %(refname)' refs/rebase-skill/<run-id>/ | git update-ref --stdin
```

## Resolving conflicts (preserve both sides)

When the rebase stops on a conflict, work each conflicted hunk until both sides' intent is
present in the file:

- Read **both** sides. In a rebase, `ours` is the base being replayed onto and `theirs` is your
  commit being replayed, the reverse of a merge. Read each side cleanly with `git show :2:path`
  (ours/base) and `git show :3:path` (theirs/your commit), or use the Read tool for the marked-up
  working file. Work out each side's _intent_ from the surrounding code and the commit message.
- **Auto-resolve only when you can preserve both sides' intent with high confidence**, for
  example non-overlapping concerns in the same hunk, or mechanical, format and import
  reconciliations. Then `git add` the file(s) and `git rebase --continue`.

**Escalate** a conflict when the two sides are **mutually exclusive** (keeping both is
impossible, so the user must choose), one side's **intent is unclear**, or the file is
**dangerous to auto-merge** (lockfiles, generated code, schema/migrations). On escalation:

- Leave the rebase paused at the conflicted commit. Earlier resolutions stay in place, and the
  backup ref guards against loss.
- **Batch all uncertain conflicts in the current commit into one `AskUserQuestion`.** For
  each, give a structured both-sides summary that says what each side changed and why, and why
  they collide. Add concrete candidate resolutions as options when you have them, with free-form
  as the fallback.
- Apply the chosen resolution, `git add`, continue, and repeat for later commits.
- In a cascade, every escalation also offers **abort the whole stack** (see the stacked file's
  recovery precedence). Without it, many branches mean many prompts with no way out.

## The loss gate (range-diff)

After the rebase completes, verify that no content was lost. The plain path runs this once. The
stacked path runs it once per moved branch, under that file's per-branch rules.

```
git range-diff --creation-factor=999 <MB>..refs/rebase-skill/<run-id>/<branch>  <newbase>..<branch> > <scratch>/range-diff-<branch>.txt
grep -E '^ *[0-9-]+: +[0-9a-f-]+ [=!<>] ' <scratch>/range-diff-<branch>.txt
```

The grep prints one pairing row per commit. Read the file's diff-of-diff only under `!`, `<` and
`>` rows. `=` rows are identical and need nothing more.

- **Use `--creation-factor=999`.** The default (60) often _fails to pair_ a commit whose diff
  context shifted during conflict resolution. It then prints a spurious drop (`<`) and add (`>`)
  instead of a matched `!`, which looks exactly like a lost commit. The high factor pairs
  aggressively and shows the real diff-of-diff.
- Every genuinely-new commit must map to a counterpart with no unexplained content change.
  Context-only shifts are fine. For example, a `!` whose only delta is the line a hunk
  _replaced_, with its added result identical, comes from the base moving and is not loss. A
  commit absent on the right is acceptable **only** if
  `git cherry <newbase> refs/rebase-skill/<run-id>/<branch>` marks it `-`, or it appears in
  neither column (already reachable from `<newbase>`, so never this branch's to replay).
  Dropping a patch-equal commit is the purpose of `--onto` and plain rebase.
- **Before concluding loss, rule out a pairing artifact.** A drop and add of the same commit
  subject, or an unpaired drop, is not loss by itself. Confirm by checking that the commit's net
  additions are present in the final tree/`HEAD`. Only a change that has vanished is loss.
- **On any _confirmed_ unexpected drop or content alteration**, do **not** keep the result.
  Restore with `git reset --hard refs/rebase-skill/<run-id>/<branch>` (or abort the rebase if
  it is still in progress), report **exactly** which commit/hunk didn't map, and **ask for help**.
  `reset --hard` is the restore for the checked-out branch. For any other branch it's
  `git update-ref refs/heads/<branch> refs/rebase-skill/<run-id>/<branch>`, since `update-ref`
  on the current branch would move the ref without touching index or worktree and leave the repo
  looking like one enormous uncommitted diff.
- **On pass**, the branch is verified. Keep the refs (they're deleted only once the push
  resolves) and go on to the push.
