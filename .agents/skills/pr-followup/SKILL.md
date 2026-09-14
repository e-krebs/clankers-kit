---
name: pr-followup
description: Watch CI after a push or PR-create and advance the PR — on green mark a draft ready or re-request a stale review and move the linked ticket to the in-review state; on red report the failures. Use when CI should be watched after git push / gh pr create. Do not use to merge or auto-fix.
---

# pr-followup

After a push or a PR-create, watch the PR's checks and advance it: green opens a draft for review
or re-requests a now-stale review and moves the linked ticket; red analyses and reports. State is
gathered first, then **one** offer authorizes the whole chain.

## Safety

- No associated PR → exit silently, with no output. Ordinary pushes to PR-less branches stay quiet.
- The triggering hook is permissive: it fires on any Bash command whose text mentions `git push` or
  `gh pr create`, even one that pushed nothing. So resolve-or-exit (Step 0) is always the first
  action; a missing, merged, or closed PR costs one quiet `gh pr view` and stops.

## Profile

Read the workflow profile rows from context — the session-start hook injects the resolved table.
When they are absent from context, run
`bash ~/.agents/skills/workflow-profile/scripts/resolve-profile.sh --rows` and read its table.
Two rows decide the run:

- CI watcher naming a CI (CircleCI, GitHub Actions) → the watch runs. Both report through
  `gh pr checks`, so the row tells you which staged-job behaviour to expect, not which command to
  use.
- CI watcher `none` → nothing to watch: confirm in one line that the push landed (branch, commits,
  and the PR link when one exists) and stop. No offer, no watch, no tracker move.
- Ticket system `none` → no ticket question and no tracker move in this run.

Done when the rows are in hand and the watch-or-stop branch is chosen.

## Step 0 — Gather (read-only, no side effects)

- Current branch: `git branch --show-current`.
- Resolve the PR for it: `gh pr view --json
  number,state,isDraft,url,title,body,reviewDecision,latestReviews,reviewRequests,headRefName,statusCheckRollup`.
  No PR (the command errors or returns empty) → exit silently. A `MERGED` or `CLOSED` PR → exit
  silently; there is nothing to advance.
- Derive from the JSON: draft vs open (`isDraft`); the submitted reviewers — distinct
  `latestReviews[].author.login` minus the PR author, bots (`[bot]` logins, `__typename == "Bot"`),
  and anyone whose request is already pending in `reviewRequests`, since re-adding them is a no-op;
  and the CI status from `statusCheckRollup` (pending / passing / failing / none).
- The linked ticket, only once the PR is confirmed live and only when Ticket system names a
  tracker: take the ID through the detection order in the profile's `## Tracker rules`, starting
  with the PR body, which conventionally carries the reference. With an ID, follow those same rules
  to resolve the move to the tracker's in-review state, carrying forward a matched transition, the
  picker candidates, or nothing applicable.
- Decide the green-action: a draft → mark ready (`gh pr ready`); an open PR with submitted
  reviewers → re-request those reviewers; an open PR without them → ask for reviewers. When a tracker
  move applies, green also performs it, in every one of those cases.
- CI already complete at gather time → skip the watch only: green still passes through the Step 1
  offer before Step 3, red goes to Step 4. No checks configured → treat as green.

Done when the PR state, the reviewer set, the CI status, the tracker-move candidate, and the
green-action are all resolved, or the silent exit fired.

## Step 1 — Offer (the gate)

Present one summary, then make the offer through the harness's question tool when it has one, else
as numbered questions in prose — selectable choices, not a prose "Proceed?" you wait on. Spell out
exactly what will happen, and offer Proceed (first, recommended) plus a decline.

When a tracker move applies, batch a second, dedicated question alongside Proceed: also move
`<TICKET>` (`<current>` → the in-review state) on green? — or the rules' picker plus Skip when no
transition targets that state, so the move stays independently declinable. Omit it when no move
applies. For the open-PR case, name the reviewers to be re-requested. Nothing runs — not even the
watch — until the user picks Proceed; that one interaction authorizes the chain, and the
green-action then fires unattended.

Done when the user picks Proceed, or declines.

## Step 2 — Watch (after yes)

Launch `gh pr checks <n> --watch` as a background Bash task, without `--fail-fast`, so the report
covers every failing check. It blocks until the checks complete, and the harness re-invokes on
exit.

Distrust the watch's exit code: it judges only the checks registered when it polls, and a staged CI
(a dynamic setup job that posts the real jobs seconds later) lets a watch exit `0` on a lone
bootstrap check. After every watch exit, pause a few seconds, then re-gather `statusCheckRollup`;
re-watch when anything is still pending, new checks appeared, or the set looks suspiciously thin.

Done when a fresh `gh pr view` shows every check in a terminal state.

## Step 3 — On green

- Draft PR → `gh pr ready <n>`. The forge auto-requests the CODEOWNERS-matched reviewers on
  undraft, so read and report who it assigned rather than parsing `.github/CODEOWNERS` or adding
  anyone by hand. `reviewRequests` holds teams (`.slug`) as well as users (`.login`) — report both:
  `gh pr view <n> --json reviewRequests --jq '.reviewRequests[] | (.login // .slug)'`.
- Open PR with submitted reviewers → `gh pr edit <n> --add-reviewer <login>` each; the forge treats
  adding a past reviewer as a re-request. Report who was re-requested.
- Open PR with no reviewers → ask who should review, through the harness's question tool when
  it has one, else in prose, with cheap suggestions when they exist: the CODEOWNERS matches for
  the touched paths, and the recent committers of those files (`git log --format=%an -- <paths>`).
  Then `gh pr edit <n> --add-reviewer <login>` for the picks; a declined question mutates nothing.
- Tracker move, when one was resolved and the user chose Yes → after the forge action, perform it
  per the profile's `## Tracker rules` and report it. Best-effort: on error, report and continue,
  since the PR is already advanced.

Close by naming the next step: the merge capability takes it from here, once the review lands. This
skill neither merges nor waits for the approval.

Done when the green-action and, where it applies, the tracker move have both been attempted, and
the next step is named.

## Step 4 — On red

Report which checks failed, fetch and summarize the failing logs (`gh run view <id> --log-failed`),
give a short root-cause read, then ask whether to investigate. No tracker move happens on red.

Done when the failures are reported and the question is asked; the next move is the user's.

## Gotchas

- Several PRs for one branch → `gh pr view` resolves by head branch; use that one.
- A headless or cron run has no tracker tooling: the best-effort contract skips the move and the
  PR still advances.
