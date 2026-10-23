# Plan — stop the widget importer from dropping empty rows

Source: the request in one line. The user picked the lighter fix.
Ticket: none, because the acme profile names no ticket system.
Repo: /Users/example/widgets.
Size: small.

## Summary

The importer drops a row whose cells are all empty, so the counts drift. The fix keeps the row and marks it empty. One worker edits the importer and its test.

## Decisions

- Keep the empty row and mark it, because the export expects the same count (agent).

<details><summary>Your decisions (1)</summary>

- Use the lighter fix, because the heavier one rewrites the parser (you).

</details>

## Steps

| State | # | Task | Tier | After | Done when | Files |
| --- | --- | --- | --- | --- | --- | --- |
| ➖ | S0 | Refresh the base | __TIER_FIRST__ | — | `git merge-base --is-ancestor origin/main HEAD` | — |
| ➖ | S1 | Keep empty rows | __TIER_B__ | S0 | `yarn test` | `src/import.ts`, `src/import.test.ts` |
| ➖ | S2 | Review: the review skill, __TIER_A__ tier × 1 | __RUN_TIER__ | S1 | `test -s /Users/example/.claude/plans/widget-import.briefs/S2.report.md` | working tree |
| ➖ | S3 | Gates: run the checks | __TIER_A__ | S2 | `yarn verify` | — |
| ➖ | S4 | Approval: the user reviews the working tree | __RUN_TIER__ | S3 | the user's go-ahead | — |
| ➖ | S5 | Hand-off: the PR skill | __RUN_TIER__ | S4 | the PR skill ran | — |

## Plan review

- claude, __TIER_A__ tier subagent: 2 findings, both folded.

## Briefs

<details><summary>S0 Refresh the base</summary>

### S0 Refresh the base

Fetch origin main and fast-forward when behind. Return at most 3 lines.

</details>

<details><summary>S1 Keep empty rows</summary>

### S1 Keep empty rows

Edit `src/import.ts` so an all-empty row is kept and marked. Add a test case. Done when `yarn test` passes.

</details>

<details><summary>S3 Gates</summary>

### S3 Gates

Run the checks the profile names. Return PASS or FAIL per check.

</details>
