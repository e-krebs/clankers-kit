---
name: verify
description: >-
  Run every check the repo's workflow profile lists, in parallel, and report one verdict each
  with every failure quoted. Use when asked to verify, run the checks, confirm green before
  a PR, or after a broad refactor. Not for a single test file or a targeted lint run.
---

# verify

The gate between a finished implementation and a review: the repo's own checks, all of them,
one run. The workflow profile names them, so the commands come from the profile rather than
from a guess at the package scripts.

## Steps

1. Read the profile. The session-start hook injects the resolved rows into context under a
   "Workflow profile resolved" header. When those rows are absent from context, run
   `bash ~/.agents/skills/workflow-profile/scripts/resolve-profile.sh --rows` and read its
   table.
   Take three things: the Verify commands, the working-directory prefix that opens that cell
   (`<dir>: <commands>`, the commands themselves separated by `, `), and the Browser check row.
   Two conditions end the run here:
   - The Verify commands row is missing or `—`: report that this repo's profile lists no checks,
     point at the profile setup capability to add them, and stop.
   - The prefix names a directory that is not the session cwd: run the commands from that
     directory when the harness lets you change directory. When it refuses (a hook may deny
     `cd` or `--cwd`), report the mismatch and stop; the remedy is reopening the session with
     that directory as the workspace root.
   Done when the command list, its directory and the Browser check row are in hand, or the run
   has stopped with one of those two reasons stated.
2. Launch every command in one message, one background Bash call each, a 10-minute timeout each,
   output redirected to the session scratchpad: `<command> > <scratchpad>/verify-<n>.log 2>&1`,
   numbered in the order the row lists them. Wait for all of them to finish, then read each log
   and grep it for the failure. A command that hits the timeout counts as timed-out, not failed,
   and its log is partial. Done when every command carries an exit status or a timeout and every
   log is on disk.
3. Run the browser pass when the profile carries a Browser check and the plan's Verification
   section calls for one. A behavioral change (handlers, hooks, API calls, state, endpoints)
   needs the network requests and the console read through the browser tooling the session
   offers; a pure-visual change (copy, classNames, layout) needs a screenshot. The Browser check
   row holds `<dir>: <dev server command> → <base URL>`: start that server as a background Bash
   call, and take the page path from the plan. With no plan in context, ask whether a browser pass is wanted — through the
   harness's question tool when it has one, else in prose — and follow the answer. Done when the
   pass carries a verdict, or the report records it as not called for.
4. Report one line per check: the command, its verdict of passed / failed / timed-out, and for a
   failure every failing test name, lint rule or `file:line` quoted from its log, up to ten per
   check, then the count of the rest. A log path alone is not a report. Close by naming the next steps in order — the review capability over
   the working tree, then the PR capability — unless a check is red, in which case the fix comes
   first. Done when every check and the browser pass carry a verdict, every failure quotes its
   offenders, and the next step is named.

## Gotchas

- Re-reading a log is free; re-running a full suite costs minutes and burns the prompt cache.
- A cell with no `<dir>:` prefix runs in the session cwd, which is the common case. The prefix
  binds every command in that cell, not only the first.
- A clean tree is not a reason to skip: the checks run whenever the run was asked for, because
  a red base is worth knowing before the work starts.
- The run after a timeout raises the timeout rather than chasing a phantom failure.
- Reviewers reading a red tree spend their findings on the breakage, so the fix lands before the
  review capability starts.
