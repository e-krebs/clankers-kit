---
name: hooks-review
description: >-
  Audit, prune or extend the hooks layer. Use when the user asks to review, prune or audit their
  hooks, or asks what should become a hook. Not for editing one hook, the memory store, or code
  review.
disable-model-invocation: true
---

# hooks-review

Review the standing hooks: the shared scripts under `~/.claude/hooks/`, the
skill-owned ones under `.agents/skills/*/hooks/`, their `hooks.json` fragments, the composed
wiring in `.claude/settings.json` and `.codex/user-hooks.json`, and the inline entries there.
Prune what drifted, then propose what the evidence says should become a hook. The user decides
every verdict through `AskUserQuestion`. Two arguments let a parent audit split the run.
`gather` stops after phase 3's candidate table with flags and recommendations and asks nothing.
`apply <path>` reads the verdicts from the rows of that file whose sub-topic is `hooks`, skips
the two interviews and the closing chain, and ends on the closing report. With no
argument, every phase runs.

## Phase 1: inventory (three read-only workers, in parallel)

Launch three read-only workers in one message, one per packet of
[references/inventory-prompts.md](references/inventory-prompts.md): wiring and triggers, prose
against hooks, history and signals. Pass each worker that path and its packet heading rather
than loading the file here. Each packet names the evidence format it returns. Treat the reports
as leads, and reopen the cited lines behind a flag before it reaches a question.

Done when every hook has a row in the first and third report, every suite has a PASS or FAIL
result, and the second report holds its three lists (redundant, unenforced, contradictory) plus
the dead references.

## Phase 2: prune interview

Load the prune flags in [references/lenses.md](references/lenses.md) and assign each hook its
flags and a recommended verdict. Under `gather` or `apply`, skip the interview below. The
flags go into the returned table, or the verdicts come from the file. Otherwise ask through
`AskUserQuestion`, flagged hooks first, batched by theme (removals, relaxations, fixtures).
Each option carries the evidence and a recommendation, and the recommended option comes first
with "(Recommended)". Verdicts: keep · drop · relax (a rule goes) · scope (a rule
fires only under a condition) · add-fixture · merge-into (fold into a named sibling). When the
user asks for a recommendation on one rule, name the mechanism the rule protects and the cost of
each side, then recommend one.

Done when every hook and every inline entry holds a verdict, or under `gather` its flags and a
recommended verdict.

## Phase 3: suggest

Load the suggestion sources in [references/lenses.md](references/lenses.md) and build one
candidate table from all five, one row per candidate: rule, evidence and count, event and
matcher, field and regex, cost. Sources 2 and 4 come from the phase 1 reports. Hand sources 1,
3 and 5 to one read-only worker that returns rows in that shape, so no memory or transcript
text reaches this context. Rank by evidence count, mechanical rows above judgment rows.
A judgment row leaves the table with a one-line reason. Under `gather`, stop here, return the
hook table and the candidate table, and ask nothing. Under `apply`, take the candidate verdicts
from the file. Otherwise ask through `AskUserQuestion`, up to four candidates per call, options
add · skip · later. In either mode, each add becomes a brief at `~/.claude/plans/hook-<slug>.md`
written from [references/brief-template.md](references/brief-template.md), never a hook built
in this run.

Done when every mechanical candidate holds a verdict and every add has a brief path, or under
`gather` a ranked row with a recommended verdict and no brief written.

## Phase 4: apply the prune

Each rule change ships with one fixture case. Dropping a hook removes its entry in the owning
`hooks.json` fragment (then rerun the composer with the command in `README.md`, which rewrites
both wiring files), its marker family in the session cleanup hook, and its README line.
Before committing a skill edited by a prose verdict, run the hygiene gate on it. That means the
`skill-review` skill, a user-granted exception to the no-cross-reference rule, or, when that
skill is absent, the repo's authoring conventions and lint bar. Under `apply`, run
that gate to its diagnosis and scoring only, and hand any new finding back in the closing report
for a later approval, so the run still asks nothing. Commit per concern with a scoped
conventional message, by pathspec, so a parallel agent's files stay out.

Done when every verdict is applied, `bash .agents/hooks/run-fixtures.sh` passes (its
`compose-hooks` suite fails on a stale wiring file), and `jq -e .` passes on both wiring files.

## Closing report

Two tables: per hook the verdict and its commit, per candidate the verdict and its brief path.
Then the suites run and the commit range. Under `apply`, this report is the last output, and the
parent merges it into its own.

Done when both tables hold every verdict from phases 2 and 3.

## Closing chain (skipped under `apply`)

Run an independent adversarial review with a DIFFERENT model over the commit range plus the two
verdict tables: `codex exec --sandbox read-only` when codex is on the path and the parent is not
Codex itself, else a Claude reviewer. Its checklist: every decided drop is gone, every keep is
untouched, every rule change has its case, and the new hook code is sound. Apply its
high-confidence findings as a fixup commit, decline the rest with cause in the report. If codex
reports the hooks untrusted, re-trust them per the gotcha below rather than passing
`--dangerously-bypass-hook-trust`.

Close by recommending the built-in `/doctor` checkup to the user.

Done when each reviewer finding is marked applied or declined-with-cause.

## Gotchas

- Test a hook change with fixture files piped from disk (`bash hook.sh < fixture.json`). A deny
  pattern typed inline in your own command trips the live hook on that call.
- `run-fixtures.sh` runs every suite in one call and prints one line per suite; run it right
  after a hook edit.
- The hooks are symlinked live, so an edit applies to the next tool call in every open session.
- A worker in a worktree may branch from `origin/main`, not the local tip. Have it run
  `git reset --hard main` first, and cherry-pick its commit onto main afterwards.
- Codex trusts hooks per definition hash. After a wiring edit, run `/hooks` once in an
  interactive `codex`. A script edit needs no re-trust.
- The event log keeps at least the last 30 days (it trims only past 500 lines). A silent rule
  is "no signal yet", not dead, while the log or the rule itself is younger than 30 days.
- The prose that a Claude hook also enforces stays in `AGENTS.md`, because Codex and Cursor
  read it without the Claude hooks.
- This skill's own files and the compose-hooks suite are in scope every pass.
