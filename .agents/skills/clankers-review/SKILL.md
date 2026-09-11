---
name: clankers-review
description: >-
  Run the full config audit behind two gates: pick sub-topics (memories, hooks, skills,
  AGENTS.md), gather, approve each change, apply, review. Use when the user asks to review
  memories and standing rules together, or for the periodic clankers audit.
  Not for one sub-topic alone, or code review.
---

# clankers-review

Orchestrate the audits that steer every session, behind two gates. Gate 1 picks the sub-topics
before any worker runs. Gate 2 approves every change, item by item, after all gathering and
before any write. The memory and hooks halves are their own skills and run alone when typed;
here they run in `gather` mode, then in `apply` mode with the approved verdicts.

## Phase 1 — gate 1: sub-topics

Create the scratch dir `${TMPDIR:-/tmp}/clankers-review-<date>/` and record `git rev-parse HEAD`
in the clankers repo root and today's date in its `findings.md`. Then ask one multi-select
`AskUserQuestion`: which sub-topics this pass gathers. Options: memories
(the per-project memory store), hooks (the hook scripts, wiring and the new-hook suggestions),
skills (the authoring hygiene of every installed skill), AGENTS.md (the global instructions).
Nothing runs until the answer is in.

Done when the scratch file holds the commit and the date, and the selected sub-topics are known.

## Phase 2 — gather (read-only)

Run each selected gatherer, all read-only, no question asked, no file written outside the
scratch dir:

- memories: the `memory-review` skill with the argument `gather` (the Skill tool where it
  exists, else load `~/.agents/skills/memory-review/SKILL.md` and follow it). It returns per
  memory the flags, the recommended verdict and the evidence, plus its before snapshot per
  project (files and words).
- hooks: the `hooks-review` skill with the argument `gather`, the same way. It returns per hook
  the flags and the recommended verdict, plus the ranked new-hook candidates.
- skills: the `skill-review` skill with the argument `gather` over every installed skill, the
  same way. It returns per skill the findings and the lint score, none of them fixed.
- AGENTS.md: one read-only worker over `~/.claude/CLAUDE.md` (a symlink to the shared AGENTS.md) with four
  lenses: dead (the target is gone), hook-redundant (a hook enforces it, and the line serves no
  reader without that hook), contradictory (against another line, a hook or a skill contract),
  unenforced (a mechanical rule with no hook). It returns per line the flag, the quoted text
  and a fix. An unreadable file is the unavailable notice below.

A child skill whose file is absent is a notice, never a stop: say which sub-topic is
unavailable and go on with the others. Merge the returns into `findings.md`: one table with
the columns `id | sub-topic | item | flag | recommended | verdict | evidence` (verdict empty
until gate 2), then the memory snapshot as one block per project. Each applier later reads
only the rows whose sub-topic is its own.

Done when every selected sub-topic has its rows in the table, or its unavailable notice, and
the memory snapshot block is present when memories were gathered.

## Phase 3 — gate 2: approvals

Ask through `AskUserQuestion`, sub-topic by sub-topic, flagged items first, up to four items per
call, one question per item. Each option carries the résumé, the evidence and a recommendation,
the recommended option first with "(Recommended)". Verdicts per sub-topic:

- memories: keep · delete · refresh · merge · promote.
- hooks: keep · drop · relax · scope · add-fixture · merge-into; candidates: add · skip · later.
- skills: apply the fix · skip.
- AGENTS.md: apply the fix · keep the line.

Close each sub-topic with one multi-select confirm-all call for its clean set. Write every
verdict next to its row in the scratch file. Done when every row holds a verdict.

## Phase 4 — apply

Run each selected applier with the `findings.md` path; each reads only its own sub-topic's
rows:

- memories: the `memory-review` skill with the argument `apply <path>`. It applies its verdicts,
  writes the briefs its promote verdicts need, rebuilds the index, fixes the wikilinks, writes
  the review marker, commits per concern and ends on its closing report with the before numbers
  read from the snapshot block.
- hooks: the `hooks-review` skill with the argument `apply <path>`. It applies the prune
  verdicts with their fixture cases, writes one brief per approved candidate, commits per
  concern and ends on its closing report.
- skills: the `skill-review` skill with the argument `apply <path>`. It applies the approved
  fixes, re-runs its scoring step on the changed skills and reports before and after scores;
  commit per skill.
- AGENTS.md: apply each approved fix, commit once.

Every commit names its paths, so a parallel agent's files stay out. Done when every verdict is
applied and every touched suite passes.

## Phase 5 — closing chain

Run an independent adversarial review with a DIFFERENT model, `codex` when it is on the path
(`codex exec --sandbox read-only`), over the range from the phase-1 commit to HEAD plus the
verdict table. Its checklist: every decided delete or drop is gone, every keep is untouched, no
trim dropped a surviving fact, every rule change has its fixture case, and any new code is
sound. Apply its high-confidence findings as a fixup commit, decline the rest with cause. The
shared hooks run inside that `codex exec` once trusted; if codex reports them untrusted after
a wiring edit, run `/hooks` once in an interactive `codex` rather than passing
`--dangerously-bypass-hook-trust`.

Close by recommending the built-in `/doctor` checkup to the user. It covers install health,
unused extensions, version currency and permission posture, and its CLAUDE.md trim check runs
only when the user types it in a session.

Done when each reviewer finding is marked applied or declined-with-cause.

## Closing report

The verdict table by sub-topic with the outcome of each verdict (the commit it landed in, the
brief path it produced, "kept", "skipped" or "deferred"), the children's closing reports as
they returned them, the commit range, the reviewer's verdict line, and the fixup commit when
one landed. Done when every row of the table shows one of the five outcomes.

## Gotchas

- The children run their own interview and chain only when typed alone. `gather` asks nothing
  and writes nothing outside the scratch dir; `apply <path>` asks nothing, reads only its own
  sub-topic's rows, and skips the chain.
- The skill-review dependency is a user-granted exception to the no-cross-reference rule. When
  that skill is absent, the skills sub-topic falls back to the lint runner named by
  `SKILL_LINT_RUNNER` when that variable is set (for example `bash "$SKILL_LINT_RUNNER" .agents`)
  and the repo's authoring conventions, and says so. If the runner is absent, the checklist is
  the gate.
- A sub-topic the user did not pick is not gathered, even when a worker would be cheap.
- At runtime you may name any skill freely in questions and reports.
