---
name: review-changes
description: >-
  Run independent reviewers over a working tree, a branch, a PR or a plan file, then triage
  their findings into one severity-ranked report. Use when the user asks to review changes, a
  branch, a PR or a plan for bugs with independent reviewers. Not for fixing the bugs or
  reviewing style.
---

# review-changes

Independent reviewers read one target in parallel, read-only, and this agent triages what comes
back: dedupe, reopen every cited line, rank by severity, write one report. Reviewing only — the
fixes belong to whoever asked for the review.

## Steps

1. Resolve the target as one of four kinds and state it in one line with the command that
   produces it:
   - working tree — the uncommitted diff, `git diff HEAD` plus the untracked files. This is the
     target when the caller names none and the tree is dirty.
   - branch — the range against its base, `git diff $(git merge-base <base> HEAD)..HEAD`, the
     base being the profile's Default branch.
   - PR — a number or a URL, read through `gh pr diff <n>` and `gh pr view <n>`. Check the
     branch out only when a reviewer needs the files at that revision, and ask first when local
     changes are in the way.
   - plan file — a markdown plan; the reviewers read the plan text, not code.

   Done when the kind, the range or path, and the command are stated.
2. Resolve the tier and the count. A plan in context supplies both from its Closing steps review
   line ("judgment tier × 2"). Failing that, take what the caller said. Failing that, one
   reviewer at the judgment tier. Done when the tier, its model per provider from the table
   below, and the count are fixed.
3. Choose the reviewers from the profile's Reviewers row, read from context, else from
   `bash ~/.agents/skills/workflow-profile/scripts/resolve-profile.sh --field Reviewers`. It
   lists the review agents installed on this machine, in order:
   - claude — a subagent at the tier's Claude model (`model: opus` at the judgment tier).
   - codex — `codex exec --sandbox read-only -m <model> "<prompt>" < /dev/null`.

   Count 1 takes the row's first entry, count 2 the first two, and a count above the number
   installed runs every installed reviewer with the shortfall named in the report. A repo may
   ship its own review skill; a plan names those, and this skill picks none. Done when the
   reviewer list holds as many entries as the count, or every installed reviewer.
4. Launch them in one message so they run concurrently. Every reviewer runs read-only in this
   tree and receives [references/review-prompt.md](references/review-prompt.md) verbatim plus
   the target line from step 1. Retry a failed invocation once, then name the blocker and
   continue with the rest. Done when each launched reviewer returned findings or a named failure.
5. Triage. Merge cross-reviewer duplicates into one finding carrying the sharpest evidence, then
   reopen the cited lines plus their callers and tests yourself and mark each one confirmed (the
   code shows the bug) or plausible (reading alone cannot settle it). Drop the severity when the
   impact is latent, such as a broken helper nothing calls. Done when every finding is deduped,
   ranked and marked.
6. Write one report: a count per severity, the findings from P1 down with `file:line`, impact and
   the proposed fix, a ruled-out list with the reason each was dropped, a per-reviewer finding
   count, and a line saying only static review ran when no test or type-check was executed. The
   tree ends the review byte-identical. Done when the report holds every triaged finding.

## Model tiers

A tiers reference already in context wins over this table.

| Tier | Shape of work | Claude | Codex |
| --- | --- | --- | --- |
| fast | small, pattern-following, one file | Sonnet | Luna |
| everyday | well-scoped, several files, known conventions | Sonnet | Sol |
| judgment | coupled, delicate, must stay in one head | Opus | Astra |
| orchestration | parallel slices, token-heavy, many files | Fable, Sonnet workers | Astra, Sol workers |

## Gotchas

- `codex exec` waits on stdin and hangs forever without `< /dev/null`.
- The installed codex may not know a model codename from the table. Run its default and record
  which model actually reviewed.
- The shared PreToolUse gates from `~/.codex/hooks.json` also run inside `codex exec` once
  trusted, so a codex reviewer's `cd` or `cat` is denied like Claude's. When codex reports
  untrusted hooks after a wiring edit, run `/hooks` once in an interactive `codex`; never pass
  `--dangerously-bypass-hook-trust` from a skill.
- The Reviewers row is the whole roster: an agent absent from it is not installed here.
- A plan-file review returns gaps, not bugs, ranked on the same scale.
- Reviewers share this tree, which is what keeps an uncommitted diff reviewable at all; a
  worktree per reviewer would drift from it.
