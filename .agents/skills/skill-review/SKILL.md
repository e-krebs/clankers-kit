---
name: skill-review
compatibility: >-
  Best with Matt Pocock's writing-for-agents skill (conventions source; writing-great-skills before
  its v1.1) and a skill lint runner named by SKILL_LINT_RUNNER installed; both have inline
  fallbacks below.
description: >-
  Review a skill or every installed skill for authoring quality: description triggers,
  completion criteria, leading words, no-ops, lint score, cross-references. Use when the user
  asks to review, lint, audit or improve a skill, or after creating or editing one. Not for
  code or memory review.
---

# skill-review

The hygiene gate for skills: review the target skill(s) against the authoring conventions,
fix what the user approves, and hold each at the lint bar. Run it on one skill after creating
or editing it, or over every installed skill as an audit. Two arguments let a parent audit
split the run: `gather` stops after step 4 with the findings and scores and asks nothing, and
`apply <path>` reads the approved findings from the rows of that file whose sub-topic is
`skills`, skips step 5's interview, applies them and re-runs step 4. With no argument, every
step runs.

## Steps

1. Load the conventions: Read `~/.agents/skills/writing-for-agents/SKILL.md` plus its
   `SKILL-MECHANICS.md`, or, on an older install, `~/.agents/skills/writing-great-skills/SKILL.md`
   plus its `GLOSSARY.md` when a bold term needs its full definition — a user-granted named
   dependency; the Skill tool cannot invoke it (the skill sets `disable-model-invocation`). If
   neither file is present, the inline checklist in step 2 is the gate. Done when the conventions
   are in context.
2. Review each target skill against the checklist, quoting the offending line per finding.
   This checklist is the gate; writing-for-agents owns the vocabulary:
   - Description: triggers only (identity lives in the body), the leading word front-loaded,
     one trigger per branch, a negative ("not for...") present, under 300 chars.
   - Invocation: model-invoked only if the agent or another skill must reach it on its own;
     otherwise `disable-model-invocation: true` and a human-facing one-liner.
   - Steps end on a checkable completion criterion.
   - Progressive disclosure holds — grade it with the rubric below, one verdict per section of
     the target skill.
   - Hunt no-ops, duplication, sediment, sprawl, negation-steering; hunt passages a leading
     word would collapse.
   - Overconstraint: a rigid "never/always" that is not safety-critical, where an intent
     statement plus the model's judgment would do → relax it (worst-case rules written for
     older models over-constrain newer ones).
   - Cross-surface duplication: the same guidance in the skill AND in CLAUDE.md, a hook
     message, or a tool description → one owner keeps it.
   - Examples where interface would do: a usage example that a sharper step name, parameter,
     or enumerated status makes redundant → cut it; prefer a runnable check or real code over
     a prose rubric where one exists.
   - Frontmatter parses; `evals/evals.json` exists and parses (a step-bearing skill without
     one is a finding; a pure-reference skill earns at least one diagnosis eval).
   Done when every target has a findings list (or an explicit clean verdict).
3. Cross-reference check: grep each target's authored text for other installed skills' names.
   A hit is a finding unless the user granted that dependency explicitly and the text states a
   fallback. Runtime naming (in questions, reports) is always fine. Done when every hit is
   classified granted-or-finding.
4. Score: run the lint runner named by `SKILL_LINT_RUNNER` when that variable is set (for
   example `bash "$SKILL_LINT_RUNNER" .agents`, passing the PARENT of `skills/`; passing
   `.agents/skills` silently scores 0 skills as an A). The bar is 80%+. A run is valid only when its skills-checked count equals the
   number of target skills — a missing summary or a lower count means the runner aborted
   mid-run (it dies silently on some inputs); score the missing skills via per-skill symlink
   dirs in the scratchpad. If the runner is absent, step 2's checklist is the gate and say so
   in the report. Done when each target's score is recorded from a valid run.
5. Fix: propose the findings through `AskUserQuestion` (batch related ones), apply what the
   user approves, re-run step 4 on changed skills. Under `apply <path>` the approvals come from
   the file and no question is asked; under `gather` this step does not run. Done when every
   applied fix holds the bar and the report shows before → after scores per skill.

## Progressive-disclosure rubric

Grade each section of the target skill; every failed row is a finding naming the section.
When rows 2 and 3 both fire on one block, row 2 wins — a block every branch needs stays
inline; row 3 fires only on branch-specific reference. On a reference-only skill (no step
sequence), rows 3 and 5 read differently: row 3 is N/A, and row 5 asks whether the first
screen carries the taxonomy instead of a process skeleton.

| Criterion | Checkable question | Verdict when it fails |
| --- | --- | --- |
| Branch test | Does every invocation path read this section? | No → disclose to `references/` |
| Inverted disclosure | Does every run need this `references/` file? | Yes → hoist it inline |
| Steps vs reference | Is a flat reference block (table, worked example, API detail) sitting inside the step sequence? | Yes → disclose; steps stay inline |
| Pointer wording | Does each pointer say WHEN to load its file, and is the file named for what it holds? | No → reword the pointer |
| First screen | Do the first ~40 lines carry the whole process skeleton? | No → push detail down or out |
| Size signal | Body over ~200 lines, or over 8 code blocks, with no `references/`? | Yes → find the disclosure cut |
| Co-location | Do a concept's definition, rules, and caveats sit under one heading? | No → regroup them |
| Sequence cut | Do post-completion steps tempt a rush past the current one? | Yes → sharpen the criterion first, then split |

## Gotchas

- Accepted lint warnings, not bugs: `description too long` when the triggers genuinely need
  the space; `body >200 lines with no references/` on a reference-style skill (try the trim
  first); the frontmatter trigger/negative checks on a `disable-model-invocation` skill (its
  description is human-facing by design); `missing gotchas section` when a `## Failure modes`
  section holds that content.
- A skill published to a marketplace channel keeps the ABSOLUTE no-cross-reference rule — the
  granted-exception clause applies only to personal skills co-versioned in one repo.
