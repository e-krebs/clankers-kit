# Plain rebase (no tracked stack)

You are here because `gh-stack` isn't tracking a stack in this repo. That does **not** mean this
branch stands alone — someone may have cut branches off it by hand, and those are as real a stack
as a tracked one. Nothing here can cascade them, but Step 3 finds them and says what they'll need.

Three steps, using the shared mechanics in SKILL.md —
[Dirty tree](../SKILL.md#dirty-tree), [Backup refs](../SKILL.md#backup-refs),
[Resolving conflicts](../SKILL.md#resolving-conflicts-preserve-both-sides), and
[the loss gate](../SKILL.md#the-loss-gate-range-diff).

## Step 1 — Base setup (determine, sync)

Everything here happens before any rewrite — it's the last point to bail safely. Pre-flight has
already fetched. Handle uncommitted work first, per
[SKILL.md's Dirty tree](../SKILL.md#dirty-tree).

- **Determine the base**:
  - If the user passed a base as an argument, **use it** (skip detection).
  - Else **detect the branch's actual parent** (handles a branch cut from another branch):
    1. Configured upstream: `git rev-parse --abbrev-ref @{upstream}` — use it **only** if it
       isn't this branch's own remote-tracking ref (`origin/<current>`).
    2. Else infer the fork: for each likely base (repo default, `develop`, `main`, `master`,
       and any branch this one obviously forked from per reflog), compute
       `git merge-base <branch> origin/<candidate>` and how many commits are unique to the
       branch. The candidate the branch most plausibly forked from is the parent.
    3. Fall back to the **repo default**: `git symbolic-ref --quiet refs/remotes/origin/HEAD`
       → strip to leaf (e.g. `develop`); fall back to `develop` if unset.
  - **Confident** (one clear candidate) ⇒ use it silently. **Ambiguous** (multiple plausible
    candidates / low confidence) ⇒ show the candidates and **ask**.
- The rebase target is **`origin/<base>`** (always the freshly-fetched remote tip).
- **Sync the local `<base>` ref to match `origin/<base>`** (so the local base isn't stale).
  **Unpushed work is the one thing at risk here**: if `git rev-list origin/<base>..<base>` is
  non-empty, the local base has commits not on the remote — **warn** before overwriting (they
  survive only in the reflog), then `git branch -f <base> origin/<base>`. (We're on the feature
  branch, so `<base>` isn't checked out.)
- **Your branch vs its remote — the check the lease can't make for you.** If
  `git rev-parse --verify --quiet origin/<branch>` resolves, run
  `git rev-list --count <branch>..origin/<branch>`; non-zero ⇒ **stop and ask**. Those are
  commits someone else pushed to your branch. Pre-flight has already fetched, so
  `--force-with-lease` will measure against them and **pass**, and the loss gate can't see them
  either — they're in neither range-diff column. Integrate them first (offer: fast-forward, or
  merge them in, then re-run) or abort.
- **Nothing to do**: if `git merge-base --is-ancestor origin/<base> <branch>`, the branch is
  already on top of the latest base ⇒ report "already up to date", stop.

Then take the backup ref, per [SKILL.md's Backup refs](../SKILL.md#backup-refs).

## Step 2 — Rebase (the safest `--onto` you can compute, no prompts)

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
- **Replay anything you can't prove is already on the base.** `git cherry` is the only evidence
  that counts: `-` means integrated, everything else replays. A commit whose content looks merged
  but isn't patch-detectable is unproven, and you aren't prompting — so it replays. More
  conflicts, zero loss.

Conflicts are [SKILL.md's Resolving conflicts](../SKILL.md#resolving-conflicts-preserve-both-sides),
unchanged — this path uses plain `git rebase --continue`.

When the rebase completes, run [the loss gate](../SKILL.md#the-loss-gate-range-diff) once, with
`MB` from above and `<newbase>` = `origin/<base>`.

## Step 3 — Done

- **Branches stacked on this one, by hand** — check before the push:
  `git branch --contains refs/rebase-skill/<run-id>/<branch> --format='%(refname:short)'`.
  Use the **backup ref**, not `<branch>`: it points at the tip you just rewrote, so anything still
  descending from it is now parented on abandoned commits. Once the rebase has completed the
  branch itself has moved off that tip, so the list is exactly the orphans — filter `<branch>` out
  anyway, since a no-op or aborted rebase leaves it in.
  Non-empty ⇒ **say so and name them**, with the remedy: each needs its own rebase onto this
  branch, working from the bottom of the chain upwards. Don't rebase them yourself — the user
  didn't ask, and they may be shared.
- Report a summary: commits replayed, commits skipped (already on base) and why, conflicts
  auto-resolved, conflicts you decided.
- **Push directly**: `git push --force-with-lease`. Push is permission-gated by the harness, so
  the prompt is the confirmation — if it's **denied**, that's fine: report the branch as rebased
  and verified locally and leave it for the user. Push **only this branch** — anything stacked on
  it is the user's to rebase and publish.
- The run is done once the push has resolved and the backup refs are deleted — or the refs are
  kept and the exact restore commands are in the report.
