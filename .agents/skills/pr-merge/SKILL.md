---
name: pr-merge
description: >-
  Merge an approved PR the way the repo's workflow profile prescribes — squash, delete the
  branch, move the linked ticket to Done, restack dependants. Use when the user says merge the
  PR, land it, or ship it once approved. Not for creating a PR, watching CI, or resolving
  conflicts.
---

# pr-merge

The landing gate. It reads the repo's merge habits from the workflow profile, gathers the PR's
real state, offers the merge and the tracker move in one declinable gate, then executes. A PR
that cannot land gets one line naming the blocker, and nothing else.

A PR with other open PRs stacked on it lands differently, and step 2 is where that is decided:
[references/gh-stack-merge.md](references/gh-stack-merge.md) replaces steps 3 and 4 and adds a
restack step. The steps below are the lone-PR path.

## Steps

1. Read the workflow profile: the rows the session-start hook injected into context, else the
   table `bash ~/.agents/skills/workflow-profile/scripts/resolve-profile.sh --rows` prints. Three rows
   matter: Commit policy, PR shape, Ticket system. Commit policy `direct commits to main`, or
   PR shape `n/a`, means this repo has no PR flow: say so and stop.
   Done when those three rows are in hand, or the no-PR-flow exit has fired.
2. Gather PR state, read-only:
   `gh pr view [<number>|<url>|<branch>] --json number,title,state,isDraft,reviewDecision,mergeable,mergeStateStatus,statusCheckRollup,headRefName,baseRefName,body,url`.
   With no argument it resolves the current branch, and that PR is the only candidate: no PR
   for it, or one already `MERGED` / `CLOSED`, ends the run in one line, without hunting for
   another open PR to land.

   Then **pick the path** with one query:
   `gh pr list --state open --base <headRefName> --json number,url,headRefName,baseRefName,isCrossRepository`.
   **It has to run here.** GitHub retargets a stacked PR's dependants about two seconds after
   the parent merges — both dependants in the incident logged
   `automatic_base_change_succeeded` two seconds in — so a post-merge query finds nothing at all.
   - **Empty** ⇒ a lone PR: follow steps 3 and 4 below, and nothing about stacks reaches the
     user. An ordinary merge pays this one extra call, plus step 3's sibling search where a
     tracker is named.
   - **Non-empty** ⇒ **run no further command until you have read
     [references/gh-stack-merge.md](references/gh-stack-merge.md) in full**, then follow it. It
     replaces steps 3 and 4 and adds the restack. Beyond this one query it is the only source
     for `gh stack` invocations — treat any others you recall from memory as wrong.
   Done when that JSON is in hand and the path is picked, or the one-line exit fired.
3. Judge, then gate. A PR is blocked by any of: `isDraft` true; `reviewDecision`
   `CHANGES_REQUESTED`, or not `APPROVED` when PR shape names a CODEOWNERS review; a failing or
   still-pending `statusCheckRollup`; `mergeable` `CONFLICTING`; `mergeStateStatus` `DIRTY`,
   `BEHIND` or `BLOCKED`. Blocked → report that one blocker in a single line and stop. Clear →
   one declinable offer through the harness's question tool, else as numbered questions in
   prose: the merge method PR shape prescribes plus the branch deletion as the first question,
   and, when Ticket system is not `none` and no other open PR carries the ticket, the ticket's
   move to the Done state as a second, independently declinable one. One search settles that, the
   ID as the profile's `## Tracker rules` resolve it and `<owner/repo>` from the PR's own `url`,
   dropping the PRs this merge will land — here, this PR alone:
   `gh pr list --repo <owner/repo> --search "<TICKET-ID> in:title,body" --state open --json number,url`
   Any row ⇒ offer the merge alone, name those PRs in one line, and say the Done move is there on
   request. No ID resolves ⇒ no search and no ticket question. The search failing ⇒ both
   questions, saying the sibling check did not run. Done when each question is accepted or
   declined, or the blocker line is out.
4. Execute in order. `gh pr merge <n> --squash --delete-branch` when PR shape says squash,
   `--merge --delete-branch` otherwise; `-d` removes the local branch as well as the remote one.
   Re-read `gh pr view <n> --json state,mergeCommit`. Only when it reads `MERGED` and the move
   was accepted, transition the ticket using the `## Tracker rules` section of the profile's org
   file for the mechanics and the Done state name; a queued or failed merge moves nothing. Done
   when the report names the merge SHA, the deleted branch, and the ticket's new state (or why
   it did not move) — or says the merge is queued and the ticket untouched.

   A merge that comes back `GraphQL: This pull request is part of a stack and must be merged
   using the asynchronous merge REST API` is not an error: GitHub is saying this PR is stacked
   even though step 2 found nothing above it. Read
   [references/gh-stack-merge.md](references/gh-stack-merge.md) in full and follow it from its
   capture step, before any further merge attempt.

## Gotchas

- `mergeStateStatus` separates the red flavours: `BLOCKED` is an unsatisfied branch-protection
  rule (missing approval, required check), `BEHIND` is a base that moved on, `DIRTY` a real
  conflict. The blocker line names which one, and the fix belongs to the user.
- `mergeable` reads `UNKNOWN` for a few seconds after a push while GitHub recomputes it. Re-read
  once after a short pause before calling it blocked.
- Branch protection can queue a merge rather than apply it: the command returns, yet `state`
  stays `OPEN` until the queue lands the PR. Report it as queued and stop there.
- A protection rule that refuses the merge hands the PR back to the user; `--admin` stays out
  of this flow.
- `gh pr list --search` indexes a freshly-opened PR seconds late, and it reads only titles and
  bodies in this one repo, so a sibling opened moments ago, keyed only in its branch name, or
  living in another repo all read as absent. Re-run the search, or move the ticket by hand, when
  one of those is in play.
- `isCrossRepository` is in step 2's field list because only the stacked route can act on it;
  [references/gh-stack-merge.md](references/gh-stack-merge.md) says what it does with it.
