---
name: verify
description: >-
  Run the repo's workflow-profile checks. Use when asked to verify, run the checks, confirm green
  before a PR, or after a broad refactor. Not for a single test file or a targeted lint run.
---

# verify

Runs every check the workflow profile lists, in parallel, one verdict each. The commands come
from the profile, never from a guess at the package scripts.

## Steps

1. Read the profile. The session-start hook injects the resolved rows into context under a
   "Workflow profile resolved" header. When they are absent, run
   `bash ~/.agents/skills/workflow-profile/scripts/resolve-profile.sh --field "Browser check"`; empty output
   means the row is `—`. Always read the checks from
   `bash ~/.agents/skills/workflow-profile/scripts/resolve-profile.sh --verify-commands`. It prints one
   `<dir><TAB><command>` line per command and nothing for `—`. A non-empty dir binds every
   command; with none, they run in the session cwd. When the script is missing, say the profile
   setup is missing and stop.
   Two conditions end the run here:
   - The `--verify-commands` output is empty (row missing or `—`): report that this repo's profile lists no checks,
     point at the profile setup capability to add them, and stop.
   - The prefix names a directory that is not the session cwd: run the commands from that
     directory when the harness lets you change directory. When it refuses (a hook may deny
     `cd` or `--cwd`), report the mismatch and stop; the remedy is reopening the session with
     that directory as the workspace root.
   Done when the command list, its directory and the Browser check row are in hand, or the run
   has stopped with its reason stated.
2. Launch every command in one message, one background Bash call each, a 10-minute timeout each:
   `<command> > <scratchpad>/verify-<n>.log 2>&1`, numbered in row order. The scratchpad is the
   harness's scratch directory, else `mktemp -d`. Wait for all of them. Never read a log whole:
   for a failed command, grep its log for the offenders (failing test names, lint rules,
   `file:line`), and fall back to its last 40 lines when the grep finds nothing. A passed log
   stays unread. A command that hits the timeout counts as timed-out, not failed, and its log is
   partial. Done when every command carries an exit status or a timeout.
3. Run the browser pass when the profile carries a Browser check and the plan's Gates row, or
   its brief, calls for one; read [references/browser-check.md](references/browser-check.md) then.
   With no plan in context, ask whether a browser pass is wanted, through the harness's question
   tool when it has one, else in prose. Done when the pass carries a verdict, or the report
   records it as not called for.
4. Report one line per check: the command, its verdict of passed / failed / timed-out, and for a
   failure every offender quoted from its log, up to ten per check, then the count of the rest.
   A log path alone is not a report. Close with the next steps in order: the review capability
   over the working tree, then the PR capability. When a check is red, the fix comes first,
   because reviewers reading a red tree spend their findings on the breakage. Done when every
   check and the browser pass carry a verdict, every failure quotes its offenders, and the next
   step is named.

## Gotchas

- A clean tree is not a reason to skip, because a red base is worth knowing before the work starts.
- After a timeout, re-run that one command alone in a later run, with a longer timeout where the
  harness allows one. A partial log is not evidence of a failure.
