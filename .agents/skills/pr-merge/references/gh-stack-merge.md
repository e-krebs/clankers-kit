# Stacked PRs (`gh stack`)

You are here because SKILL.md's step 2 found an open PR based on this one, because its dependant
query came back empty on a PR whose base is neither the trunk nor an ordinary branch but an open
PR of its own — in which case you enter at M1 with an empty restack set — or because
`gh pr merge` came back with `GraphQL: This pull request is part of a stack and must be merged
using the asynchronous merge REST API`. This file replaces SKILL.md's steps 3 and 4 and adds the
restack. SKILL.md's step 1 and its blocker rules still apply.

Two things make this path different from an ordinary merge. `gh stack merge` lands **every member
below** the PR you name, in one all-or-nothing operation, so the gate has to cover the whole set.
And GitHub retargets the PRs **above** it seconds after it lands, so whatever was not captured
before the merge is gone.

## M1 — Finish the capture (nothing has merged yet)

SKILL.md's step 2 already holds the primary PR's JSON and one page of dependants. Complete it
here, all read-only.

- **Tested first**, because both change what may run. Neither lets a `gh stack` command run; the
  first stops the whole run, the second only rules out the stacked route:
  - `test -e "$(git rev-parse --git-common-dir)/gh-stack-rebase-state"` ⇒ a cascade from an
    earlier run is paused, and every `gh stack` read fails with `not on any branch` because the
    pause leaves HEAD detached. Report it and stop: the user resolves that cascade first, and a
    merge that retargets PRs on top of a half-rebased stack is not one to guess at.
  - A linked worktree (`git rev-parse --git-common-dir` differs from `--git-dir`) ⇒ `gh stack`
    reports the current branch "is not part of a stack" even when the metadata lists it, so every
    answer it gives here is unreliable. Record membership **unreadable** and run no `gh stack`
    command: M2 and M3 still run, the ordinary `gh pr merge` still lands the PR, and M4 then
    takes its report-only exit rather than a restack. If `gh pr merge` is refused as well, stop
    there and say the merge needs the main worktree.
- **Trunk**: the profile's Default branch row, else `gh repo view --json defaultBranchRef`.
- **The remote, `<rem>`**: a single remote, `gh-stack.remote`, or `remote.pushDefault`, asking if
  none of those settles it. It is resolved here because the preconditions below compare against
  `<rem>/<branch>`, and because `gh stack`'s own auto-detection stops on a multi-remote repo.
- **Finish the upward walk.** Repeat SKILL.md's query for each newly found `headRefName` until
  nothing new appears. Dependants nest, and one level is not enough: #30132 was a grandchild of
  the PR being merged, and a single query would have missed it.
- **Set aside the cross-repo dependants.** A PR with `isCrossRepository` true has a
  `headRefName` that names a branch in the fork, not here. It cannot be restacked from this
  repository and no local command may take that name as a ref. Name those PRs in the report and
  drop them from the restack set.
- **Walk the merge set downward**:
  `gh pr view <baseRefName> --json number,title,state,isDraft,reviewDecision,mergeable,mergeStateStatus,statusCheckRollup,headRefName,baseRefName,body,url`,
  repeated from each `baseRefName` until it reaches the trunk. Same field set as the primary PR,
  because M2 judges every member from identical data. A base that names no PR ends the walk: the
  members found so far are the whole merge set, and its lowest one sits on an ordinary branch
  rather than on the trunk. Say so in M2's offer, because `gh stack merge` still lands that set
  into that branch. Distinguish it from a failing `gh` — auth, a rate limit — which records the
  merge set as incomplete and takes M2's stop rather than merging a set it could not read.
- **Membership, not file presence.** `gh stack view --json` must list the primary PR's
  `headRefName` among the members. The metadata file merely existing proves nothing: in the
  incident it tracked a different, fully merged stack. When the current branch is not the PR's
  branch, `gh stack view` answers about the wrong branch, so record membership **unknown**.
  Unknown and unreadable both route as absent in M3.

- **The restack preconditions**, read-only, and here rather than at M4. The `gh stack sync` route
  at M4 refuses on any of three states, and every one of them is knowable now — before anything
  merges. Checking them here is what stops the run landing a merge and then discovering it cannot
  restack, which would leave the user consenting to both and getting one.
  - The first applies always: `git status --porcelain` non-empty.
  - The other two need a member list, so they run only where **membership is present** — the one
    case where the `sync` route is reachable without adopting, and the one case where
    `gh stack view --json` supplies that list. Membership absent, unknown or unreadable takes the
    rebase or report-only exits at M4, where these two are irrelevant; a refusal at M3 that adopts
    the stack re-checks them there, once adoption has supplied the list.
  - Any stack member whose remote holds commits the local branch lacks:
    `git rev-parse --verify --quiet <rem>/<b>`, then `git rev-list --count <b>..<rem>/<b>`
    non-zero.
  - Any branch this run will make prunable with commits its remote lacks:
    `git rev-list --count <rem>/<b>..<b>` non-zero, a branch with no remote ref counting as
    non-zero. **That set includes the merge set**, not only the members already merged. The set is
    what M3's `git branch -D` and M4's `--prune` are about to delete, and here is the only point
    where its remote refs still exist to compare against — re-checking at M4 would false-refuse
    every run.
  Record which of the three hold. M2's offer says so, and M4 explains each one where it refuses.

Done when the dependant chain is walked to its end, the cross-repo PRs are set aside, the merge
set is walked down to the trunk, membership reads present, absent, unknown or unreadable, and the
dirty-tree precondition is recorded, plus the other two where membership is present — or a stop
condition has fired.

## M2 — Gate

SKILL.md's blocker rules, applied to **every member of the merge set** and not only the PR named,
whenever `gh stack merge` will be the route. That breadth is the point: `gh stack merge`'s own
pre-flight checks nothing but "open and not a draft", and it lands the set together, so one
member's missing approval or red check is the whole set's blocker. Where the route stays
`gh pr merge` — no membership and no refusal — judge only the PR being merged, because that
command touches nothing else.

Blocked → one line naming the blocker **and which PR it belongs to**, then stop.

Clear → one declinable offer:

- **The merge**, with the method PR shape prescribes. Name every captured dependant: the merge
  moves their base. On the `gh stack merge` route the branch deletion offered is the **local** one
  (M3), because that command has no `--delete-branch` and the remote branch's fate is the
  repository's `delete_branch_on_merge` setting; otherwise it is the local-and-remote deletion
  `gh pr merge -d` does. Say which of M1's three preconditions hold, because each one that does
  means the restack at M4 will refuse — the user is consenting to a merge and a restack, and this
  is where they learn whether the second half can happen.
- **The tickets**, when Ticket system is not `none`: one question listing **every distinct**
  ticket across the merge set and its move to the Done state, declinable as a unit or per ticket.
  A key two members share is one row, transitioned once. A single
  ticket question for a set of four would transition three tickets nobody consented to. Run
  SKILL.md step 3's sibling search per member, each member's own `url` supplying `<owner/repo>`,
  and its no-ID and search-failure exits applying per member. **The drop set is the route M3 will
  take**: the whole merge set under `gh stack merge`, the named PR alone where the route stays
  `gh pr merge`, which lands nothing else. Omit from the question every member whose ticket still
  carries an open PR, and name those PRs. M3's refusal re-runs M2, so the search re-runs there
  with the wider drop set.

Done when each question is accepted or declined, or the blocker line is out.

## M3 — Merge

- **Membership absent, unknown or unreadable, and no refusal yet** ⇒ `gh pr merge <n> --squash
  --delete-branch` (or `--merge --delete-branch`). `-d` removes the local branch too, so M4 has
  no local delete to do. **A refusal here re-runs M2 first**, over the merge set M1 walked, and
  re-offers both questions before the stacked route runs. M2 judged only this PR on the way in,
  because `gh pr merge` touches only this PR — and the route the refusal switches to lands every
  member below it. Merging that set on the strength of one PR's verdict is the exact breadth this
  file exists to enforce, and `gh stack merge` will not catch it.
  **Except where membership reads unreadable**: the stacked route needs `gh stack checkout` and
  `gh stack merge`, and M1 forbade both from a linked worktree. A refusal there stops the run —
  say the merge needs the main worktree, and do not re-gate for a route that cannot run.
- **Membership present, or a refusal** ⇒ the stacked route.
  - Membership absent or unknown ⇒ **adopt first**: `gh stack checkout <pr-url>` on a still-open
    member. It **moves the worktree**, so say so before running it. It failing means the stack is
    not a `gh stack` one after all: stop, and report the PRs that need a hand-rebase rather than
    merging blind.
  - Then `gh stack merge <n> --squash --yes`. Both flags are mandatory: interactively the command
    opens a wizard, and non-interactively it reuses whichever method was used last, so `--squash`
    is what honours the profile and `--yes` is what stops a hang.
  - **The local delete**, on this route only: `git checkout <trunk>`, then `git branch -D
    <branch>` for each merged member. `-D` and not `-d`, which refuses a squash-merged branch
    because its commits are not ancestors of the trunk. Run it before M4's `--prune`, and report
    a failure rather than blocking on it.
- **Either route**: re-read **every** PR in the merge set, one `gh pr view <number> --json
  state,mergeCommit` per member, not only the PR named. Transition each ticket whose move M2
  approved and whose PR now reads `MERGED`; a queued or failed merge moves nothing.

Done when the report names every merge SHA, the local delete's result where that route ran, and
each approved ticket's new state or why it did not move — or says the merge is queued and the
tickets untouched.

## M4 — Restack

The dependants captured in M1 are now parented on commits the merge abandoned, and GitHub has
already retargeted their PRs, so nothing left in the graph records what they used to sit on.

- **Nothing above** — the restack set is empty once the cross-repo PRs are set aside ⇒ say so in
  one clause and the step is done.
- **Tracked now** — membership was present in M1, or M3 adopted the stack ⇒ the `gh stack sync`
  route below.
- **Not tracked** — membership absent, unknown or unreadable, with a non-empty restack set ⇒
  offer the rebase. On a yes, run the rebase skill, the installed skill that rebases a branch or
  restacks a stack, which asks GitHub for the stack and cascades
  it: tell the user to start from the trunk, since the merged branch is gone locally and `HEAD`
  has moved, and that adoption there takes a **still-open dependant's** PR URL, never the merged
  parent's, because the picker omits fully merged stacks. On a no, or where that skill is not
  installed, take the report-only exit.
- **Report-only exit** — a stop condition fired, the offer was declined, a precondition refused,
  the sync paused or aborted, or the movement assertion failed ⇒ report each orphaned PR by number
  with the branch it needs to sit on, working from the bottom of the chain upwards, and say which
  of those it was. This report is the only record the user gets, and it is where every route that
  cannot finish the restack ends up.

### The `gh stack sync` route

`gh stack sync --prune --remote <rem>` is what restacks a stack this skill can reach, with `<rem>`
as M1 resolved it.

This command pushes before anything verifies the result, and this skill holds no backup refs, no
`upstream-` refs and no loss gate to undo it with. So three preconditions are **checked and
refused**, not merely announced. M1 recorded all three before the merge and M2's offer stated
them; re-read the first one here, immediately before the command, because the tree can have
changed since. Any of them holding ⇒ refuse, name it, and take the report-only exit above:

1. **A dirty tree.** `git status --porcelain` non-empty ⇒ refuse. `sync` checks each branch out in
   turn, and an uncommitted edit that rides one of those checkouts exists in no stage, no ref and
   no reflog. It is the one loss nothing here can recover, which is why it is a refusal and not a
   warning.
2. **A teammate's commit on a member.** For each branch in the stack,
   `git rev-parse --verify --quiet <rem>/<b>`, and where it resolves,
   `git rev-list --count <b>..<rem>/<b>`. Non-zero ⇒ refuse, naming the branch. `sync` fetches at
   its start, which advances `<rem>/<b>` to include that commit, so by push time the lease
   *passes* and the work is destroyed. `--force-with-lease` cannot catch this one, and nothing
   here can put it back.
3. **Unpushed work on a branch `--prune` may delete.** For each merged member,
   `git rev-list --count <rem>/<b>..<b>`, treating a branch with no remote ref as non-zero.
   Non-zero ⇒ refuse, naming the branch. `--prune` deletes the local branches it classifies as
   merged, and a local-only commit on one of them goes with it.

The push preceding any check is the one hazard that cannot become a precondition, because it is
what the command does rather than a state to test. Say so plainly in the offer at M2 and again
before running: if the restack is wrong, it is already published.

Then, in order:

- Record each restack-set branch's tip: `git update-ref refs/pr-merge/<run-id>/<branch>
  <branch>`, `<run-id>` = `date +%Y%m%d-%H%M%S`. Refs rather than remembered SHAs, because a
  `sync` that pauses on a conflict can outlive the session and these are the only record of where
  the branches were.
- Run `gh stack sync --prune --remote <rem>`.
- **Assert every recorded tip moved**: `git rev-parse <b>` ≠ `git rev-parse
  refs/pr-merge/<run-id>/<b>`, and `git merge-base --is-ancestor <rem>/<trunk> <b>` succeeds.
  Every one of them had its parent merged, so every one of them owes a move. Without this, a
  `sync` that aborted and a `sync` that worked look identical: the range-diff of an unmoved
  branch against itself is empty, and its remote still matches. **Any tip that did not move ⇒**
  the restack did not happen for that branch: keep the refs, take the report-only exit, and name
  the branch there.
- **A pause** — unmerged paths, or the `gh-stack-rebase-state` file now exists ⇒ take the
  report-only exit. This skill resolves no conflicts. Name the state file and hand the recovery
  over: the rebase skill's pre-flight detects that state and offers the cascade's own
  `--continue` and `--abort`.
- **A divergence abort** — `sync` reports it aborted without pushing ⇒ it still fast-forwarded
  the trunk and may have pulled down branches earlier in its sequence. There is no `--abort` and
  no revert path here, so take the report-only exit, name the half-synced state, and leave
  recovery to the user.

Done when one of three things is true. Every recorded tip moved and the run's refs are deleted
(`git for-each-ref --format='delete %(refname)' refs/pr-merge/<run-id>/ | git update-ref
--stdin`). Or the restack set was empty, or the rebase was offered and its answer acted on. Or the
report-only exit is out, naming every orphaned PR and which of its triggers fired — and there the
refs are **kept**, because after a pause, an abort or a failed assertion they are the only record
of where the branches were.

## Gotchas

- **The async-merge refusal was observed once**, on the bottom open member of a stack. Whether
  every stacked PR refuses is untested, and the text appears in no `gh` help output. It is a
  route switch, not an error — and it can arrive on a PR with nothing above it, which is why
  SKILL.md's step 4 points back here.
- **A bare number is unambiguous.** Stack numbers and PR numbers never overlap, and both
  `checkout` and `merge` resolve a bare number as a stack number first, then as a PR number.
  `checkout` also takes a `<pr-url>`, which is the form to use there because it is unambiguous by
  construction. `merge` takes `<stack-number> | <pr-number>` only and **no URL form**, so that
  habit does not generalise.
- **`gh stack checkout` with no argument** opens an interactive picker and has no `--yes`, so it
  hangs unattended. Always pass the PR URL.
- **`gh stack sync` does more than restack.** It links the stack's open PRs into a stack on
  GitHub and syncs PR state, which is PR mutation immediately after a merge. On local/remote
  divergence it *prompts* under a TTY — use the remote as the source of truth, delete the stack on
  GitHub, or cancel — and only aborts non-interactively. Precondition 2 above is what keeps the
  run out of both.
- **`gh stack view --json` can lie by omission.** It fails with `not on any branch` inside a
  paused cascade, and from a linked worktree it reports the current branch "is not part of a
  stack" even when the metadata lists it. Either answer reads as "not tracked", which is why M1
  tests both conditions before believing anything it says.
