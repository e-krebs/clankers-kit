---
name: execute-plan
description: >-
  Run an approved plan file row by row: check the session's model, dispatch rows to workers, set
  the State cells and end with a worker count. Use when the user asks to execute, run or resume a
  plan, or types /execute-plan with a plan path. Not for writing a plan, or for reviewing code.
---

# execute-plan

Entry: `/execute-plan <absolute plan path>`.

The plan file is the only input. It holds the Steps table, the Run block and the briefs of the
delegated rows. The rules for the run are in [references/run-rules.md](references/run-rules.md),
read by the running session before the first row.

## Steps

1. Read the plan file's lines above `## Briefs`: the header, Summary, Decisions and Steps. Done when
   the Steps table and the Run block are in hand.
2. Read [references/run-rules.md](references/run-rules.md) in full. Done when the seven rules and the
   start check are in hand.
3. Run the start check. Compare this session's model and effort with the rules' sources, and stop
   with both values on a mismatch. Done when the check passes, or the run stopped and reported.
4. Run the rules: rows in order, every row that is not at this session's tier goes to a worker, and the session runs only its own rows (Review, Approval, Hand-off), State
   cells set through the script only. Done when every row is `✅`, or the run stopped and reported.
5. End the last reply with the `workers:` line, in the form `workers: <n> dispatched, <m> fix`. Done when that line is the reply's last line.
