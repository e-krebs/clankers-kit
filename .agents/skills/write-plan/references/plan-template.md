# Plan template

Six `## ` headings follow the header, in this order and spelled exactly as below, because a hook
parses them. Each hint below names its section's reader. The plan shows the reader through
section order and folding only. Replace each hint with content and keep the heading texts.

````markdown
# Plan: <one clause naming the change>

Source: <brief path | the request in one line>. <Who decided what.>
Ticket: [<KEY>](<absolute URL>), <status> | none, <reason>.
Repo: <absolute path of the repo root>.
Size: <small | medium | large>.
Attachments: [<name>](<absolute path>) for <its reader>. <Omit the line when there are none.>

## Summary

<For the user. Why, the approach and the outcome, in at most five sentences.>

## Decisions

<For the user and the running session. The agent's decisions first, one line each: the choice, the fact
behind it, and `(agent)`. They stay unfolded, because the user vetoes from this list.>

- <the choice>, <the fact behind it> (agent)

<details><summary>Your decisions (<n>)</summary>

- <the choice>, <the fact behind it> (you)

</details>

## Steps

<For the user and the running session. One table. Files, the last column, lists literal paths (globs allowed) or `—`. Tier is
a tier name from `~/.agents/workflow-models/tiers.md`: a worker row's name, or `<tier of the running session>` on a row the running session does itself, never the tier of the plan writer. After is `—` or row ids. Done when is one
backticked shell command with no `|` character (the row parser splits cells on it; chain with `&&`, and put a pipeline in a script file that the command runs), except Approval and Hand-off, which hold text. A new plan holds `➖` in every State cell, the first column.>

| State | # | Task | Tier | After | Done when | Files |
| --- | --- | --- | --- | --- | --- | --- |
| ➖ | S0 | Refresh the base | <worker tier> | — | `<base check command>` | — |
| ➖ | S1 | <task> | <tier> | S0 | `<command>` | `<path>` |
| ➖ | S2 | Review: `/<review skill>`, <tier> tier × <count> | <tier of the running session> | S1 | `test -f "<absolute plan path>"` | working tree |
| ➖ | S3 | Gates: the Done when check, then the browser pass when the profile has one | <worker tier> | S2 | one of: `<one command>` / `bash "<absolute plan stem>.briefs/gates.sh"` / `test -f "<absolute plan path>"` | — |
| ➖ | S4 | Approval: the user reviews the working tree | <tier of the running session> | S3 | the user's go-ahead | — |
| ➖ | S5 | Hand-off: `/<pr skill>` with <KEY> | <tier of the running session> | S4 | the PR skill ran | — |

## Run

<For the user and the running session. One line: the tier of the running session, its model and the effort.>
In a new terminal:

```
claude --agent <tier of the running session> "/execute-plan <absolute path of this plan file>"
```

On Codex, the fence holds one launch line instead:

```
codex -m <model> -c model_reasoning_effort=<level> "Execute the plan at <absolute path of this plan file>"
```

Run rules: `<absolute path of references/run-rules.md in the execute-plan skill folder>`. The running session reads that file before the first row.

## Plan review

<For the user. One line per reviewing agent: who, when, the findings count, and what changed.
Name an agent, because the gate checks for one. A re-review after an edit adds a line.>

## Briefs

<For the workers, and for the running session on its own rows. One brief file per row whose Tier is not
`<tier of the running session>`, in the briefs folder beside this plan, named `S<n>.md`. A row at that tier may have one too.
Each file holds at most 25 lines and no heading. On Codex Plan mode, which forbids writes, this section holds the inline
form instead: one fold per row, with its `### S<n> <title>` heading inside the fold.>

Briefs: <absolute path of this plan without `.md`>.briefs/, one file S<n>.md per delegated row.

- [S<n> <row title>](<absolute path of its brief file>)
````

## The header

- `Ticket:` holds the key that later rows use. The Hand-off row passes it to the PR skill, which
  writes it into the PR body. The tracker's move to review then reads the key from the PR body.
- `Repo:` is the root that the run rules' dispatch prompt names, so a worker knows where to work.
- `Attachments:` lists one absolute link per attachment, with the reader it serves.

## Folding

A fold is `<details><summary>…</summary>`, a blank line, the content, a blank line, then
`</details>`. The blank lines let the markdown inside render. One thing folds by default: the user's
decisions, under `Your decisions (<n>)`. Briefs are files, so they do not fold. Only the inline form of the Briefs section folds them.

The agent's decisions, the Steps table and the Run fence stay in view.

## Steps

- State is `➖` (open), `▶️` (in progress) or `✅` (done).
- S0 is the kickoff row when one is needed. It refreshes the base branch when the profile has a
  remote, and it carries any tracker write that plan mode refused, at Tier `<tier of the running session>`.
- A row's Tier is `<tier of the running session>` only for an external write, a subagent fan-out
  or a user errand. A worker cannot spawn subagents. Every other row goes to a tier agent with its
  own brief.
- Rows that are ready together never share a file.
- Rows with the same tier whose files overlap merge into one row.
- The last four rows are always Review, Gates, Approval and Hand-off, in that order, and each
  Task cell starts with the row's name:

| Row | Tier | What it does |
| --- | --- | --- |
| Review | `<tier of the running session>` | runs the review skill, and its Task names that skill and `<tier> tier × <n>` |
| Gates | a worker tier | runs its Done when, then the profile's Browser check steps when that row is not `—`. Its report's `check:` line holds only the failing lines. Its Done when follows the block below |
| Approval | `<tier of the running session>` | stops and asks the user through the question tool whether to hand off or to take feedback |
| Hand-off | `<tier of the running session>` | invokes the PR skill with the ticket key when there is one |

- Gates Done when, by the Verify commands row (`<plan stem>` is the plan file's name without `.md`).
  Paths in the Done when are absolute, because the plan's directory is not the run cwd. A plan
  path with a space is quoted in the cell (`bash "<path>"`, `test -f "<path>"`), which the one
  backticked span still holds. Only an empty `--verify-commands` output from a working resolver counts as
  `—`. A missing resolver (exit 127) stops the plan with the reason. Exit 1 asks for the facts instead.
  - The commands come from the resolver's `--verify-commands` output, one `<dir><TAB><command>`
    line each, with an empty dir when the row has none. Never split the row yourself.
  - One command: that command, verbatim, with no backtick pair doubled in the cell. It has no
    `;`, `|`, `$(...)`, backtick or single quote, and no dir. A plain `&&` chain counts.
  - Any other output: a script `<plan stem>.briefs/gates.sh`, with Done when
    `bash "<absolute path of that script>"`. It starts `rc=0`, runs each command as
    `<cmd> || rc=1` and ends `exit $rc`. Every command runs and any failure exits non-zero.
  - No bare `set -e` covers the script. It would stop at the first failure, and the profile may
    ask to run every step and report all failures.
  - A command with `;` or `|` runs as `bash -o pipefail -ec '<cmd>' || rc=1`. A `set -e` in a
    `( )` subshell is ignored under `||`, which would hide a failing first part. A pipeline needs
    `pipefail` to fail on its first stage.
  - A command with a single quote or a literal backtick goes into the script through a quoted
    here-doc (`<<'X'`), which keeps both literal. The cell then holds the script path as its one backticked command.
  - A dir is relative to the repo root and binds every command, always, because a
    later session runs the plan from the repo root. A plain command runs as
    `(cd <absolute Repo>/<dir> && <cmd>) || rc=1`. A `;` or `|` command runs as
    `(cd <absolute Repo>/<dir> && bash -o pipefail -ec '<cmd>') || rc=1`. The `||` sits outside
    the parentheses, so a failure of the cd or the command sets `rc=1` and the script exits
    non-zero.
  - The script is written in step 8 with the Gates row. On Codex Plan mode, which forbids
    writes, add a build row just before Review, so the last four rows stay Review, Gates,
    Approval and Hand-off. It is a worker row whose inline brief holds the script text and whose
    Done when is `test -s "<absolute plan stem>.briefs/gates.sh"`. Gates lists it in After.
  - `—`: `test -f "<absolute plan path>"`, which passes in every mode, inline briefs included.
    The check's own report is written by the session after the worker returns, so a `test -s`
    on it would fail. The brief tells the worker to report that the profile lists no checks.
  - The Gates brief tells the worker to save each check's output to a file and read only the
    failing lines. The script can outlast a 10-minute foreground call, so the worker may run it
    in the background and read its output file.
- The Hand-off row's brief file carries the recommended commit split and any file to leave out, as a
  hint. The PR skill owns every commit and push, and keeps its own approval of the split, the
  branch and the PR body.
- A file change after the Gates row is `✅` resets Gates
  and Approval to `➖`.
- On feedback at the Approval row, the running session inserts fix rows before the Review row and adds them
  to the After cells of Review and Gates. A fix row carries the feedback in its Task cell and
  needs no brief. The running session then resets Gates and Approval to `➖`, and Review too when the fixes
  change more than 20 lines in all.

## Run and Briefs

- The Run section follows step 7 of SKILL.md. The gate denies any fence line other than the two
  launch forms in the template above.
- The plan does not copy the run rules. The Run section's last line names the run rules file by
  its absolute path, and the gate denies a Run section without it.
- The Briefs section lists each brief file as a markdown link, one bullet per delegated row after the pointer line, so the user can open it. A bullet holds the link and nothing after it: no summary, because the brief file holds the content.
- Every delegated row has a brief file, S0 and Gates included. A brief file is at most 25 lines and has no
  heading. A row at the running session's tier needs none.
- A spec that two or more briefs share, such as the same steps, rules or test list, goes in one
  markdown attachment named in the `Attachments:` line. Each brief links it by absolute path and
  holds only what differs, such as paths and the Done-when check. A build row writes the attachment
  before the first row that reads it.
- A brief stands alone. A worker with no chat context can do the row from the brief, its row
  line and the files it links. A worker on a tier below the ones for cross-component changes and
  for judging a diff reads no other section of the plan.
- A `Provider: codex` or `Provider: claude` line in a brief's first line pins that row to the
  named provider. Rows without one are routed when the plan runs.

## Rules the template carries

- Write every step as a step. No step reads "default yes" and no step is an offer. The user
  deletes the steps they decline before approving.
- No row commits or pushes. A row phrased as a commit invites committing before any reviewer
  has seen the work, so the split lives in the Hand-off brief.
- Fill the `/<...>` placeholders by name, in every section, from the skills installed in the
  session that writes the plan. The template itself names none.
- The tables in a plan keep a source line when their numbers come from somewhere, such as a
  command, a query or a transcript.
- Every link in a plan and in its attachments uses an absolute path.
- HTML exists only as an attachment, in the cases that
  [html-rendering.md](html-rendering.md) lists. The markdown stays the plan.
