---
name: rebase-branch
description: Rebase the current branch onto its freshly-fetched base, losing no work from either side; auto-skip already-integrated commits and escalate only genuinely complex conflicts. Use when asked to 'rebase this branch', 'rebase onto <base>', or 'update my branch'. Not for merging or squashing.
---

# rebase-branch

Rebase the **current** branch onto its base, with a hard guarantee that no work is lost
from either side. Resolves conflicts that preserve both intents; escalates the rest with a
summary. Stops at a **verified, locally-rebased branch**, then pushes (push is
permission-gated, so the prompt is the confirmation).

## Prime directive

**Never lose changes from either side.** Every step below is subordinate to this. When a
choice is between "more automatic" and "provably loses nothing," choose the latter. The
range-diff gate (Step 6) is the backstop that enforces it.

## Safety

- A hidden backup ref is written before any history rewrite; the range-diff gate restores
  from it on any detected loss. `ORIG_HEAD` and the reflog are the fallback net.
- Never use blanket `-X ours` / `-X theirs` or `git checkout --ours/--theirs` to make a
  conflict disappear — that silently drops one side.
- Pushing rewritten history is outward-facing. Only ever `--force-with-lease`, never
  `--force`. Don't push any branch other than the one rebased.
- Prefer read-only comparison — `diff <(git show A:path) <(git show B:path)` over temp-file
  dumps: no scratch, no plan-mode write-prompt. A `/tmp` temp file is the right call when the
  extraction must outlive a single command, or is large enough that re-extracting would be wasteful.

## Step 0 — Pre-flight (no rebase yet)

Base-independent guards. Run first:

- **Current branch**: `git branch --show-current`. Empty ⇒ detached HEAD ⇒ **abort
  gracefully** ("not on a branch; check one out first").
- **Rebase already in progress**: if `git rev-parse --git-path rebase-merge` /
  `rebase-apply` points at an existing dir ⇒ **don't start fresh**. Report it and offer
  `git rebase --continue` or `git rebase --abort`.
- **Dirty tree**: `git status --porcelain`. If non-empty ⇒ **ask** (single
  `AskUserQuestion`): **stash & restore** (autostash — restored after) · **commit & push,
  then rebase** (commit the working tree onto the current branch, then `git push` it —
  setting upstream if needed — so the pre-rebase state is safely on the remote before any
  history rewrite; propose a message) · **abort**.

## Step 1 — Base setup (fetch, determine, sync)

Everything here must happen before any rewrite — it's the last point to bail safely.

- **Fetch**: `git fetch origin` (fresh refs, so base detection and the sync use the real
  remote tip).
- **Determine the base**:
  - If the user passed a base as an argument, **use it** (skip detection).
  - Else **detect the branch's actual parent** (handles stacked branches):
    1. Configured upstream: `git rev-parse --abbrev-ref @{upstream}` — use it **only** if it
       isn't this branch's own remote-tracking ref (`origin/<current>`).
    2. Else infer the fork: for each likely base (repo default, `develop`, `main`, `master`,
       and any branch this one obviously forked from per reflog), compute
       `git merge-base <branch> origin/<candidate>` and how many commits are unique to the
       branch. The candidate the branch most plausibly forked from is the parent.
    3. Fall back to the **repo default**: `git symbolic-ref --quiet refs/remotes/origin/HEAD`
       → strip to leaf (e.g. `develop`); fall back to `develop` if unset.
  - **Confident** (one clear candidate) ⇒ use it silently. **Ambiguous** (multiple
    plausible candidates / low confidence) ⇒ show the candidates and **ask**.
- The rebase target is **`origin/<base>`** (always the freshly-fetched remote tip).
- **Sync the local `<base>` ref to match `origin/<base>`** (so the local base isn't stale).
  **Unpushed work is the one thing at risk here**: if `git rev-list origin/<base>..<base>`
  is non-empty, the local base has commits not on the remote — **warn** before overwriting
  (they remain recoverable via the reflog), then `git branch -f <base> origin/<base>`.
  (We're on the feature branch, so `<base>` isn't checked out.) The current branch's own
  commits are never at risk: the backup ref (Step 2) + the final `--force-with-lease` cover
  them, and uncommitted work was handled by Step 0.
- **Nothing to do**: if `git merge-base --is-ancestor origin/<base> <branch>`, the branch is
  already on top of the latest base ⇒ report "already up to date", stop.

## Step 2 — Backup ref

Before any rewrite, snapshot the tip into a hidden ref:
`git update-ref refs/rebase-skill/<branch> HEAD`. This is the source the range-diff gate
restores from. Auto-deleted once Step 6 passes.

## Step 3 — Rebase (safest --onto the agent can compute, no prompts)

No confirmation prompts. Pick the **safest cut point**:

- `MB = git merge-base <branch> origin/<base>` (the fork point).
- Classify each commit in `MB..<branch>` with `git cherry origin/<base> <branch>`: `-` =
  patch-equal to a commit already on the base, `+` = genuinely new.
- Let the **already-integrated prefix** be the leading contiguous run of `-` commits from
  `MB`. If it's non-empty, its last commit is the **cutpoint** and everything before it is
  _provably_ already on the base:
  `git rebase --onto origin/<base> <cutpoint> <branch>` — replays only the genuinely-new
  commits, skipping the integrated prefix (the main conflict-avoidance win).
- Otherwise: `git rebase origin/<base>` (default rebase still drops patch-equal commits).
- **Do not guess squash-merges.** When a commit's content looks merged but isn't
  patch-detectable, **don't** silently drop it — that can't be proven safe and you're not
  prompting. Replay it (plain rebase): more conflicts, but zero loss. The range-diff gate
  verifies the outcome regardless.

## Step 4 — Resolve conflicts (preserve both sides)

When the rebase stops on a conflict, for **each** conflicted hunk:

- Read **both** sides. In a rebase, `ours` = the **base** being replayed onto, `theirs` =
  **your** commit being replayed (reversed from a merge — don't get this backwards). Read each
  side cleanly with `git show :2:path` (ours/base) / `git show :3:path` (theirs/your commit), or
  the Read tool for the marked-up working file — not `cat`. Understand each side's _intent_ from
  the surrounding code and the commit message.
- **Auto-resolve only when both sides' intent can be preserved with high confidence** —
  e.g. non-overlapping concerns in the same hunk, mechanical/format/import reconciliations.
  Then `git add` the file(s) and `git rebase --continue`.

## Step 5 — Escalate the too-complex ones

**Escalate** a conflict when: the two sides are **mutually exclusive** (keeping both is
impossible, so the user must choose), one side's **intent is unclear**, or the file is
**dangerous to auto-merge** (lockfiles, generated code, schema/migrations).

On escalation:

- Leave the rebase **paused** at the conflicted commit (earlier resolutions are preserved;
  the backup ref guards against loss).
- **Batch all uncertain conflicts in the current commit into one `AskUserQuestion`.** For
  each, give a structured **both-sides summary**: what the **base** side changed and why,
  what **your** side changed and why, and **why they collide** — plus concrete candidate
  resolutions as options when you have them (free-form fallback).
- Apply the chosen resolution, `git add`, `git rebase --continue`, and proceed (repeat
  Steps 4–5 for later commits).

## Step 6 — Loss gate (range-diff)

After the rebase completes, verify content preservation:

```
git range-diff --creation-factor=999 <MB>..refs/rebase-skill/<branch>  origin/<base>..HEAD
```

- **Use `--creation-factor=999`.** The default (60) often _fails to pair_ a commit whose
  diff context shifted during conflict resolution (e.g. a one-line change now sitting on a
  moved base), printing it as a spurious **drop (`<`) + add (`>`)** instead of a matched
  `!`. That artifact looks exactly like a lost commit and would trip a false abort. The
  high factor makes range-diff pair aggressively and show the real diff-of-diff instead.
- Every genuinely-new commit must map to a counterpart with no unexplained content change
  (context-only shifts are fine — e.g. a `!` whose only delta is the line a hunk _replaced_,
  with its added result identical, is a base-movement artifact, not loss). Commits absent on
  the right are acceptable **only** if they're in the already-integrated set from Step 3.
- **Before concluding loss, rule out a pairing artifact.** A drop+add of the **same commit
  subject**, or an unpaired drop, is not loss by itself — confirm by checking the commit's
  net additions are actually present in the final tree/`HEAD`. Only a genuinely vanished
  change is loss.
- **Any _confirmed_ unexpected drop or content alteration** ⇒ do **not** keep the result:
  restore with `git reset --hard refs/rebase-skill/<branch>` (or `git rebase --abort` if
  still mid-rebase), report **exactly** which commit/hunk didn't map, and **ask for help**.
- On pass: delete the backup ref (`git update-ref -d refs/rebase-skill/<branch>`).

## Step 7 — Done

- Report a summary: commits replayed, commits skipped (already on base) and why, conflicts
  auto-resolved, conflicts you decided.
- **Push directly**: `git push --force-with-lease`. Push is permission-gated by the
  harness, so the prompt is the confirmation — if it's **denied**, that's fine: report the
  branch is rebased and verified locally and leave it for the user. Never `--force`.

## Gotchas

- **`ours`/`theirs` are reversed in a rebase.** `ours` is the base you replay onto, `theirs`
  is your own commit — the opposite of a merge. Resolving on the wrong assumption silently
  keeps the wrong side (Step 4).
- **Never make a conflict "disappear" with `-X ours`/`-X theirs` or `checkout --ours/--theirs`.**
  Each drops one side wholesale; a rebase that finishes clean this way has almost certainly
  lost work.
- **`git range-diff`'s default `--creation-factor` (60) fakes losses.** A commit whose
  context shifted shows as an unpaired drop+add that looks exactly like a vanished commit.
  Use `--creation-factor=999` and confirm the change is truly gone from `HEAD` before
  concluding anything was lost (Step 6).
- **A dropped commit isn't automatically loss.** Plain rebase and `--onto` intentionally drop
  patch-equal commits already on the base — that's the point. Only an unexplained, still-wanted
  change vanishing is loss.
- **Only ever `--force-with-lease`, never `--force`.** A plain force-push clobbers teammate
  commits pushed after your last fetch; the lease refuses when the remote moved under you.
- **Syncing the local base can eat unpushed commits.** `git branch -f <base> origin/<base>`
  overwrites a local base that has commits not on the remote — warn first; they survive only
  in the reflog.
