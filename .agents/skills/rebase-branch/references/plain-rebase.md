# Plain rebase (no tracked stack)

You are here because `gh-stack` isn't tracking a stack in this repo. That does **not** mean this
branch stands alone. Someone may have cut branches off it by hand, and those are as real a stack
as a tracked one. Nothing here can cascade them, but Step 3 finds them and says what they'll need.

This path has three steps and uses the shared mechanics in SKILL.md, namely
[Dirty tree](../SKILL.md#dirty-tree), [Backup refs](../SKILL.md#backup-refs),
[Resolving conflicts](../SKILL.md#resolving-conflicts-preserve-both-sides), and
[the loss gate](../SKILL.md#the-loss-gate-range-diff).

## Step 1 — Base setup (determine, sync)

Everything here happens before any rewrite, so this is the last point where you can stop safely.
Pre-flight has already fetched, and `origin` below means the remote it fetched. Handle
uncommitted work first, per [SKILL.md's Dirty tree](../SKILL.md#dirty-tree).

- **Determine the base.**
  - If the user passed a base as an argument, use it and skip detection.
  - Else detect the branch's actual parent, which handles a branch cut from another branch:
    1. Configured upstream from `git rev-parse --abbrev-ref @{upstream}`. Use it **only** if it
       isn't this branch's own remote-tracking ref (`origin/<current>`).
    2. Else infer the fork. For each likely base (repo default, `develop`, `main`, `master`,
       and any branch this one obviously forked from per reflog), compute
       `git merge-base <branch> origin/<candidate>` and how many commits are unique to the
       branch. The candidate the branch most plausibly forked from is the parent.
    3. Fall back to the repo default. Run `git symbolic-ref --quiet refs/remotes/origin/HEAD`
       and strip the result to its leaf (e.g. `develop`). Fall back to `develop` if it is unset.
  - When you are confident (one clear candidate), use it silently. When it is ambiguous
    (multiple plausible candidates or low confidence), show the candidates and **ask**.
- The rebase target is always `origin/<base>`, the freshly-fetched remote tip.
- **Sync the local `<base>` ref to match `origin/<base>`**, so the local base isn't stale.
  If `git rev-list origin/<base>..<base>` is non-empty, the local base holds unpushed commits.
  Leave it where it is and say so, since the rebase targets `origin/<base>` anyway. Otherwise
  run `git branch -f <base> origin/<base>`. You're on the feature branch, so `<base>` isn't
  checked out.
- **Compare your branch with its remote, because the lease can't make this check for you.** If
  `git rev-parse --verify --quiet origin/<branch>` resolves, run
  `git rev-list --count <branch>..origin/<branch>`. If the count is non-zero, **stop and ask**.
  Those are commits someone else pushed to your branch. Pre-flight has already fetched, so
  `--force-with-lease` will measure against them and **pass**, and the loss gate can't see them
  either, because they're in neither range-diff column. Integrate them first (offer to
  fast-forward, or merge them in, then re-run) or abort.
- **Nothing to do.** If `git merge-base --is-ancestor origin/<base> <branch>` succeeds, the
  branch is already on top of the latest base. Report "already up to date" and stop.

Then take the backup ref, per [SKILL.md's Backup refs](../SKILL.md#backup-refs).

## Step 2 — Rebase (the safest `--onto` you can compute, no prompts)

Ask for no confirmation. Pick the **safest cut point**:

- `MB = git merge-base <branch> origin/<base>` (the fork point).
- Classify each commit in `MB..<branch>` with `git cherry origin/<base> <branch>`. `-` means
  patch-equal to a commit already on the base, and `+` means genuinely new.
- Let the **already-integrated prefix** be the leading contiguous run of `-` commits from
  `MB`. If it's non-empty, its last commit is the **cutpoint** and everything before it is
  _provably_ already on the base. Run
  `git rebase --onto origin/<base> <cutpoint> <branch>`, which replays only the genuinely-new
  commits and skips the integrated prefix. Skipping that prefix is what avoids most conflicts.
- Otherwise run `git rebase origin/<base>`. The default rebase still drops patch-equal commits.
- **Replay anything you can't prove is already on the base.** `git cherry` is the only evidence
  that counts. `-` means integrated, and everything else replays. A commit whose content looks
  merged but isn't patch-detectable is unproven, and you aren't prompting, so it replays.

Conflicts follow [SKILL.md's Resolving conflicts](../SKILL.md#resolving-conflicts-preserve-both-sides)
unchanged. This path uses plain `git rebase --continue`.

When the rebase completes, run [the loss gate](../SKILL.md#the-loss-gate-range-diff) once, with
`MB` from above and `<newbase>` = `origin/<base>`.

## Step 3 — Done

- **Check for branches stacked on this one by hand** before the push:
  `git branch --contains refs/rebase-skill/<run-id>/<branch> --format='%(refname:short)'`.
  Use the **backup ref**, not `<branch>`. It points at the tip you just rewrote, so anything still
  descending from it is now parented on abandoned commits. Once the rebase has completed, the
  branch itself has moved off that tip, so the list is exactly the orphans. Filter `<branch>` out
  anyway, since a no-op or aborted rebase leaves it in.
  If the list is non-empty, **say so and name them**, with the remedy: each needs its own rebase
  onto this branch, working from the bottom of the chain upwards. Don't rebase them yourself,
  because the user didn't ask and they may be shared.
- Report a summary with the commits replayed, the commits skipped (already on base) and why, the
  conflicts auto-resolved, and the conflicts you decided.
- **Push directly** with `git push --force-with-lease`. The harness gates the push behind a
  permission prompt, so that prompt is the confirmation. If the user **denies** it, report the
  branch as rebased and verified locally and leave it for the user. Push **only this branch**.
  Anything stacked on it is the user's to rebase and publish.
- The run is done once the push has resolved and the backup refs are deleted, or once the refs
  are kept and the exact restore commands are in the report.
