---
name: hooks-review
description: >-
  Audit the hooks layer: inventory every hook, prune what drifted, and suggest new hooks from
  evidence. Use when the user asks to review, prune or audit their hooks, or asks what should
  become a hook. Not for editing one hook, for the memory store, or for code review.
---

# hooks-review

Review the standing hooks: the shared scripts under `~/.claude/hooks/`, the
skill-owned ones under `.agents/skills/*/hooks/`, their `hooks.json` fragments, the composed
wiring in `.claude/settings.json` and `.codex/user-hooks.json`, and the inline entries there.
Prune what drifted, then propose what the evidence says should become a hook. Every verdict is
the user's through `AskUserQuestion`. Two arguments let a parent audit split the run: `gather`
stops after phase 3's candidate table with the flags and the recommendations and asks nothing,
and `apply <path>` reads the verdicts from the rows of that file whose sub-topic is `hooks`,
skips the two interviews and the closing chain, and ends on the closing report. With no
argument, every phase runs.

## Phase 1 — inventory (three read-only workers, in parallel)

Load [references/inventory-prompts.md](references/inventory-prompts.md) and launch its three
packets as read-only workers in one message: wiring and triggers, prose against hooks, history
and signals. Each packet names the evidence format it returns. Treat the reports as leads:
reopen every cited line before it reaches a question.

Done when every hook has a row in the first and third report, every suite has a PASS or FAIL
result, and the second report holds its three lists (redundant, unenforced, contradictory) plus
the dead references.

## Phase 2 — prune interview

Load the prune flags in [references/lenses.md](references/lenses.md) and assign each hook its
flags and a recommended verdict. Under `gather` or `apply`, the interview below is skipped: the
flags go into the returned table, or the verdicts come from the file. Otherwise ask through
`AskUserQuestion`, flagged hooks first, batched by theme (removals,
relaxations, fixtures), each option carrying the evidence and a recommendation, the recommended
option first with "(Recommended)". Verdicts: keep · drop · relax (a rule goes) · scope (a rule
fires only under a condition) · add-fixture · merge-into (fold into a named sibling). When the
user asks for a recommendation on one rule, name the mechanism the rule protects and the cost of
each side, then recommend one.

Done when every hook and every inline entry holds a verdict, or under `gather` its flags and a
recommended verdict.

## Phase 3 — suggest

Load the suggestion sources in [references/lenses.md](references/lenses.md) and build one
candidate table from all five, one row per candidate: rule, evidence and count, event and
matcher, field and regex, cost. Rank by evidence count, mechanical rows above judgment rows.
A judgment row leaves the table with a one-line reason. Under `gather`, stop here: return the
hook table and the candidate table and ask nothing. Under `apply`, take the candidate verdicts
from the file. Otherwise ask through `AskUserQuestion`, up to four candidates per call, options
add · skip · later. In either mode, each add becomes a brief at `~/.claude/plans/hook-<slug>.md`
written from [references/brief-template.md](references/brief-template.md), never a hook built
in this run.

Done when every mechanical candidate holds a verdict and every add has a brief path, or under
`gather` a ranked row with a recommended verdict and no brief written.

## Phase 4 — apply the prune

One rule change lands with one fixture case, and each suite runs as one Bash call. A dropped hook
takes its entry in the owning `hooks.json` fragment (then rerun `compose-hooks.sh`, which
rewrites both wiring files), its marker family in the session cleanup hook, and its README
line with it. A skill edited by a prose verdict gets the
hygiene gate before its commit: run the `skill-review` skill on it, a user-granted exception to
the no-cross-reference rule, or hold it to the repo's authoring conventions and lint bar when
that skill is absent. Under `apply`, run that gate to its diagnosis and scoring only, and hand
any new finding back in the closing report for a later approval, so the run still asks nothing. Commit per concern with a scoped conventional message, by pathspec, so a
parallel agent's files stay out.

Done when every verdict is applied, `compose-hooks.sh` reports both wiring files unchanged,
every suite passes, and `jq -e .` passes on both wiring files.

## Closing report

Two tables: per hook the verdict and its commit, per candidate the verdict and its brief path.
Then the suites run and the commit range. Under `apply`, this report is the last output: the
parent merges it into its own.

Done when both tables hold every verdict from phases 2 and 3.

## Closing chain (skipped under `apply`)

Run an independent adversarial review with a DIFFERENT model, `codex` when it is on the path
(`codex exec --sandbox read-only`), over the commit range plus the two verdict tables. Its
checklist: every decided drop is gone, every keep is untouched, every rule change has its case,
and the new hook code is sound. Apply its high-confidence findings as a fixup commit, decline the
rest with cause in the report. The shared hooks run inside that `codex exec` once trusted; if
codex reports them untrusted after a wiring edit, run `/hooks` once in an interactive `codex`
rather than passing `--dangerously-bypass-hook-trust`.

Close by recommending the built-in `/doctor` checkup to the user.

Done when each reviewer finding is marked applied or declined-with-cause.

## Gotchas

- Test a hook change with fixture files piped from disk (`bash hook.sh < fixture.json`). A deny
  pattern typed inline in your own command trips the live hook on that call.
- The session hooks deny `cd`, `cat`, `sed`, `awk`, loops and `xargs` (except grep, wc, ls) in
  typed commands. Run the suites one call each, or delegate the sweep to a worker.
- The hooks are symlinked live: an edit applies to the next tool call in every open session, so
  run the suite right after the edit, before anything else.
- A worker in a worktree may branch from `origin/main`, not the local tip. Have it run
  `git reset --hard main` first, and cherry-pick its commit onto main afterwards.
- Codex trusts hooks per definition hash: after a wiring edit, run `/hooks` once in an
  interactive `codex`. A script edit needs no re-trust.
- The event log is 30 days deep. A silent rule over a younger log is "no signal yet", not dead.
- The prose that a Claude hook also enforces stays in `AGENTS.md`: Codex and Cursor read it
  without the Claude hooks.
- This skill's own files and the compose-hooks suite are in scope every pass.
