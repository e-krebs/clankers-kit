# Stacked PRs (`gh stack`)

Verified against `gh stack` v0.1.0.

Load this file when Step 0 has a member list: from the lookup's line, or from the PR-graph walk.
No `gh stack` command runs in this skill. `gh stack submit` and `gh stack push` both republish
**every** active branch in the stack, so this run owns every member's checks and not only the ones
on the branch the user is standing on.

This file replaces SKILL.md's Step 0 PR resolve and its Steps 2 and 3. Step 1's gate still runs,
over F2's summary. Step 4's red path still runs, with the failing member named.

## F1: Enumerate the members (read-only)

Take each member's branch and PR number, bottom to top, from the lookup's line or the walk. A member
printed `#-` has no PR number in the metadata yet, which happens seconds after a submit: resolve it
with `gh pr list --head <branch> --state open --json number,url`. The lookup's `(merged)` suffix
lags and sets nothing aside; the PR's own state below does. Then read each member PR with
`$PRS <n> --stack`, reusing any PR the walk already read.

- Set aside every member whose PR reads `MERGED` or `CLOSED`. There is nothing to advance there,
  and the push skipped them. Keep a queued member, because `gh pr view` carries no
  merge-queue field, a queued PR is never a draft, and a reviewer re-request on one is harmless.
- Set aside any member whose `isCrossRepository` is true: its `headRefName` names a fork branch,
  and nothing here may act on it. Name the ones you set aside.
- If no member has a live PR, exit silently, exactly as Step 0's no-PR rule.
- **The bottom open member** is the lowest live member: the one whose base is the trunk (the
  profile's Default branch row), or whose base is a member that has already merged. Every report
  orders the stack from it upwards.

Done when the member list is in hand bottom to top, each with its PR JSON, the bottom open member is
identified, and the merged and cross-repo members are set aside and named, or the silent exit fired.

## F2: What the gate offers

Step 1's one offer, widened to the stack, so the user authorizes a stack-wide chain rather than one
PR's:

- The stack bottom to top: each live member's PR number, its draft state, and its CI status now.
- The watch: every live member's checks, not only the current branch's.
- The green action: Step 0's rules applied to **every live member**, bottom to top.
- Tracker moves: one per live member that has a ticket, in the same question.

Done when the user picks Proceed, or declines.

## F3: Watch every member

Run Step 2 per live member: one watch each, launched as background Bash tasks in a single round,
each writing to its own unread file. A stack push re-runs CI on every branch, and a failure two
members down matters most, so watching only the current branch would miss it.

Apply Step 2's distrust **per member**: after each watch exits, pause a few seconds, run
`$PRS --checks <n>` for that PR, and re-watch on pending, new, or suspiciously few checks. A member
is done only at a terminal state, so keep looping while any check is pending.

Done when a fresh `--checks` read shows every live member's checks in a terminal state.

## F4: Advance the stack

Green means **every** live member's checks reached a terminal success. If any member is red, go to
Step 4, naming which member failed and on what. Nothing is advanced anywhere and no tracker move happens,
because a green member above a blocked one is still blocked by it.

On green, run Step 3 as written for every live member, bottom to top, then each tracker
move. Report each member's outcome by number. Close by naming the next step: the merge
capability lands the whole stack.

Done when the green action and, where they apply, the tracker moves have been attempted for every
live member, each outcome is reported by number, and the next step is named.
