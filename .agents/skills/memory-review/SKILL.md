---
name: memory-review
description: >-
  Audit the personal agent-memory store project by project: flag stale, duplicate and
  rule-covered memories, decide each with the user, apply and commit. Use when the user asks to
  review, prune or clean up their memories. Not for a single memory edit, code review, or the
  standing rules (hooks, CLAUDE.md, skills).
---

# memory-review

Audit every per-project memory store under `~/.claude/projects/*/memory/`. The pass keeps only
facts that are true today and that nothing else already says. Every change is the user's
decision through `AskUserQuestion`, applied, and committed to the dotfiles repo. Two arguments
let a parent audit split the run: `gather` stops after phase 2 with the findings table and the
before snapshot and asks nothing, and `apply <path>` reads the verdicts and the snapshot from
the rows and block of that file whose sub-topic is `memories`, skips phases 1 to 3 and the
closing chain, and ends on the closing report. With no argument, every phase runs.

## Phase 1 — gather (read-only)

1. List every project's memory dir with `find -L` (plain `find` returns nothing through the
   symlink) and count with `find -H`, so a symlinked memory dir (a worktree key aliasing a
   canonical store) lands once, under its canonical key. Order projects by memory count,
   ascending. The smallest store warms the user up cheaply.
2. Snapshot the before-numbers for the closing report: files and words per project (`wc -w`
   over every memory file, `MEMORY.md` included). Save them to a scratch file.
3. Check each source repo's pulse (`git log -1 --format=%ci` in `~/Projects/<name>`). A dormant
   or unversioned repo makes its memories candidates for promotion or deletion.

Done when the snapshot file exists and every store has a count and a repo pulse.

## Phase 2 — fan out (one read-only subagent per project, plus one for the rules inventory)

Launch them in parallel. Each project agent reports, per memory: filename, frontmatter `name:`
and `type:`, a one-line résumé (max 20 words), and whether it is time-bound or stale (a PR, a
sprint, a "pending" item, a past date). Then: a thematic grouping, every overlap, duplicate or
contradiction (quote the conflicting lines), every memory whose content the repo already
records, and whether `MEMORY.md` matches the files. The rules agent inventories every standing
rule with its source (CLAUDE.md, each hook and what it denies, each skill's contract, the output
style), which feeds the covered-by-a-rule flags.

Load [references/flag-heuristics.md](references/flag-heuristics.md) before assigning any
verdict. It holds the full flag list with per-flag guidance. Verify before judging: a memory
naming a PR or a ticket gets its live state checked (`gh`, Jira) before it is called stale.

Done when every memory carries a résumé and a flags-or-clean call, and the rules inventory names
every rule with its source. Under `gather`, stop here: return the findings table (repository,
memory, flags, recommended verdict, evidence) and the phase-1 snapshot, and ask nothing.

## Phase 3 — interview

Under `apply <path>`, skip this phase: the verdicts sit in that file's `memories` rows, one per
memory. Otherwise
ask through `AskUserQuestion`, flagged memories first, project by project. Close each project
with one multi-select confirm-all call for its clean set. Rules:

- Every question leads with the name of the repository the memory belongs to ("widgets: ...").
- Each option carries the résumé plus a recommendation and its rationale. The recommended option
  comes first with "(Recommended)".
- Verdicts: keep · delete · refresh (rewrite to the current state, drop the dated changelog) ·
  merge (fold into a named sibling, delete the loser) · promote (move the rule to CLAUDE.md, a
  hook, a skill or a repo doc, then delete the memory).

Done when every memory in the store holds a user verdict.

## Phase 4 — apply and commit

Per project: apply the verdicts, rewrite retractions in place (a reader must never meet
retracted advice above its correction), rebuild `MEMORY.md` (one line per memory), fix every
`[[wikilink]]` to a surviving hyphenated `name:` slug, and normalize slugs to the hyphenated
form of the filename. A promote verdict whose target is another repo writes a self-contained
brief under `~/.claude/plans/` first (problem, evidence with links, proposed text, acceptance
check, commit and PR shape), and the memory is deleted only once the brief exists. Commit per
concern with a scoped conventional message. Then write today's date to
`~/.claude/projects/.last-memory-review` for downstream readers.

A skill this pass creates or edits gets the hygiene gate before its commit: run the
`skill-review` skill on it, a user-granted exception to the no-cross-reference rule. Under
`apply`, run that gate to its diagnosis and scoring only, and hand any new finding back in the
closing report for a later approval, so the run still asks nothing. If that skill is absent,
hold the skill to the repo's authoring conventions and its lint bar before committing.

Done when every wikilink resolves, each index's line count equals its file count, every brief
a promote verdict needs exists, every touched skill passes the gate, and the marker holds
today's date.

## Closing report

Show, in tables: per project before / deleted / refreshed / merged / promoted / kept / after
plus a global total row; where the promoted rules went (CLAUDE.md lines, hook denies, repo docs,
briefs); size before and after (files and words, from the phase-1 snapshot, or under `apply`
from the snapshot block of the verdicts file); integrity fixes
(dangling links removed, index lines corrected, slugs normalized); and, per applied change, the
file plus a one-line undo. Under `apply`, this report is the last output: the parent merges it
into its own.

Done when every table holds the numbers the snapshot and the verdicts give.

## Closing chain (skipped under `apply`)

Run an independent adversarial review with a DIFFERENT model, `codex` when it is on the path
(`codex exec --sandbox read-only`), pointed at the commit range plus the decision table. Its
checklist: every decided delete is gone, every keep is untouched, no trim dropped a surviving
fact, and any new code is sound. Apply its high-confidence findings as a fixup commit, decline
the rest with cause in the report. The shared hooks run inside that `codex exec` once trusted;
if codex reports them untrusted after a wiring edit, run `/hooks` once in an interactive `codex`
rather than passing `--dangerously-bypass-hook-trust`.

Close by recommending the built-in `/doctor` checkup to the user. It covers install health,
unused extensions, version currency and permission posture, and its CLAUDE.md trim check runs
only when the user types it in a session.

Done when each reviewer finding is marked applied or declined-with-cause.

## Gotchas

- `MEMORY.md` is an index only: one line per memory, never content.
- Deleting a whole project's store removes the `memory/` dir and its index together.
- A "pending X" memory whose trigger already fired is ripe: do X (or verify it happened), then
  delete the memory. Check for an existing tracker ticket before creating one.
- Vet a delegated rewrite before committing it. A worker can leave stray markup (a literal
  `</content>` line, an unclosed fence) at a file's end.
- Session transcripts (`*.jsonl`) sit next to the memory dirs and are gitignored: never stage
  them, and never grep them for wikilink integrity (they hold stale copies of everything).
- The gitignore re-includes `projects/*/memory` both as a dir and as a symlink; keep both lines.
