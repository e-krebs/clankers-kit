---
name: pr-followup
description: Watch CI after git push, gh pr create or gh stack push/submit, then advance the PR. On green, mark a draft ready or re-request stale reviewers and move the ticket to review. On red, report failures. Not for merging or auto-fixing.
---

# pr-followup

After a push or a PR-create, watch the PR's checks and advance it. Green opens a draft for review
or re-requests a now-stale review, and moves the linked ticket. Red analyses the failures and
reports them. Gather the state first, then make **one** offer that authorizes the whole chain.

`$PRS` below is `bash ~/.agents/skills/pr-followup/scripts/pr-state.sh`. It returns compact PR JSON
(check counts by state, reviewer logins, no review bodies), so use it for every PR read instead of
raw `statusCheckRollup` or `latestReviews`.

## Safety

- With no associated PR, exit silently, with no output. Ordinary pushes to PR-less branches stay
  quiet.
- The triggering hook fires on any command that mentions a push or PR-create, even one that pushed
  nothing, so Step 0's resolve-or-exit always runs first.

## Profile

Read the workflow profile rows from context, where the session-start hook injects the resolved
table. Only when they are absent, run
`bash ~/.agents/skills/workflow-profile/scripts/resolve-profile.sh --rows`. Three rows decide the run:

- CI watcher naming a CI (CircleCI, GitHub Actions) means the watch runs. Both report through
  `gh pr checks`, so the row tells you which staged-job behaviour to expect, not which command to
  use.
- CI watcher `none` means there is nothing to watch. Confirm in one line that the push landed
  (branch, commits, and the PR link when one exists) and stop. No offer, no watch, no tracker move.
- Ticket system `none` means no ticket question and no tracker move in this run.
- PR shape carrying the clause `gh stack for a multi-PR change`, or the `gh-stack` spelling, means
  the push may have moved a whole stack, so Step 0 enumerates the members before resolving one PR.
  Without the clause, there is one PR and this file applies as written. The clause never overrides
  CI watcher `none`.

Done when the rows are in hand, the watch-or-stop branch is chosen, and, where the clause applies,
the single-PR or stack enumeration is picked.

## Step 0: Gather (read-only, no side effects)

- Current branch: `git branch --show-current`.
- The paused cascade, only where PR shape carries the clause:
  `test -e "$(git rev-parse --git-common-dir)/gh-stack-rebase-state"`. If the file is present,
  HEAD is detached, so there is no branch to key on and every `gh stack` read fails with
  `not on any branch`. Name the pause in one line and stop.
- The stack, only where PR shape carries the clause, from the local metadata:
  `bash ~/.agents/skills/workflow-profile/scripts/gh-stack-lookup.sh --branch "$(git branch --show-current)"`.
  It reads `gh stack`'s file from the git common dir, so it answers from a linked worktree, and
  no `gh stack` command runs anywhere in this skill. Its exit code is the membership state. Read
  the named file in full before running any further command:
  - **Exit 0, present.** The script prints one line per stack listing this branch, members bottom
    to top. With two lines, ask which stack. Read
    [references/gh-stack-followup.md](references/gh-stack-followup.md), which takes over from F1.
  - **Exit 3 or 4, absent.** Read [references/gh-stack-walk.md](references/gh-stack-walk.md),
    because `gh stack link` builds a stack on GitHub and writes nothing locally. A walk that finds
    no chain returns here for the single-PR resolve, reusing the PR it already fetched.
  - **Exit 5, 2 or 127, unknown.** Say so in one line, then run the walk as on absent. The walk is
    read-only and a superset of the absent path.
- Resolve the PR with `$PRS` (the current branch's PR). On `no pull requests found`, exit
  silently. On a `MERGED` or `CLOSED` state, exit silently, because there is nothing to advance. On
  any other error (auth, network), report it in one line and stop.
- Derive from the JSON: draft vs open (`isDraft`); the re-request set, which is `reviewers` minus
  `author`, minus bots (`[bot]` logins and `copilot-pull-request-reviewer`, since gh's JSON has no
  author type), and minus anyone already in `requested`, since re-adding them is a no-op; and the
  CI status from `checks` (pending / passing / failing / none).
- The linked ticket, only once the PR is confirmed live and only when Ticket system names a
  tracker. Take the ID through the detection order in the profile's `## Tracker rules`, starting
  with the PR body, which conventionally carries the reference. With an ID, follow those same rules
  to resolve the move to the tracker's in-review state, carrying forward a matched transition, the
  picker candidates, or nothing applicable.
- Decide the green-action. For a draft, mark it ready (`gh pr ready`). For an open PR with a
  non-empty re-request set, re-request those reviewers. For an open PR whose reviewers are all
  still pending in `requested`, there is nothing to request, so report them. For an open PR with
  no reviewers at all, ask for reviewers. When a tracker move applies, green also performs it, in
  every one of those cases.
- If CI is already complete at gather time, skip only the watch. Green still passes through the
  Step 1 offer before Step 3, and red goes to Step 4. Treat a PR with no checks configured as
  green.

Done when the PR state, the re-request set, the CI status, the tracker-move candidate, and the
green-action are all resolved, and the stack read either enumerated its members or handed off to
a reference file, or the silent exit fired.

## Step 1: Offer (the gate)

Present one summary, then make the offer through the harness's question tool when it has one, else
as numbered questions in prose. Use selectable choices, not a prose "Proceed?" you wait on. Spell
out exactly what will happen, and offer Proceed (first, recommended) plus a decline.

When a tracker move applies, batch a second, dedicated question alongside Proceed: also move
`<TICKET>` from `<current>` to the in-review state on green? When no transition targets that state,
offer the rules' picker plus Skip instead, so the user can still decline the move on its own. Omit
it when no move applies. For the open-PR case, name the reviewers to be re-requested. Nothing runs,
not even the watch, until the user picks Proceed. That one interaction authorizes the chain, and
the green-action then fires unattended.

Done when the user picks Proceed, or declines.

## Step 2: Watch (after yes)

Launch `gh pr checks <n> --watch > <scratch>/checks-<n>.txt 2>&1` as a background Bash task,
without `--fail-fast`, so the run covers every failing check. `<scratch>` is the harness's scratch
directory, else `mktemp -d`. The command blocks until the checks complete, and the harness
re-invokes you on exit. The file reprints the full table on every poll, so leave it unread. The
re-gather below is the source of truth.

Distrust the watch's exit code. It judges only the checks registered when it polls, and a staged CI
(a dynamic setup job that posts the real jobs seconds later) lets a watch exit `0` on a lone
bootstrap check. After every watch exit, pause a few seconds, then run
`$PRS --checks <n>`. Re-watch when anything is still pending, new checks
appeared, or the total looks suspiciously thin.

Done when a fresh `--checks` read shows every check in a terminal state.

## Step 3: On green

- For a draft PR, run `gh pr ready <n>`. The forge auto-requests the CODEOWNERS-matched reviewers
  on undraft, so read and report who it assigned rather than parsing `.github/CODEOWNERS` or adding
  anyone by hand. `reviewRequests` holds teams (`.slug`) as well as users (`.login`), so report
  both: `gh pr view <n> --json reviewRequests --jq '.reviewRequests[] | (.login // .slug)'`.
- For an open PR with a re-request set, run `gh pr edit <n> --add-reviewer <login>` for each login.
  The forge treats adding a past reviewer as a re-request. Report who was re-requested.
- For an open PR with no reviewers, ask who should review, through the harness's question tool
  when it has one, else in prose. Offer cheap suggestions when they exist: the CODEOWNERS matches
  for the touched paths, and the recent committers of those files
  (`git log --format=%an -- <paths>`). Then run `gh pr edit <n> --add-reviewer <login>` for the
  picks. A declined question mutates nothing.
- When a tracker move was resolved and the user chose Yes, perform it after the forge action, per
  the profile's `## Tracker rules`, and report it. The move is best-effort. On error, report and
  continue, since the PR is already advanced.

Close by naming the next step: the merge capability takes it from here, once the review lands. This
skill neither merges nor waits for the approval.

Done when the green-action and, where it applies, the tracker move have both been attempted, and
the next step is named.

## Step 4: On red

List the failing checks with `$PRS --failing <n>`. For a GitHub Actions check,
take the run id from its `url` (`/actions/runs/<id>/`), save
`gh run view <id> --log-failed > <scratch>/run-<id>.log`, and read only a bounded excerpt:
`grep -niE 'error|fail' <scratch>/run-<id>.log | head -40`, or `tail -60` when the grep finds nothing.
Other providers (CircleCI) expose no logs through `gh`, so report the check's `url`. Give a short
root-cause read, then ask whether to investigate. No tracker move happens on red.

Done when the failures are reported and the question is asked. The next move is the user's.

## Gotchas

- When one branch has several PRs, `gh pr view` resolves by head branch. Use that one.
- A headless or cron run has no tracker tooling. The best-effort contract skips the move and the
  PR still advances.
