# Stacked branches (`gh-stack`)

You are here because pre-flight found stack metadata. Follow this file instead of
[plain-rebase.md](plain-rebase.md), and instead of the shared **Dirty tree** guard, which S1
replaces. SKILL.md's shared mechanics still apply: [Backup refs](../SKILL.md#backup-refs)
(S1 extends them), [Resolving conflicts](../SKILL.md#resolving-conflicts-preserve-both-sides)
(with this file's cascade specifics below), and
[the loss gate](../SKILL.md#the-loss-gate-range-diff), which S3 runs once per moved branch
under its verdict rules.

## Conflicts on this path

- **Both sides may be yours** — the "base" side is the freshly-rebased tip of your own branch
  one below it, so name the two **branches** rather than "base" and "your commit". Read which
  branch is being replayed from
  `git rev-parse --path-format=absolute --git-path rebase-merge/head-name`; mid-rebase HEAD is
  detached, so `git rev-parse --abbrev-ref HEAD` just returns `HEAD`.
- **The continue command is `gh stack rebase --continue`** — plain `git rebase --continue`
  finishes one branch while the cascade's own state goes stale, orphaning the rest.

A single-branch rebase **orphans** the branches above: they stay parented on commits it abandoned,
and the push publishes that. [`gh stack`](https://github.com/github/gh-stack) cascades correctly,
so the cascade is delegated and everything else stays here.

**Every failure on this path is silent.** Exit 0, no conflict, and a "pushed" report are each
compatible with lost commits or an unpublished branch — the cascade reports on its own success, not
on yours. Decide from state you can observe.

## The command surface

Six invocations are the whole surface. Read `--help` before reaching for anything outside it.

- `gh stack view --json` — read the stack (S1). It is the non-blocking form: the bare command
  opens a full-screen TUI that never returns. "Not part of a stack" and "belongs to multiple
  stacks" come back as **errors on stderr**, not as fields, and telling those two apart decides
  whether you cascade at all. It resolves **membership from local tracking only**, so it can
  never confirm GitHub-side truth — which is why S1's not-in-a-stack branch asks the PR graph
  before believing it.
- `gh stack rebase` — cascade (S2); `--continue` / `--abort` while paused.
- `gh stack push` — publish (S4).
- `gh stack checkout <stack-number>` — pick a stack when the branch is in more than one. It
  **moves the worktree**, so say so before running it; no other subcommand takes a stack
  selector, so there is no way to "just pass" the choice along. `gh stack checkout <pr-url>` is
  the other form: it resolves the stack **from GitHub** rather than from local tracking, which is
  what adopts a stack `gh stack link` created and never wrote locally. With **no argument** it
  opens an interactive picker and has no `--yes`, so it hangs unattended.
- `gh stack unstack --local` — leave the stack (explicit-base branch, below).
- `gh stack sync` — the cascade for a stack **adopted during this run** (S1's adoption branch,
  then S2's adopted route), and nowhere else.

`rebase` then `push` is what makes the push gateable: it lands in its own permission-gated step
where the prompt is the confirmation. `sync` collapses fetch, cascade, push and PR mutation into
one run, so on that route nothing is left to gate — its push precedes the loss gate, which is why
S3 becomes detect-and-revert there and S4 is skipped. What `sync` adds over `rebase` is the trunk
fast-forward, the merged-member skip and `--prune`; it is **not** the merged-prefix `--onto` cut,
which `rebase` already computes from its own recorded base SHAs (S3, below). Likewise `submit` is
always wrong: `gh stack` suggests it after a `--continue` run, it mutates PR state, and `push`
moves the branches without doing so.

**`sync` does more than restack**, which is why S1's preconditions gate it rather than a warning.
It links the stack's open PRs into a stack on GitHub and syncs PR state. On local/remote
divergence it *prompts* under a TTY — use the remote as the source of truth, delete the stack on
GitHub, or cancel — and only aborts non-interactively. That abort is not a no-op either: it
"aborts the sync without pushing branches or updating PRs" while still fast-forwarding the trunk
and possibly pulling down branches earlier in its sequence. A **rebase conflict**, by contrast,
restores every branch. Recovery from the divergence case runs through the `upstream-` refs S1
wrote, and nothing else.

Pass `--remote <rem>` to `rebase`, `push`, `sync` and `submit`; `init`, `add` and `view` take no
`--remote` at all — drop it there.

**Assume any `gh stack` command may want to prompt.** Multiple remotes, a branch in several
stacks, the argument-less `checkout` picker, `sync`'s divergence question and the first-run rerere
question all ask interactively under a TTY and fail or hang otherwise. Resolve each of them up
front (S1) instead of discovering them mid-cascade.

**`gh stack` does not work from a linked worktree.** Observed: from a worktree it reports the
current branch "is not part of a stack" even when the metadata lists it. If pre-flight found metadata
but you are in a linked worktree, say so and stop rather than acting on that answer. That stop
covers the PR-graph probe, the adoption and the `sync` too, and it comes **first**: from a worktree
the not-in-a-stack answer is a known false negative, so probing there spends an authenticated
round trip on an answer the run would have to discard.

**Nothing works while a cascade is paused** — `view --json`, `rebase`, and `push` all fail with
`not on any branch`, because the pause leaves HEAD detached. That is why pre-flight tests the state
file before anything else; there is no way to interrogate the stack from inside a pause.

## Step S1 — Pre-flight (nothing has moved yet)

**Resolve the remote first**, before anything reads a remote-tracking ref: `gh stack` auto-detects
one, and a multi-remote repo stops it (`multiple remotes configured; set remote.pushDefault or use
an interactive terminal`). Determine `<rem>` — a single remote, `gh-stack.remote`, or
`remote.pushDefault`; ask if none of those settles it — then use `<rem>/<branch>` in every
comparison below and `git fetch <rem>`. If `<rem>` isn't `origin`, pre-flight's `git fetch origin`
fetched the wrong remote: re-fetch.

Then read the stack once: `gh stack view --json`. Take from it the stack order (bottom-to-top),
which branch is current, which branches are merged or queued, which need rebasing, and each
branch's PR. Read the actual keys — the names are `gh-stack`'s, not this skill's.

Branch on its outcome before anything else:

- **Success** ⇒ the stack is **tracked**; proceed with the checks below.
- **Reports the branch isn't part of a stack** ⇒ **do not believe it yet.** That answer comes from
  local tracking, and `gh stack link` creates a stack on GitHub without writing any. So ask the PR
  graph, read-only, with **filtered** queries and no repo-wide scan — `gh pr list`
  fetches 30 items by default, and an unfiltered listing on a busy repo silently misses the very PRs
  that matter (these three rules are mirrored in the CI-watch capability's own stack reference,
  sentence for sentence, so a diff across the two files catches drift):
  - The trunk, which `gh stack view` would normally have supplied and did not:
    `gh repo view --json defaultBranchRef`, or the profile's Default branch row where the session
    carries one.
  - `gh pr view --json number,url,headRefName,baseRefName,isCrossRepository` for this branch. No
    PR for it, or `gh` failing, ⇒ close this file and follow [plain-rebase.md](plain-rebase.md).
  - Then **walk the chain in both directions until nothing new appears**, one branch at a time,
    with the same field set: `gh pr list --state open --base <b>` finds what is stacked on `<b>`,
    and `gh pr list --state open --head <its baseRefName>` finds what `<b>` is stacked on. **Skip
    a `--head` query whose value is the trunk**: a repo carrying a standing open
    trunk-to-release PR would otherwise make every ordinary PR look like a chain. Walking to the
    end matters — a two-query probe reads a four-member stack as two branches, and the adoption
    check below would then reject the stack it just adopted.
  - **Drop the cross-repo PRs.** `isCrossRepository` true means `headRefName` names a branch in
    a fork, which is not a local branch and nothing here may act on it. Name them and exclude them.
  - **A real chain is the test**: a query returning a PR whose head or base is one of these
    branches. A base that merely differs from the trunk is **not** — a PR onto a release branch is
    not a stack, and plenty of trunks aren't `main`. A chain of hand-cut branches is not
    adoptable either, which is why adoption has to prove itself below.
  - **Chain found** ⇒ its branches and PR numbers are the **member list** every "every branch"
    check below iterates, until adoption replaces it with `gh stack view`'s own. Carry on.
  - **No chain** ⇒ close this file and follow [plain-rebase.md](plain-rebase.md) instead, handling
    a dirty tree per [SKILL.md's Dirty tree](../SKILL.md#dirty-tree) on the way.
- **Reports the branch belongs to several stacks** ⇒ **ask which** (its stack number), then
  `gh stack checkout <stack-number>` to make that one active before S2 — it moves the worktree,
  so say so. Never guess: the answer decides which branches cascade. That number-form `checkout`
  picks among stacks **already tracked** here; the `<pr-url>` form above adopts one that is not.
- **Any other failure** ⇒ stop and report; nothing has moved yet. An auth failure, a rate limit
  and `timed out waiting for stack lock` all come back on stderr like the two outcomes above, and
  none of them means this branch is in no stack — reading one as the probe's cue would start an
  adoption on no evidence at all.

Then, in this order. The stash comes **first**, ahead of the refs it used to follow: a probed
stack's branches may not exist locally until adoption fetches them, adoption moves the worktree,
and a ref can be abandoned freely while an uncommitted edit cannot be recovered at all.

- **Dirty tree.** Pre-flight's autostash is a `git rebase` flag and never reaches a delegated
  rebase. Worse, uncommitted edits can ride along the per-branch `git checkout` the cascade — and
  `gh stack checkout` — does, and be destroyed while resolving a conflict; they exist in no stage,
  no ref and no reflog, so nothing below can recover them. Ask, per
  [SKILL.md's Dirty tree](../SKILL.md#dirty-tree):
  - **Stash** (skill-owned): `git stash push --include-untracked`, record `git rev-parse
    refs/stash`, and **re-assert `git status --porcelain` is empty** immediately before invoking
    the cascade. Restore with `git stash apply <sha>` — leaving the entry in place until the user
    confirms it applied — and only in this order: the cascade is finished or aborted, **then** the
    original branch is checked back out, **then** the stash is applied. Applying it while cascade
    state still exists puts a dirty tree in front of `--abort`'s per-branch `reset --hard`. Any
    abort still owes the user their stash: apply it once the abort completes, and say so.
  - **Commit & push, then rebase** (as the shared guard, pushing to `<rem>`) — worth preferring here:
    it's a
    fast-forward, so it neither trips a lease nor orphans anything.
  - **Abort.**
- **Adopt, on the probed route only.** Record the branch the user started on first, because the
  next command moves `HEAD` and the report has to put it back. Then `gh stack checkout <pr-url>`
  on a **still-open** member, saying that it moves the worktree; it is also what fetches the
  members that exist only on the remote, which is why it precedes every per-branch check below.
  Then `gh stack view --json` must succeed and list **every branch the probe found**. Extra
  members are expected and fine — the probe queried `--state open`, so a merged member of the
  same stack cannot appear in it — but a branch the probe found and the adopted view does not is
  proof this was never that stack: `gh stack unstack --local`, then close this file and follow
  [plain-rebase.md](plain-rebase.md). From here on, `gh stack view`'s member list replaces the
  probe's, and it is the one that carries each member's PR state.
- **State the plan of action**: the trunk you'll cascade onto (`<rem>/<trunk>`) and every branch
  that will move.
- **Already up to date**: if no branch needs rebasing, report it and **stop**.
- **Current branch merged or queued** ⇒ say so and stop, or offer to operate on the lowest
  non-merged branch. `gh stack push` skips merged and queued branches. This and the bullet above
  read `gh stack view`'s output, which on the probed route exists only after adoption — another
  reason adoption sits above them.
- **Remote divergence — the check that saves a teammate's work.** For every branch, first
  `git rev-parse --verify --quiet <rem>/<b>`; if it doesn't resolve the branch was never
  published, so record `n/a` and move on (a plain `rev-list` on a missing ref is fatal).
  Otherwise `git rev-list --count <b>..<rem>/<b>` — non-zero ⇒ **stop and ask**, offering:
  fast-forward that branch to `<rem>/<b>` (`git fetch <rem> <b>:<b>` for a branch that isn't
  checked out, which brings the count back to `0`) · drop it from this run
  (`--downstack` from below it) · abort. This is the one hazard `--force-with-lease` cannot
  catch: `gh stack rebase` fetches at its start, advancing `<rem>/<b>` to include the teammate's
  commit, so by push time the lease *passes* and their work is destroyed.
- **Unpushed work, on the adopted `sync` route only.** `--prune` deletes the local branches it
  classifies as merged, so for each merged member run `git rev-list --count <rem>/<b>..<b>`,
  treating a branch with no remote ref as non-zero. Non-zero ⇒ **stop and ask**, naming the
  branch: a local-only commit on a pruned branch goes with it, and this path holds no snapshot of
  a branch it never rebased.
- **Backup refs** — do SKILL.md's **Backup refs** for **every** branch in the stack, plus two
  more per branch that only this path needs:
  - `refs/rebase-skill/<run-id>/upstream-<branch>` = `<rem>/<branch>` **before** the delegated
    fetch (skip where there's no remote ref). The only thing that makes a wrongly-published
    stack reversible: once you have force-pushed, the remote's previous SHAs are gone from your
    side, and a later `--force-with-lease` measures its lease against what you pushed. On the
    adopted `sync` route it is also the only revert path, since that push precedes the gate.
  - `refs/rebase-skill/<run-id>/mb-<branch>` =
    `git update-ref refs/rebase-skill/<run-id>/mb-<branch> $(git merge-base <branch> <its parent in the stack>)`.
    S3's gate needs each branch's **pre-cascade** merge-base, and by then the parent has moved.
    Store it as a ref, not as a note to yourself: it has to survive many pauses, escalations and
    possibly a session break, and its loss silently changes what the gate compares.
- **Settle the rerere question** so the cascade can't block on the prompt:
  `git config --local rerere.enabled false`, recording any prior value so the report can offer to
  restore it. `false` is the right answer here — with rerere on, the cascade auto-continues past
  conflicts it has seen before, and those resolutions never reach the conflict step. (Verified: a
  pre-set value survives the cascade untouched and no prompt appears.)

**The cascade starts only once every branch has all four values recorded** — tip ref, `upstream-`
ref (or `n/a`), `mb-` ref, and a divergence count of `0` (or `n/a`) — **and the tree is clean**,
**and**, where the stack was adopted this run, the member-list check above has passed and the
unpushed-work check is clear. Echo that table, one row per branch, before invoking S2: a missing
cell is a branch you cannot restore. The branch the user started on is already recorded above;
carry it into the same table.

## Step S2 — Cascade

```
gh stack rebase --remote <rem>
```

Bare (no `--upstack`/`--downstack`): the whole stack, trunk→top. Report every branch that moved —
the blast radius is wider than the branch the user named.

**On a stack adopted this run**, use `gh stack sync --prune --remote <rem>` instead, for the
reasons in the command surface. Its push precedes the loss gate, so S3 is detect-and-revert and
S4 is skipped; say that before running it, along with the fact that a divergence abort leaves the
trunk fast-forwarded with no `--abort` to undo it. S1's dirty-tree, divergence and unpushed-work
checks are what make that route safe enough to take, and each of them refuses rather than warns.

**Decide from observable state**, not from exit numbers, which aren't reliably documented:

- Unmerged paths present (`git diff --name-only --diff-filter=U` non-empty), or the
  `gh-stack-rebase-state` file exists ⇒ **paused on a conflict** (observed exit 3) ⇒ **Resolving conflicts**,
  then back here. Expect several pauses across several branches. While paused, that state file is
  also the best record of the run: it carries `originalBranch` (where the user started),
  `originalRefs` (every branch's pre-cascade tip), `conflictBranch`, `remainingBranches` and
  `ontoOldBase`. It is **deleted on completion**, which is why S1 records its own refs.
- Exit 0 and no unmerged paths ⇒ the cascade finished **replaying**; loss is still unverified, so
  go to S3. Its own closing message suggests `gh stack submit` — ignore that and use S4's `push`.
- **A dirty tree fails it safely**: it stops at the first `git checkout` with `Your local changes
  … would be overwritten` (exit 1) and rewrites nothing, leaving no state files. That is a clean
  bail, not a half-done cascade — but S1's stash step is what keeps you out of it.
- **Any other failure** ⇒ stop, do not push, and report stderr verbatim rather than mapping it to
  a number. Worth recognising by text: `Stacked PRs are not enabled for this repository` ·
  `timed out waiting for stack lock` / `another gh-stack process may be running` (wait and retry;
  don't clear the lock) · a previously interrupted `gh stack modify` session (⇒ `gh stack modify
  --abort` first) · a schema-version complaint (the metadata is newer than the installed
  extension ⇒ upgrade it, don't proceed) · `contains a merge commit` (the stack refuses that
  branch) · `leftover conflict marker` (a file you thought resolved still has markers) ·
  `Rebase aborted but some branches could not be fully restored` — the one case where the backup
  refs are the only remaining route, so restore from them explicitly.
- A **GitHub API failure** is a silent input to the cut point (see S3), not a mere error: the
  cascade uses the API to learn which PRs merged, so a failure can make it cut in the wrong place.
  Check `gh auth status` and re-run rather than pressing on.

**With rerere on, not every conflict pauses** — the cascade auto-continues past a conflict whose
resolution is in the cache, so you never see it. S1 turns rerere off for this reason. If it
was on anyway, you cannot enumerate what it resolved after the fact: report plainly that
rerere-auto-resolved hunks were never reviewed.

**Recovery precedence.** While the `gh-stack-rebase-state` file exists, `gh stack rebase --abort`
is the correct exit — it restores **every** branch, not just the current one, and it is
**destructive to the working tree** (`checkout` + `reset --hard` per branch), so say so before
offering it. The backup refs are the fallback when no such state exists, or the abort failed.
A `sync` that aborted on divergence leaves no state file, so the `upstream-` refs are the only
route there.

## Step S3 — Loss gate, per branch

For every branch whose tip now differs from its backup ref
(`git rev-parse <b>` ≠ `git rev-parse refs/rebase-skill/<run-id>/<b>`), with `MB_b` the merge-base
recorded in S1 (`refs/rebase-skill/<run-id>/mb-<b>`) and `newbase_b` the branch one below it —
**`<rem>/<trunk>`** for the bottom one, never a bare local `trunk`, which this path never syncs
and whose extra commits would show up as spurious additions in the gate:

```
git range-diff --creation-factor=999 <MB_b>..refs/rebase-skill/<run-id>/<b>  <newbase_b>..<b>
```

Verdict rules are [the shared gate's](../SKILL.md#the-loss-gate-range-diff), with `<newbase_b>`
and `<MB_b>` substituted throughout.

The cascade switches to `--onto` when a lower PR has merged, with a cut point from **its own
recorded base SHAs**. A stale SHA — lower branch amended outside `gh stack`, or a squash-merge
edited at merge time — makes `--onto` discard everything at or below the cut point with **no
conflict and exit 0**. It is the same unproven cut the plain path refuses to make, made here by a tool
whose reasoning you can't inspect. Conflict pausing catches none of it; the range-diff does.

**The movement assertion**, which every cascade owes and a `sync` owes most. It applies to each
branch **whose base moved** — the trunk advanced under the bottom one, or its parent in the stack
was rebased — and to no others. A branch whose base never moved has nothing to replay, and a
merged or queued one the cascade skips outright; both legitimately keep their tips.

Work out that set bottom-up, from state you still have rather than from memory. The bottom
branch's base moved when `git merge-base --is-ancestor <rem>/<trunk>
refs/rebase-skill/<run-id>/<b>` **fails** — the trunk is not an ancestor of where that branch
stood before the cascade, so it advanced. Every branch above one whose base moved has a moved base
too, because its parent was rebased. Going bottom-up settles each branch before the one above it
needs the answer. For each branch in that set:

- its tip must differ from `refs/rebase-skill/<run-id>/<branch>`, and
- `git merge-base --is-ancestor <rem>/<trunk> <branch>` must succeed.

Without it, a `sync` that aborted and a `sync` that worked both pass a range-diff and a
remote-match check: the range-diff of an unmoved branch against itself is empty, and its remote
still matches. A failed assertion on the `sync` route means a half-synced repo with the trunk
already fast-forwarded, so report that state by name and restore from the `upstream-` refs.

**Any confirmed loss ⇒ block the push**, report the branch and commit, and offer
`gh stack rebase --abort` or a ref restore.

**On the adopted `sync` route the push has already happened**, so the gate is
**detect-and-revert** and S4 never runs. The run is done there when, for every branch whose base
moved: its gate passed and its movement assertion passed, or the failure was reported by name and
the `upstream-` refs were restored from — and the refs are deleted per
[SKILL.md's Backup refs](../SKILL.md#backup-refs), or kept with the exact restore commands in the
report. Say in that report that the state was published before it was checked.

## Step S4 — Push

Skipped entirely on the adopted `sync` route, which already pushed and whose completion clause is
in S3. Otherwise:

**First decide whether a push is needed**: for each branch compare `git rev-parse <b>` against
`git rev-parse --verify --quiet <rem>/<b>` (the `--verify --quiet` form exits 1 instead of fatally
on a branch that was never published — and one of those *does* need pushing, even though the
cascade left it untouched). If every branch already matches its remote, report and stop.

Otherwise:

```
gh stack push --remote <rem>
```

One `git push` with a per-branch `--force-with-lease`. Same push contract as the plain path's.

- It pushes every **active** branch, not only the ones that moved; merged and queued branches are
  skipped. Say which branches were in the push.
- **Updates are not atomic**: a branch may update even if another is rejected. So after pushing,
  `git fetch <rem>` and check `git rev-parse <b>` == `git rev-parse --verify --quiet <rem>/<b>` for
  every branch, exempting merged and queued ones. Any mismatch ⇒ **report it as a partial
  publish**: name which branches landed and which didn't, say plainly that the stack is
  inconsistent on GitHub (PR diffs and CI on the un-pushed branches now run against an abandoned
  base), and offer, in this order: re-run `gh stack push` after re-checking S1's divergence for the
  rejected branch — a lease failure usually means someone pushed to it, and the re-run leaves the
  branches that already landed untouched · re-cascade then re-push · restore from the `upstream-`
  refs.
- A branch that exists on the remote with no local tracking ref is sent with an *empty* lease
  ("must not exist") and may be **rejected** rather than force-updated. If it is, report it.
- "No active branches to push (all merged or queued)" succeeds while pushing nothing. Report that
  rather than a completed push.

**The run is done** when, for every branch in the push set: its gate passed, its movement
assertion passed **where its base moved**, it matches its remote (or the mismatch is reported as a
partial publish), and its refs are deleted per
[SKILL.md's Backup refs](../SKILL.md#backup-refs) — or the refs are kept and the exact restore
commands are in the report, per [the loss gate's](../SKILL.md#the-loss-gate-range-diff) restore
rules with `<b>` substituted.

## An explicit base argument

`gh stack rebase` targets the stack's own trunk and ignores any base you pass. If the base the
user named **is** the trunk, cascade. Otherwise **ask**:

- **Cascade the stack onto its trunk** — the named base is ignored; say so.
- **Take this branch out of the stack**: `gh stack unstack --local` **first**, then close this
  file and follow [plain-rebase.md](plain-rebase.md), handling a dirty tree per pre-flight's
  guard on the way. The unstack is load-bearing: leaving
  the metadata in place keeps a recorded base SHA that is now a lie, and that SHA is the `--onto`
  cut-point input above — so skipping it manufactures a silent-drop condition for the next run, by
  anyone. (Without `--local` it also unstacks the PRs on GitHub; queued and auto-merge PRs are
  left stacked. Add `gh pr edit --base` if the PR's base must move too.)
- **Abort.**

## Metadata present, `gh stack` not installed

The metadata file exists but `gh` reports `unknown command "stack"`. Warn that this repo has a
stack and no tooling to cascade it, then **ask**:

- **Install it**: `gh extension install github/gh-stack`, then start over.
- **Single-branch rebase anyway** — with the warning that the branches above are **orphaned** and
  each need their own rebase, bottom-up. Then close this file and follow
  [plain-rebase.md](plain-rebase.md), handling a dirty tree per
  [SKILL.md's Dirty tree](../SKILL.md#dirty-tree) on the way.
- **Abort.**

Branch names come from the metadata JSON. If it doesn't parse unambiguously, say only what the
metadata proves — that a stack exists, and that branches above this one are at risk — without
naming them.

## Report

- Stack order, and which branches moved.
- Whether the stack was adopted this run, through which PR URL, and any cross-repo PR the probe
  set aside.
- Conflicts: auto-resolved · escalated to the user · **rerere-auto-resolved (never reviewed)**.
- Loss gate result per branch, and the movement assertion for each branch whose base moved.
- Push result per branch, including any deliberately skipped (merged/queued) or rejected — or,
  on the adopted `sync` route, that the push happened before the gate and what the gate then found.
- `git checkout` back to the branch recorded in S1's table, and say where the cascade had left
  `HEAD`.
- Any stash still held, and the `git stash apply <sha>` command for it.
- Any repo config this run changed (`rerere.enabled`) and its prior value, with the offer to
  restore it.
- Whether the run disabled auto-merge on any PR — `gh stack` does that when it's incompatible
  with stacking, and the user needs to know it happened.
