---
name: pr-followup
description: Watch CI after a push or PR, then advance it: on green, mark a draft PR ready for review or re-request a stale review and move the linked tracker item to In Review; on red, analyse and report. Use when you want CI watched after a git push or gh pr create. Do not use to merge or auto-fix.
---

# pr-followup

After a push or PR-create, watch the PR's CI and advance it: green → open a draft for
review or re-request a now-stale review and move the linked tracker item to In Review; red →
analyse and report. Gathers state first, then makes **one** offer that authorizes the whole
chain. Never merges, never auto-fixes.

## Safety

- Gather is read-only. Nothing is watched or mutated until the user approves the single
  offer (Step 1). Opening a PR for review and re-requesting reviews are outward-facing.
- The linked-item discovery (Step 0) is read-only; moving the tracker item is outward-facing,
  gated by the Step 1 offer, runs only after the green GitHub action, best-effort, and silently
  skipped when no move applies (no item / already In Review / tracker unreachable).
- No associated PR → **exit silently**, with no output. Ordinary pushes to PR-less branches
  must stay quiet.
- The triggering hook is **permissive** — it can fire on any Bash command whose text mentions
  `git push` / `gh pr create`, even one that doesn't actually push. So **resolve-or-exit
  (Step 0) is always the first action**; on a missing / merged / closed PR it costs one quiet
  `gh pr view` and stops, with nothing shown to the user.
- On red CI, report and stop — never auto-fix or re-push.

## Step 0 — Gather (read-only, no side effects)

- Current branch: `git branch --show-current`.
- Resolve the PR for the current branch:
  `gh pr view --json number,state,isDraft,url,title,body,reviewDecision,latestReviews,reviewRequests,headRefName,statusCheckRollup`.
  - No PR (command errors / empty) → **exit silently**. Done.
  - PR already `MERGED` or `CLOSED` → **exit silently**. Nothing to advance.
- Derive from the JSON:
  - **draft vs open**: `isDraft`.
  - Submitted reviewers: distinct `latestReviews[].author.login`, minus the PR author,
    bots (`[bot]` logins / `__typename == "Bot"`), and anyone whose request is already
    pending in `reviewRequests` (re-adding them is a no-op). Only individuals submit
    reviews, so this set is users, never teams — re-request scope is individual reviewers
    by design.
  - **CI status**: from `statusCheckRollup` (pending / passing / failing / none).
  - **linked item** (only once the pull request is confirmed live): the first issue key —
    `[A-Z]{2,}-\d+` or `#\d+` — in the body / branch name / `<base>..HEAD` commit subjects
    (multiple → prefer the one on the `[TICKET]`/motivation line, else the first). If a tracker
    is available, read the item's status and available transitions and pick the one whose
    **target status** (case-insensitive) is **In Review** — match the target, not the
    transition's display name. All read-only. No key / already In Review / tracker unreachable →
    no move; transitions exist but none target In Review → keep the candidates for a Step-1 picker.
- Decide the **green-action**:
  - draft → mark ready (`gh pr ready`).
  - open with submitted reviewers → re-request those reviewers.
  - open without submitted reviewers → report-only (nothing to re-request).
  - If a move applies, green **also** advances the linked item to In Review (best-effort) — in
    any of the above cases; it self-no-ops once the item is already there.
- **If CI is already complete** at gather time, skip the watch: green → go straight to the
  green-action; red → straight to analyse + report. No checks configured → treat as green.

## Step 1 — Offer (the GATE)

Present a single summary, then make the offer through the **AskUserQuestion** tool — selectable
choices, not a prose "Proceed?" you wait on. Spell out exactly what will happen, and offer
"Proceed" (first / recommended) plus a decline option, e.g.:

> PR #123 «title» is **draft**, CI **pending**. I'll watch CI →
> on **green** mark it ready for review (GitHub auto-requests the CODEOWNERS-matched
> reviewers) and move PROJ-42 (To Do → In Review) → on **red** report the failing checks.

For the open case, name the reviewers to be re-requested. When a move is applicable, add it as a
**separate, independently-declinable** question in the same AskUserQuestion batch — `Also move
<ITEM> (<current> → In Review) on green? [Yes / Skip]` — so the user can advance the PR on
Proceed while still skipping just the move; omit that question when no move applies. When
transitions exist but none target In Review, make it a picker of the available transitions plus
Skip. Nothing runs — not even the watch — until the user picks Proceed. One interaction settles
both; the green-action and any approved item move then fire unattended.

## Step 2 — Watch (after yes)

Launch `gh pr checks <n> --watch` as a **background Bash task** (no `--fail-fast`, so the
report covers all failing checks). It blocks until checks complete; the harness re-invokes
on exit. (If Step 0 found CI already complete, skip straight to the green / red handling.)

Don't trust the watch's exit code. It only judges the checks registered when it polls;
staged CIs (e.g. a dynamic `setup` job that generates the real pipeline) post the real jobs
seconds later, so a watch can exit `0` on a lone bootstrap check before they appear. After
every watch exit, **pause a few seconds, then re-gather `statusCheckRollup`** (staged jobs
need a moment to register, and the pause keeps a thin terminal set from spinning); if
anything is still pending, new checks appeared, or the set is suspiciously thin, **re-watch**.
Only a fresh `gh pr view` with all checks terminal means settled.

## Step 3 — On green

- Draft PR → `gh pr ready <n>`. GitHub auto-requests the CODEOWNERS-matched reviewers on
  undraft — don't parse `.github/CODEOWNERS` yourself. Instead, after undraft, read and
  report the reviewers GitHub assigned — informational; do not add them manually.
  `reviewRequests` includes teams (`.slug`), not just users (`.login`); report both, e.g.
  `gh pr view <n> --json reviewRequests --jq '.reviewRequests[] | (.login // .slug)'`.
- Open PR with submitted reviewers → for each, `gh pr edit <n> --add-reviewer <login>`
  (GitHub treats adding someone who already reviewed as a re-request). Report who was
  re-requested.
- Open PR with no reviewers → report green; no mutation.
- Linked item (if a move was resolved and approved) → after the GitHub action above, transition
  it to In Review via the resolved transition id; report the move (`PROJ-42 → In Review`).
  Best-effort — on a tracker error, report and continue; the PR is already advanced.

## Step 4 — On red

Report which checks failed; fetch + summarize the failing logs
(`gh run view <id> --log-failed`); give a short root-cause read. Stop and ask whether to
investigate. Do not auto-fix or re-push.

## Gotchas

- No PR / on the default branch (push with no PR) → silent exit (Step 0). Resolve-or-exit
  is always the first action so a permissive hook never produces stray output.
- Multiple PRs for the branch → `gh pr view` resolves by head branch; use that one.
- Failed / dry-run push that still fired the hook → Step 0 re-derives real state and
  exits silently if there's no PR. Harmless.
- **Watch exit code lies** on staged pipelines — re-gather `statusCheckRollup` after every
  watch exit; only all-terminal checks mean settled.
- Bots and self-reviews are excluded from the re-request set; only real, previously-submitted
  human reviewers get re-requested.
- No linked item / already In Review / tracker unreachable (e.g. a headless or cron run) → no
  item question and no move; the PR still advances normally.
- Multiple issue keys in the body → prefer the one on the `[TICKET]`/motivation line, else the
  first.
