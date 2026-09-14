# Stacked PRs (`gh stack`)

Verified against `gh stack` v0.1.0.

You are here because the profile's PR shape row carries `gh stack for a multi-PR change`.
`gh stack view --json` either listed more than one member for this branch, listed one, or failed
outright — and in the last two cases F1's walk settles whether a stack exists anyway.
`gh stack submit` and `gh stack push` both
republish **every** active branch in the stack, so this run owns every member's checks and not
only the ones on the branch the user is standing on.

This file replaces SKILL.md's Step 0 PR resolve and its Steps 2 and 3. Step 1's gate still runs,
over F2's summary. Step 4's red path still runs, with the failing member named. Every `gh stack`
invocation and every PR-graph query this skill may run is here.

## F1 — Enumerate the members (read-only)

Take from `gh stack view --json`, bottom to top: each member's branch, its PR, and whether it reads
merged, queued or open. Read the actual keys — the names are `gh-stack`'s, not this skill's. Then,
per member PR, the field set Step 0 uses for one PR plus the two the stack needs:

```
gh pr view <n> --json number,state,isDraft,url,title,body,reviewDecision,latestReviews,reviewRequests,headRefName,baseRefName,isCrossRepository,statusCheckRollup
```

- Set aside the members the view marks merged or queued and any PR reading `MERGED` or `CLOSED`:
  there is nothing to advance there, and the push skipped them.
- Set aside any member whose `isCrossRepository` is true. That `headRefName` names a branch in a
  fork, and nothing here may act on it. Name the ones you set aside.
- No member has a live PR ⇒ exit silently, exactly as Step 0's no-PR rule.
- **The bottom open member** is the lowest live member — the one whose base is the trunk, or whose
  base is a member that has already merged. It is the only member F4 advances, and every report
  orders the stack from it upwards.

`gh stack view` resolves membership from **local tracking only**, so a stack `gh stack link` created
is invisible to it. Where it listed a single member, or failed outright, walk the PR graph instead.
A failure left no member list at all, so resolve the current branch's PR first — the field set
above, not Step 0's, because the walk needs `baseRefName` and `isCrossRepository` that Step 0's
query omits, and with Step 0's silent exit, because no live PR means nothing to walk and nothing to
advance — and take the trunk from the profile's Default branch row. That PR's own `baseRefName` and
`headRefName` are then the walk's two starting points.

<!-- The three walk rules below are mirrored from the rebase capability's own cascade reference,
     sentence for sentence, so a diff across the two files catches drift. -->

Ask the PR graph, read-only, with **filtered** queries and no repo-wide scan — `gh pr list`
fetches 30 items by default, and an unfiltered listing on a busy repo silently misses the very PRs
that matter:

```
gh pr list --state open --base <b>               # what is stacked on <b>
gh pr list --state open --head <its baseRefName> # what <b> is stacked on
```

each carrying `number,url,headRefName,baseRefName,isCrossRepository`. Then **walk the chain in both
directions until nothing new appears**, one branch at a time. Run the `--base` query **even when
this PR's own base is the trunk**: that is the bottom-of-stack case, where a base test alone finds
nothing while children sit above. **Skip a `--head` query whose value is the trunk**: a repo
carrying a standing open trunk-to-release PR would otherwise make every ordinary PR look like a
chain. **Drop the cross-repo PRs.** `isCrossRepository` true means `headRefName` names a branch in
a fork, which is not a local branch and nothing here may act on it. Name them and exclude them. A
walk that finds no chain ⇒ close this file and take Step 0's single-PR path.

Done when the member list is in hand bottom to top, each with its PR JSON, the bottom open member is
identified, and the merged, queued and cross-repo members are set aside and named — or the silent
exit fired.

## F2 — What the gate offers

Step 1's one offer, widened to the stack, so the user authorizes a stack-wide chain rather than one
PR's:

- The stack bottom to top: each live member's PR number, its draft state, and its CI status now.
- The watch: every live member's checks, not only the current branch's.
- The green action, which is the **bottom open member's alone** — Step 0's rules applied to that one
  PR, so a draft gets marked ready, or an open PR's submitted reviewers get re-requested. Say
  plainly that the members above it stay as they are: a stack is reviewed bottom-up, and their bases
  still move when the one below lands.
- **One** tracker move, the bottom open member's ticket, as Step 1's second and independently
  declinable question. Name the other members' tickets in the same breath and say each moves when
  its own PR reaches review. A question that moved every ticket in the stack would move tickets
  whose PR nobody can review yet.

Done when the user picks Proceed, or declines.

## F3 — Watch every member

One `gh pr checks <n> --watch` per live member, without `--fail-fast`, launched as background Bash
tasks in a single round; the harness re-invokes as each exits. A stack push re-runs CI on every
branch, and a member two down going red is the failure that matters most — watching only the current
branch reports green straight over it.

Then Step 2's distrust, **per member**: after each watch exits, pause a few seconds and re-gather
that PR's `statusCheckRollup`; re-watch when anything is still pending, new checks appeared, or the
set looks suspiciously thin. A member is done only at a terminal state, so a pending check keeps the
loop running rather than falling through to F4.

Done when a fresh `gh pr view` shows every live member's checks in a terminal state.

## F4 — Advance the bottom open member

Green means **every** live member's checks reached a terminal success. A pending check is not green
and blocks exactly as a red one does.

Then, for the bottom open member only, run Step 3 as written: `gh pr ready <n>` for a draft,
reporting who the forge auto-requested; `gh pr edit <n> --add-reviewer <login>` for an open PR's
submitted reviewers; or the reviewer question where it has none. Then the single tracker move,
best-effort, per the profile's `## Tracker rules`.

The members above are reported, not advanced: name each by number with its state, and say the stack
is reviewed from the bottom, that each one's turn comes when the PR below it merges, that the merge
capability restacks them then, and that this skill's next run advances whichever has become the
bottom.

Red or pending on any member ⇒ Step 4, naming which member failed and on what, and nothing is
advanced anywhere: a green member above a blocked one is still blocked by it, and no tracker move
happens.

Close by naming the next step: the merge capability lands the bottom PR once its review lands, and
the stack follows from there.

Done when the bottom open member's green action and, where it applies, its one tracker move have
both been attempted, every member above is reported by number, and the next step is named.
