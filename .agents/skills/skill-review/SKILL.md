---
name: skill-review
compatibility: >-
  Best with Matt Pocock's writing-for-agents skill (conventions source) and a skill lint runner
  installed. Both have inline fallbacks below.
description: >-
  Review a skill or every installed skill for authoring quality, prose tells and context cost.
  Use when the user asks to review, lint, audit or improve a skill, or after creating or editing
  one. Not for code or memory review.
---

# skill-review

The review step for skills. It reviews the target skills against the authoring conventions,
fixes what the user approves, and keeps each one at or above the 80% lint threshold. Run it on
one skill after creating or editing it, or over every installed skill as an audit. Two
arguments let a parent audit split the run. `gather` stops after step 4 with the findings and
scores, and asks nothing. `apply <path>` reads the approved findings from the rows of that file
whose sub-topic is `skills`, runs step 1, skips steps 2-3 and step 5's interview, applies the
findings and re-runs step 4. With no argument, every step runs.

## Steps

With no argument or `gather`, and two or more targets or one target over ~150 lines or with
`references/`, read [references/audit-fan-out.md](references/audit-fan-out.md) first. It moves
steps 1-3 into one subagent per target.

1. Load the conventions. Read `~/.agents/skills/writing-for-agents/SKILL.md` plus its
   `SKILL-MECHANICS.md`. This is a user-granted named dependency. Read it by path, because it
   is hidden from model invocation. If the file is absent, the checklist below is the gate. Then look up the prose rules:
   the installed skill whose description leads with cutting AI writing tells. Look in the
   session's skill list first. A skill hidden from model invocation can be missing from that
   list, so on no match, search the frontmatter descriptions of `~/.agents/skills/*/SKILL.md`
   for "AI tells". Skip this skill and any skill that names another task first. Record the
   result as the prose source: the match's path, or `fallback checklist` plus why (no match, or
   the tied paths). Read the match by path. Done when the conventions are in context and the
   prose source is recorded and read.
2. Review each target skill against the checklist below, and quote the offending line in each
   finding. The prose-tells check is mandatory and runs on the recorded prose source. Done when
   every target has a findings list or an explicit clean verdict, and a prose-pass line naming
   the prose source.
3. Cross-reference check. Search each target's authored text for other installed skills' names.
   A hit is a finding unless the user granted that dependency explicitly and the text states a
   fallback. A skill published to a marketplace channel keeps the absolute rule, because the
   grant covers only personal skills co-versioned in one repo. Runtime naming, in questions and
   reports, is always fine. Done when every hit is classified granted-or-finding.
4. Score. When a skill lint runner is installed, run it on a temp dir that holds only the
   targets: symlink each target to `<tmp>/skills/<name>`, then run the runner on `<tmp>`.
   Pass the parent of `skills/`, because passing a `skills/` dir silently scores 0 skills as an
   A. The temp dir is the harness's scratch directory when it has one, else `mktemp -d`. Pipe
   the output through `grep -E 'Skills checked|Score:'`, so only the summary lines reach the
   context. The running session runs this step itself, because it is one command. The threshold
   is 80%+. A run is valid only when its skills-checked count equals the number of target
   skills. A missing summary or a lower count means the runner aborted mid-run, which it does
   silently on some inputs. Re-score each missing skill in its own temp dir. When no temp dir
   can be created, the report names the unscored skills. If no runner is installed, the
   checklist is the gate, and the report says so. Done when each target's score is recorded
   from a valid run.
5. Fix. Propose the findings through the harness's question tool when it has one, else as
   numbered questions in prose, batching related ones. Apply what the user approves, and re-run
   step 4 on changed skills. Under `apply <path>` the approvals come from the file and no
   question is asked. Under `gather` this step does not run. Done when every applied fix holds
   the threshold, and the report shows before and after scores per skill and the prose source.

## Checklist

This checklist is the gate, and writing-for-agents defines its terms.

- Description: triggers only (identity lives in the body), the leading word front-loaded,
  one trigger per branch, a negative ("not for...") present, under 300 chars.
- Invocation: model-invoked only if the agent or another skill must reach it on its own.
  Otherwise hide it in every harness that loads it, and give it a human-facing one-liner.
  Claude Code reads `disable-model-invocation: true` in the frontmatter. Codex ignores that key
  and reads `policy.allow_implicit_invocation: false` in `agents/openai.yaml`. A skill that only
  one harness hides is a finding.
- Steps end on a checkable completion criterion.
- Progressive disclosure holds. Grade it with the rubric below, one verdict per section of the
  target skill.
- Hunt no-ops, duplication, sediment, sprawl and negation-steering. Hunt passages a leading
  word would collapse.
- Overconstraint: a rigid "never/always" that is not safety-critical, where an intent
  statement plus the model's judgment would do. Relax it, because worst-case rules written for
  older models over-constrain newer ones.
- Cross-surface duplication: the same guidance in the skill and in an agent instruction file
  (CLAUDE.md, AGENTS.md), a hook message, or a tool description. One owner keeps it.
- Examples where interface would do: a usage example that a sharper step name, parameter, or
  enumerated status makes redundant. Cut it. Prefer a runnable check or real code over a prose
  rubric where one exists.
- Prose tells: apply the rules at step 1's prose source to the target's authored prose
  (SKILL.md and `references/`). On `fallback checklist`, hunt em-dash asides, emphasis bold,
  filler ("just", "actually", "in order to"), passive voice with no named actor, and sentences
  over ~25 words. Report one finding per skill, "prose pass over N files (rules: <prose
  source>)", with up to three quoted sample lines, or a clean line naming the source. Falling
  back without saying so is a defect. A prose fix keeps every rule, number, path, command and field name, and
  stays an edit set apart from the other fixes.
- Delegation and context cost hold. Grade them with the delegation rubric below, one verdict
  per step of the target skill.
- Frontmatter parses, and `evals/evals.json` exists and parses. A step-bearing skill without
  one is a finding, and a pure-reference skill earns at least one diagnosis eval.

## Progressive-disclosure rubric

Grade each section of the target skill. Every failed row is a finding naming the section.
When rows 2 and 3 both fire on one block, row 2 wins: a block every branch needs stays inline,
and row 3 fires only on branch-specific reference. On a reference-only skill (no step
sequence), rows 3 and 5 read differently. Row 3 is N/A, and row 5 asks whether the first
screen carries the taxonomy instead of a process skeleton.

| Criterion | Checkable question | Verdict when it fails |
| --- | --- | --- |
| Branch test | Does every invocation path read this section? | No: disclose to `references/` |
| Inverted disclosure | Does every run need this `references/` file? | Yes: hoist it inline |
| Steps vs reference | Is a flat reference block (table, worked example, API detail) sitting inside the step sequence? | Yes: disclose, and keep steps inline |
| Pointer wording | Does each pointer say when to load its file, and is the file named for what it holds? | No: reword the pointer |
| First screen | Do the first ~40 lines carry the whole process skeleton? | No: push detail down or out |
| Size signal | Body over ~200 lines, or over 8 code blocks, with no `references/`? | Yes: find the disclosure cut |
| Co-location | Do a concept's definition, rules, and caveats sit under one heading? | No: regroup them |
| Sequence cut | Do post-completion steps tempt a rush past the current one? | Yes: sharpen the criterion first, then split |

## Delegation and context rubric

Grade what a run of the target puts in the main agent's context, one verdict per step. Every
failed row is a finding naming the step. The rubric grades a step-bearing skill whose run reads,
edits or runs commands, and a reference-only skill reads N/A. A step small enough for the
running session, such as one command or one short edit, passes Tier delegation. A dispatch costs
more than it saves there. The tiers are the ones in `~/.agents/workflow-models/tiers.md`. When that
file is absent, the row asks for a named cheaper agent instead of the general-purpose default.

| Criterion | Checkable question | Verdict when it fails |
| --- | --- | --- |
| Tier delegation | Does heavy or mechanical work (multi-file edits, repeated test or lint runs, a read-only skill run with no fan-out) go to a tier agent named by its tier? | Name the step and its tier |
| Report cap | Does each dispatch set a return shape and a size cap that keep diffs and file bodies out of the return? | Add the shape and the cap |
| Self-contained brief | Can a worker with no chat context do the task from the prompt and the paths it names, with no file body or diff pasted where a path would do? | List what it lacks, or swap the pasted contents for the path |
| Running-session-only work | Do external writes, subagent fan-outs and user questions stay in the main thread? | Move them to the running session |
| Check by result | Does the running session accept a worker on its check result, reading only cited line ranges? | Replace the re-read with a check |
| Load cost | Does the running session read only what it uses: a grep or head for one fact, long command output saved to a file and grepped, and MCP schemas, long pages or generated files left to a worker that returns a digest? | Name the read and its cheaper form |
| Phase hand-off | When a run ends one phase and the next starts on a filled context, does it hand over to a fresh session with a paste-ready block, and keep resumable state on disk? | Add the hand-off |
| Parallel writers | Do parallel workers always write disjoint files? | Run them in sequence |

Self-contained brief passes a short report or quoted failing lines handed to a worker, because
those are the evidence, not a load. Check by result flags a routine re-read of a worker's files.
One bounded check at a gate passes it: the cited files at their cited lines, or the final diff
read once before a PR or a done claim. A rule that tells the running session to reopen cited files before
such a gate therefore agrees with this row. Phase hand-off passes state on disk that a fresh
session resumes from with the same prompt. It reads N/A for a same-session follow-on that loads
nothing heavy, such as a closing step that invokes the next skill.

## Gotchas

- Accepted lint warnings, not bugs:
  - `description too long` when the triggers need the space.
  - `body >200 lines with no references/` on a reference-style skill, after a trim attempt.
  - The frontmatter trigger and negative checks on a skill hidden from model invocation, whose
    description is human-facing by design.
  - `missing gotchas section` when a `## Failure modes` section holds that content.
