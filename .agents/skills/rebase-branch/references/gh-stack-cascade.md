# Stacked branches (`gh-stack`)

Pre-flight sent you here on lookup exit 0 (start S1 from its top) or exit 3 (start at S1's
PR-graph probe). S1 replaces the shared **Dirty tree** guard. SKILL.md's other shared mechanics
still apply: [Backup refs](../SKILL.md#backup-refs)
(S1 extends them), [Resolving conflicts](../SKILL.md#resolving-conflicts-preserve-both-sides)
(with this file's cascade specifics below), and
[the loss gate](../SKILL.md#the-loss-gate-range-diff), which S3 runs once per moved branch
under its verdict rules.

## Conflicts on this path

- **Both sides may be yours.** The "base" side is the freshly-rebased tip of your own branch
  one below it, so name the two **branches** rather than "base" and "your commit". Read which
  branch is being replayed from
  `git rev-parse --path-format=absolute --git-path rebase-merge/head-name`. Mid-rebase HEAD is
  detached, so `git rev-parse --abbrev-ref HEAD` just returns `HEAD`.
- **The continue command is `gh stack rebase --continue`.** Plain `git rebase --continue`
  finishes one branch while the cascade's own state goes stale, which orphans the rest.

A single-branch rebase **orphans** the branches above. They stay parented on commits it
abandoned, and the push publishes that. [`gh stack`](https://github.com/github/gh-stack) cascades
correctly, so this file delegates the cascade to it and handles everything else itself.

**Every failure on this path is silent.** Exit 0, no conflict, and a "pushed" report are each
compatible with lost commits or an unpublished branch, because the cascade reports on its own
success, not on yours. Decide from state you can observe.

## The command surface

These six invocations are the full set. Read `--help` before reaching for anything outside it.

- `gh stack view --json` reads the stack (S1). It is the non-blocking form, since the bare
  command opens a full-screen TUI that never returns. "Not part of a stack" and "belongs to
  multiple stacks" come back as **errors on stderr**, not as fields, and telling those two apart
  decides whether you cascade at all. It resolves **membership from local tracking only**, so it
  can never confirm what GitHub records. That is why S1's not-in-a-stack branch asks the PR graph
  before believing it.
- `gh stack rebase` runs the cascade (S2). Use `--continue` / `--abort` while paused.
- `gh stack push` publishes (S4).
- `gh stack checkout <stack-number>` picks a stack when the branch is in more than one. It
  **moves the worktree**, so say so before running it. No other subcommand takes a stack
  selector, so you cannot pass the choice along any other way. `gh stack checkout <pr-url>` is
  the other form. It resolves the stack **from GitHub** rather than from local tracking, which is
  how you adopt a stack that `gh stack link` created and never wrote locally. With **no argument**
  it opens an interactive picker and has no `--yes`, so it hangs unattended.
- `gh stack unstack --local` leaves the stack (explicit-base branch, below).
- `gh stack sync` is the cascade for a stack **adopted during this run** (S1's adoption branch,
  then S2's adopted route), and nowhere else.

Running `rebase` then `push` is what lets you gate the push, because the push lands in its own
permission-gated step where the prompt is the confirmation. `sync` combines fetch, cascade, push
and PR mutation into one run, so on that route nothing is left to gate. Its push comes before the
loss gate, which is why S3 becomes detect-and-revert there and S4 is skipped. What `sync` adds over `rebase` is the trunk
fast-forward, the merged-member skip and `--prune`; it is **not** the merged-prefix `--onto` cut,
which `rebase` already computes from its own recorded base SHAs (S3, below). Likewise `submit` is
always wrong: `gh stack` suggests it after a `--continue` run, it mutates PR state, and `push`
moves the branches without doing so.

**`sync` does more than restack**, which is why S1's preconditions gate it rather than a warning.
It links the stack's open PRs into a stack on GitHub and syncs PR state. On local/remote
divergence it *prompts* under a TTY, offering to use the remote as the source of truth, delete
the stack on GitHub, or cancel, and it only aborts non-interactively. That abort is not a no-op
either. It "aborts the sync without pushing branches or updating PRs" while still fast-forwarding the trunk
and possibly pulling down branches earlier in its sequence. A **rebase conflict**, by contrast,
restores every branch. Recovery from the divergence case runs through the `upstream-` refs S1
wrote, and nothing else.

Two cases leave this file for [gh-stack-detours.md](gh-stack-detours.md): the user named a base
(read it before S2), or `gh` reports `unknown command "stack"` (read it at once, whatever step
you are on).

Pass `--remote <rem>` to `rebase`, `push`, `sync` and `submit`; `init`, `add` and `view` take no
`--remote` at all, so drop it there.

**Assume any `gh stack` command may want to prompt.** Multiple remotes, a branch in several
stacks, the argument-less `checkout` picker, `sync`'s divergence question and the first-run rerere
question all ask interactively under a TTY and fail or hang otherwise. Resolve each of them up
front (S1) instead of discovering them mid-cascade.

**`gh stack view` is blind from a linked worktree.** Test for one with
`git rev-parse --path-format=absolute --git-common-dir` differing from
`git rev-parse --path-format=absolute --git-dir`. Both commands take `--path-format=absolute`,
because a relative common dir (`../.git` from a subdirectory) against an absolute git dir reads
the main worktree as linked. Observed: from a linked worktree `view` reports the current branch
"is not part of a stack" even when the metadata lists it, because `gh stack` resolves its file
per worktree (`--git-dir`, never `--git-common-dir`).
Pre-flight's lookup reads the shared file, so membership is known here. When it exited 0 in a
linked worktree, skip the probe and take S1's adoption route with a still-open member the
lookup's line names: `gh stack checkout <pr-url>` fetches the stack from GitHub. That sequence
was observed from the main worktree (#30132, 2026-09-16) and is applied to a linked worktree by
inference; a failing checkout stops and names the main worktree. Never run `gh stack unstack
--local` on that route, because a blind `view` there is the expected failure, not proof of a
wrong stack.

**Nothing works while a cascade is paused.** `view --json`, `rebase`, and `push` all fail with
`not on any branch`, because the pause leaves HEAD detached. That is why pre-flight tests the
state file before anything else, since you cannot query the stack from inside a pause.

## Step S1 — Pre-flight (nothing has moved yet)

**Resolve the remote first**, before anything reads a remote-tracking ref. `gh stack` auto-detects
one, and a multi-remote repo stops it (`multiple remotes configured; set remote.pushDefault or use
an interactive terminal`). Determine `<rem>` from a single remote, `gh-stack.remote`, or
`remote.pushDefault`, and ask if none of those settles it. Then use `<rem>/<branch>` in every
comparison below and `git fetch <rem>`. If `<rem>` isn't `origin`, pre-flight's `git fetch origin`
fetched the wrong remote, so re-fetch.

Then read the stack once with `gh stack view --json`. Take from it the stack order
(bottom-to-top), which branch is current, which branches are merged or queued, which need
rebasing, and each branch's PR. Read the actual keys, because the names are `gh-stack`'s, not
this skill's. On the **exit-3 entry** skip this read. The lookup already said this branch is
untracked here, so start at the not-in-a-stack branch below.

Branch on its outcome before anything else:

- **Success.** The stack is **tracked**, so proceed with the checks below.
- **Reports the branch isn't part of a stack after an exit-0 lookup.** That contradicts the
  lookup. Inside a linked worktree it is the known false negative, so take the adoption route
  below with the still-open member the lookup's line names, and skip the probe. In the main
  worktree, stop and report both readings. Neither the probe nor an `init` runs on a listed
  branch.
- **Reports the branch isn't part of a stack, or the exit-3 entry.** **Do not believe it yet.**
  That answer comes from local tracking, and `gh stack link` creates a stack on GitHub without
  writing any. So ask the PR graph, read-only, with **filtered** queries and no repo-wide scan — `gh pr list` fetches 30
  items by default, and an unfiltered listing on a busy repo silently misses the very PRs that
  matter (these three rules are mirrored in the CI-watch capability's own stack reference,
  sentence for sentence, so a diff across the two files catches drift):
  - The trunk, which `gh stack view` would normally have supplied and did not, comes from
    `gh repo view --json defaultBranchRef`, or from the profile's Default branch row where the
    session carries one.
  - Run `gh pr view --json number,url,headRefName,baseRefName,isCrossRepository` for this
    branch. If there is no PR for it, close this file and follow
    [plain-rebase.md](plain-rebase.md). A `gh` failure (auth, rate limit, network) is no evidence
    either way, so stop and report.
  - Then **walk the chain in both directions until nothing new appears**, one branch at a time,
    with the same field set. `gh pr list --state open --base <b>` finds what is stacked on `<b>`,
    and `gh pr list --state open --head <its baseRefName>` finds what `<b>` is stacked on. **Skip
    a `--head` query whose value is the trunk**: a repo carrying a standing open
    trunk-to-release PR would otherwise make every ordinary PR look like a chain. Walk to the
    end, because a two-query probe reads a four-member stack as two branches, and the adoption
    check below would then reject the stack it just adopted.
  - **Drop the cross-repo PRs.** `isCrossRepository` true means `headRefName` names a branch in
    a fork, which is not a local branch and nothing here may act on it. Name them and exclude them.
  - **The test is a real chain**, meaning a query returns a PR whose head or base is one of these
    branches. A base that only differs from the trunk does **not** count. A PR onto a release
    branch is not a stack, and plenty of trunks aren't `main`. A chain of hand-cut branches is
    not adoptable either, which is why adoption has to prove itself below.
  - **Chain found.** Its branches and PR numbers are the **member list** that every "every
    branch" check below iterates, until adoption replaces it with `gh stack view`'s own. Carry on.
  - **No chain.** Close this file and follow [plain-rebase.md](plain-rebase.md) instead,
    handling a dirty tree per [SKILL.md's Dirty tree](../SKILL.md#dirty-tree) on the way.
- **Reports the branch belongs to several stacks**, which the lookup's two lines already
  announced. **Ask which** by its stack number. A stack printed `untracked` has none, so that
  pick stops with the report. Then run `gh stack checkout <stack-number>` to make that one
  active before S2, and say that it moves the worktree. Never guess, because the answer decides
  which branches cascade. That number-form `checkout` picks among stacks **already tracked**
  here, and the `<pr-url>` form above adopts one that is not.
- **Any other failure.** Stop and report, since nothing has moved yet. An auth failure, a rate
  limit and `timed out waiting for stack lock` all come back on stderr like the two outcomes
  above, and none of them means this branch is in no stack. Reading one as the probe's cue would
  start an adoption on no evidence at all.

Then run the following checks in this order. The stash comes **first**, ahead of the refs it used
to follow. A probed stack's branches may not exist locally until adoption fetches them, adoption
moves the worktree, and you can abandon a ref freely while an uncommitted edit cannot be
recovered at all.

- **Dirty tree.** Uncommitted edits can carry over through the per-branch `git checkout` that
  the cascade and `gh stack checkout` perform, and be destroyed while resolving a conflict. They
  exist in no stage, no ref and no reflog, so nothing below can recover them. Ask, per
  [SKILL.md's Dirty tree](../SKILL.md#dirty-tree):
  - **Stash** (skill-owned). Run `git stash push --include-untracked`, record `git rev-parse
    refs/stash`, and **re-assert `git status --porcelain` is empty** immediately before invoking
    the cascade. Restore with `git stash apply <sha>`, leaving the entry in place until the user
    confirms it applied, and only in this order: the cascade is finished or aborted, **then** the
    original branch is checked back out, **then** the stash is applied. Applying it while cascade
    state still exists puts a dirty tree in front of `--abort`'s per-branch `reset --hard`. Every
    exit owes the user their stash, including an early stop and a hand-off to
    [plain-rebase.md](plain-rebase.md). Check the original branch back out, apply it, and say so.
  - **Commit & push, then rebase** (as the shared guard, pushing to `<rem>`). Prefer this option
    here, because it's a fast-forward, so it neither trips a lease nor orphans anything.
  - **Abort.**
- **Adopt, on the probed route and on the linked-worktree route.** Record the branch the user
  started on first, because the next command moves `HEAD` and the report has to put it back.
  Check that the target branch is not checked out in another worktree (`git worktree list`).
  Git refuses that checkout before `gh stack` does anything, so stop and name that worktree.
  Then run `gh stack checkout <pr-url>` on a **still-open** member, saying that it moves the
  worktree. It also fetches the members that exist only on the remote, which is why it comes
  before every per-branch check below. Then `gh stack view --json` must succeed and list
  **every branch the probe found** (or, on the worktree route, every branch the lookup's line
  names). Extra members are expected and fine, because the probe queried `--state open`, so a
  merged member of the same stack cannot appear in it. In the **main worktree**, though, a branch
  that the probe found and the adopted view does not list proves this was never that stack. Run
  `gh stack unstack --local`, then close this file and follow [plain-rebase.md](plain-rebase.md).
  In a **linked worktree**, on either entry, a failing or short `view` is the expected blindness,
  not proof. Stop, name the main worktree, and run no `unstack --local` there. From here on,
  `gh stack view`'s member list replaces the probe's, and it is the one that carries each
  member's PR state.
- **State the plan of action**, naming the trunk you'll cascade onto (`<rem>/<trunk>`) and every
  branch that will move.
- **Already up to date.** If no branch needs rebasing, report it and **stop**.
- **Current branch merged or queued.** Say so and stop, or offer to operate on the lowest
  non-merged branch. `gh stack push` skips merged and queued branches. This bullet and the one
  above read `gh stack view`'s output, which on the probed route exists only after adoption.
  That is another reason adoption comes before them.
- **Remote divergence, the check that saves a teammate's work.** For every branch, first run
  `git rev-parse --verify --quiet <rem>/<b>`. If it doesn't resolve, the branch was never
  published, so record `n/a` and move on (a plain `rev-list` on a missing ref is fatal).
  Otherwise run `git rev-list --count <b>..<rem>/<b>`. If the count is non-zero, **stop and
  ask**, offering these options:
  - fast-forward that branch to `<rem>/<b>` (`git fetch <rem> <b>:<b>` for a branch that isn't
    checked out, which brings the count back to `0`);
  - drop it from this run (`--downstack` from below it);
  - abort.

  This is the one hazard `--force-with-lease` cannot catch. `gh stack rebase` fetches at its
  start, advancing `<rem>/<b>` to include the teammate's commit, so by push time the lease
  *passes* and their work is destroyed.
- **Unpushed work, on the adopted `sync` route only.** `--prune` deletes the local branches it
  classifies as merged, so for each merged member run `git rev-list --count <rem>/<b>..<b>`,
  treating a branch with no remote ref as non-zero. If the count is non-zero, **stop and ask**,
  naming the branch. A local-only commit on a pruned branch is deleted with it, and this path
  holds no snapshot of a branch it never rebased.
- **Backup refs.** Do SKILL.md's **Backup refs** for **every** branch in the stack, plus two
  more per branch that only this path needs:
  - `refs/rebase-skill/<run-id>/upstream-<branch>` = `<rem>/<branch>` **before** the delegated
    fetch (skip where there's no remote ref). Only this ref makes a wrongly-published stack
    reversible. Once you have force-pushed, the remote's previous SHAs are gone from your side,
    and a later `--force-with-lease` measures its lease against what you pushed. On the adopted
    `sync` route it is also the only revert path, since that push comes before the gate.
  - `refs/rebase-skill/<run-id>/mb-<branch>` =
    `git update-ref refs/rebase-skill/<run-id>/mb-<branch> $(git merge-base <branch> <its parent in the stack>)`.
    S3's gate needs each branch's **pre-cascade** merge-base, and by then the parent has moved.
    Store it as a ref, not as a note to yourself. It has to survive many pauses, escalations and
    possibly a session break, and losing it silently changes what the gate compares.
- **Settle the rerere question** so the cascade can't block on the prompt. Run
  `git config --local rerere.enabled false`, recording any prior value so the report can offer to
  restore it. `false` is the right answer here. With rerere on, the cascade auto-continues past
  conflicts it has seen before, and those resolutions never reach the conflict step. (Verified: a
  pre-set value survives the cascade untouched and no prompt appears.)

**The cascade starts only once every branch has all four values recorded** (tip ref, `upstream-`
ref or `n/a`, `mb-` ref, and a divergence count of `0` or `n/a`) **and the tree is clean**,
**and**, where the stack was adopted this run, the member-list check above has passed and the
unpushed-work check is clear. Echo that table, one row per branch, before invoking S2. A missing
cell is a branch you cannot restore. The branch the user started on is already recorded above,
so carry it into the same table.

## Step S2 — Cascade

```
gh stack rebase --remote <rem>
```

Run it bare (no `--upstack`/`--downstack`) to cascade the whole stack, from the trunk to the top.
Report every branch that moved, because more branches change than the one the user named.

**On a stack adopted this run**, use `gh stack sync --prune --remote <rem>` instead, for the
reasons in the command surface. Its push comes before the loss gate, so S3 is detect-and-revert
and S4 is skipped. Say that before running it, along with the fact that a divergence abort leaves
the trunk fast-forwarded with no `--abort` to undo it. S1's dirty-tree, divergence and
unpushed-work checks are what make that route safe enough to take, and each of them refuses
rather than warns.

**Decide from observable state**, not from exit numbers, which aren't reliably documented:

- If unmerged paths are present (`git diff --name-only --diff-filter=U` non-empty), or the
  `gh-stack-rebase-state` file exists, the cascade is **paused on a conflict** (observed exit 3).
  Go to **Resolving conflicts**, then come back here. Expect several pauses across several
  branches. While paused, that state file is also the best record of the run. It carries
  `originalBranch` (where the user started), `originalRefs` (every branch's pre-cascade tip),
  `conflictBranch`, `remainingBranches` and `ontoOldBase`. The cascade **deletes it on
  completion**, which is why S1 records its own refs.
- On exit 0 with no unmerged paths, the cascade finished **replaying**. Loss is still unverified,
  so go to S3. Its own closing message suggests `gh stack submit`. Ignore that and use S4's
  `push`.
- **A dirty tree fails it safely.** It stops at the first `git checkout` with `Your local changes
  … would be overwritten` (exit 1), rewrites nothing, and leaves no state files. That is a clean
  stop, not a half-done cascade, but S1's stash step is what keeps you from hitting it.
- On **any other failure**, stop, do not push, and report stderr verbatim rather than mapping it
  to a number. Recognise these by their text:
  - `Stacked PRs are not enabled for this repository`;
  - `timed out waiting for stack lock` / `another gh-stack process may be running` (wait and
    retry, and don't clear the lock);
  - a previously interrupted `gh stack modify` session (run `gh stack modify --abort` first);
  - a schema-version complaint (the metadata is newer than the installed extension, so upgrade
    it and don't proceed);
  - `contains a merge commit` (the stack refuses that branch);
  - `leftover conflict marker` (a file you thought resolved still has markers);
  - `Rebase aborted but some branches could not be fully restored`. This is the one case where
    the backup refs are the only remaining route, so restore from them explicitly.
- A **GitHub API failure** silently affects the cut point (see S3), so treat it as more than an
  error. The cascade uses the API to learn which PRs merged, so a failure can make it cut in the
  wrong place. Check `gh auth status` and re-run rather than continuing.

**With rerere on, not every conflict pauses.** The cascade auto-continues past a conflict whose
resolution is in the cache, so you never see it. S1 turns rerere off for this reason. If it was on
anyway, you cannot list what it resolved after the fact, so report plainly that
rerere-auto-resolved hunks were never reviewed.

**Recovery precedence.** While the `gh-stack-rebase-state` file exists, `gh stack rebase --abort`
is the correct exit. It restores **every** branch, not just the current one, and it is
**destructive to the working tree** (`checkout` + `reset --hard` per branch), so say so before
offering it. The backup refs are the fallback when no such state exists, or when the abort
failed. A `sync` that aborted on divergence leaves no state file, so the `upstream-` refs are the
only route there.

## Step S3 — Loss gate, per branch

Run the gate for every branch whose tip now differs from its backup ref
(`git rev-parse <b>` ≠ `git rev-parse refs/rebase-skill/<run-id>/<b>`). `MB_b` is the merge-base
recorded in S1 (`refs/rebase-skill/<run-id>/mb-<b>`), and `newbase_b` is the branch one below it.
For the bottom branch, `newbase_b` is **`<rem>/<trunk>`**, never a bare local `trunk`. This path
never syncs the local trunk, and its extra commits would show up as spurious additions in the
gate.

```
git range-diff --creation-factor=999 <MB_b>..refs/rebase-skill/<run-id>/<b>  <newbase_b>..<b> > <scratch>/range-diff-<b>.txt
```

Save and grep it, and apply the verdict rules, as [the shared gate](../SKILL.md#the-loss-gate-range-diff)
does, with `<newbase_b>` and `<MB_b>` substituted throughout.

The cascade switches to `--onto` when a lower PR has merged, with a cut point from **its own
recorded base SHAs**. A stale SHA makes `--onto` discard everything at or below the cut point
with **no conflict and exit 0**. A SHA goes stale when someone amends a lower branch outside
`gh stack`, or edits a squash-merge at merge time. It is the same unproven cut the plain path
refuses to make, made here by a tool whose reasoning you can't inspect. Conflict pausing catches
none of it, and the range-diff does.

**The movement assertion** is owed by every cascade, and most of all by a `sync`. It applies to
each branch **whose base moved**, meaning the trunk advanced under the bottom one or its parent
in the stack was rebased, and to no others. A branch whose base never moved has nothing to
replay, and the cascade skips a merged or queued one outright. Both correctly keep their tips.

Work out that set bottom-up, from state you still have rather than from memory. The bottom
branch's base moved when `git merge-base --is-ancestor <rem>/<trunk>
refs/rebase-skill/<run-id>/<b>` **fails**. In that case the trunk is not an ancestor of where
that branch stood before the cascade, so it advanced. Every branch above one whose base moved has
a moved base too, because its parent was rebased. Going bottom-up settles each branch before the
one above it needs the answer. For each branch in that set:

- its tip must differ from `refs/rebase-skill/<run-id>/<branch>`, and
- `git merge-base --is-ancestor <rem>/<trunk> <branch>` must succeed.

Without this assertion, a `sync` that aborted and a `sync` that worked both pass a range-diff and
a remote-match check. The range-diff of an unmoved branch against itself is empty, and its remote
still matches. A failed assertion on the `sync` route means a half-synced repo with the trunk
already fast-forwarded, so report that state by name and restore from the `upstream-` refs.

**On any confirmed loss, block the push**, report the branch and commit, and offer
`gh stack rebase --abort` or a ref restore.

**On the adopted `sync` route the push has already happened**, so the gate is
**detect-and-revert** and S4 never runs. The run is done there once two conditions hold. First,
for every branch whose base moved, its gate and its movement assertion passed, or the failure was
reported by name and the branch was restored from the `upstream-` refs. Second, the refs are
deleted per [SKILL.md's Backup refs](../SKILL.md#backup-refs), or kept with the exact restore
commands in the report. Say in that report that the state was published before it was checked.

## Step S4 — Push

Skip this step entirely on the adopted `sync` route, which already pushed and whose completion
clause is in S3. Otherwise:

**First decide whether a push is needed.** For each branch, compare `git rev-parse <b>` against
`git rev-parse --verify --quiet <rem>/<b>`. The `--verify --quiet` form exits 1 instead of
failing fatally on a branch that was never published, and such a branch *does* need pushing,
even though the cascade left it untouched. If every branch already matches its remote, report and
stop.

Otherwise:

```
gh stack push --remote <rem>
```

This runs one `git push` with a per-branch `--force-with-lease`, under the same push contract as
the plain path's.

- It pushes every **active** branch, not only the ones that moved, and skips merged and queued
  branches. Say which branches were in the push.
- **Updates are not atomic.** A branch may update even if another is rejected. So after pushing,
  run `git fetch <rem>` and check `git rev-parse <b>` == `git rev-parse --verify --quiet <rem>/<b>`
  for every branch, exempting merged and queued ones. On any mismatch, **report it as a partial
  publish**. Name which branches landed and which didn't, and say plainly that the stack is
  inconsistent on GitHub (PR diffs and CI on the un-pushed branches now run against an abandoned
  base). Then offer these options, in this order:
  1. Re-run `gh stack push` after re-checking S1's divergence for the rejected branch. A lease
     failure usually means someone pushed to it, and the re-run leaves the branches that already
     landed untouched.
  2. Re-cascade, then re-push.
  3. Restore from the `upstream-` refs.
- A branch that exists on the remote with no local tracking ref is sent with an *empty* lease
  ("must not exist"), and the remote may **reject** it rather than force-update it. If it does,
  report it.
- "No active branches to push (all merged or queued)" succeeds while pushing nothing. Report that
  rather than a completed push.

**The run is done** once two conditions hold. First, every branch in the push set passed its gate,
passed its movement assertion **where its base moved**, and matches its remote (or the mismatch
is reported as a partial publish). Second, its refs are deleted per
[SKILL.md's Backup refs](../SKILL.md#backup-refs), or the refs are kept and the exact restore
commands are in the report, per [the loss gate's](../SKILL.md#the-loss-gate-range-diff) restore
rules with `<b>` substituted.

## Report

- The stack order, and which branches moved.
- Whether the stack was adopted this run, through which PR URL, and any cross-repo PR the probe
  set aside.
- Conflicts, split into auto-resolved, escalated to the user, and
  **rerere-auto-resolved (never reviewed)**.
- The loss gate result per branch, and the movement assertion for each branch whose base moved.
- The push result per branch, including any deliberately skipped (merged/queued) or rejected. On
  the adopted `sync` route, say instead that the push happened before the gate and what the gate
  then found.
- Run `git checkout` back to the branch recorded in S1's table, and say where the cascade had
  left `HEAD`.
- Any stash still held, and the `git stash apply <sha>` command for it.
- Any repo config this run changed (`rerere.enabled`) and its prior value, with the offer to
  restore it.
- Whether the run disabled auto-merge on any PR. `gh stack` does that when auto-merge is
  incompatible with stacking, and the user needs to know it happened.
