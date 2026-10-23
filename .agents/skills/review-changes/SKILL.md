---
name: review-changes
description: >-
  Run independent reviewers over a working tree, branch, PR or plan file and triage their
  findings into one severity-ranked report. Use when asked to review changes, a branch, a PR or
  a plan for bugs. Not for fixing the bugs or reviewing style.
---

# review-changes

Independent reviewers read one target in parallel, read-only. This agent triages what comes
back: it dedupes, reopens the cited line ranges, ranks by severity and writes one report. This
skill only reviews. The requester owns the fixes.

## Steps

1. Resolve the target as one of four kinds and state it in one line with the command that
   produces it:
   - working tree: the uncommitted diff, `git diff HEAD` plus the untracked files. This is the
     target when the caller names none and the tree is dirty.
   - branch: the range against its base, `git diff $(git merge-base <base> HEAD)..HEAD`, the
     base being the profile's Default branch.
   - PR: a number or a URL, read through `gh pr diff <n>` and `gh pr view <n>`. Without a
     checkout, reviewers and triage read files at the PR head (`git fetch origin
     pull/<n>/head`, then `git show FETCH_HEAD:<path>`), never the local tree.
     Check the branch out only when that is not enough, and ask first when local changes are in
     the way.
   - plan file: a markdown plan. The reviewers read the plan text, not code.

   Done when the kind, the range or path, and the command are stated.
2. Resolve the tier and the count. A plan in context supplies both from the Task cell of the Review
   row in its Steps table ("<tier> tier × 2"). Failing that, take what the caller said. Failing that, one
   reviewer whose tier you pick from `~/.agents/workflow-models/tiers.md` by the shape of the work. Read the tier's model and effort from
   `~/.agents/workflow-models/<provider>.md`; when it is missing, run each reviewer on its
   default model, and say so. Done when the tier, its model per provider, and the count are
   fixed.
3. Choose the reviewers from the profile's Reviewers row, read from context, else from
   `bash ~/.agents/skills/workflow-profile/scripts/resolve-profile.sh --field Reviewers`. It
   lists the review agents installed on this machine, in order:
   - claude: a subagent of the tier's agent, which carries its model and effort
     (`subagent_type` set to that tier).
   - codex: `codex exec --sandbox read-only -m <model> -c model_reasoning_effort=<effort>
     -o <scratch>/codex-review.md "<prompt>" < /dev/null > <scratch>/codex-review.log 2>&1`, `<scratch>` being the harness's scratch
     directory, else `mktemp -d`. Read only the `-o` file, and the log only on failure.

   A reviewer the caller names wins over row order. Otherwise the first pick is the first row
   entry whose provider differs from the session's (codex in a Claude Code session, claude in a
   Codex session), and the rest follow in row order. With no other provider installed, count 1
   takes the row's first entry. A count above the number installed runs every installed
   reviewer, and the report names the shortfall. When a plan names a repo's own review skill,
   that skill runs instead of this step's reviewer list. Done when the reviewer list holds as
   many entries as the count, or every installed reviewer.
4. Launch them in one message so they run concurrently. Every reviewer runs read-only in this
   tree and receives the target line from step 1 plus the absolute path of
   [references/review-prompt.md](references/review-prompt.md), to read before starting; do not
   read or paste it yourself. Retry a failed invocation once, then name the blocker and
   continue with the rest. With every reviewer failed, the report says the review is
   incomplete, never clean. Done when each launched reviewer returned findings or a named
   failure.
5. Triage. Merge cross-reviewer duplicates into one finding carrying the sharpest evidence, then
   reopen the cited line ranges yourself, not whole files. Widen to callers and tests only when
   the cited lines cannot settle it or reviewers disagree. Mark each one confirmed (the code
   shows the bug) or plausible (reading alone cannot settle it). Drop the severity when the
   impact is latent, such as a broken helper nothing calls. Done when every finding is deduped,
   ranked and marked.
6. Write one report: a count per severity, the findings from P1 down with `file:line`, impact and
   the proposed fix, a ruled-out list with the reason each was dropped, a per-reviewer finding
   count, and a line saying only static review ran when no test or type-check was executed. The
   review leaves the tree byte-identical. Done when the report holds every triaged finding.

## Gotchas

- `codex exec` waits on stdin and hangs forever without `< /dev/null`.
- The installed codex may not know a model codename from the tiers file. Run its default and record
  which model actually reviewed.
- The shared PreToolUse gates from `~/.codex/hooks.json` also run inside `codex exec` once
  trusted, so a codex reviewer's `cd` or `cat` is denied like Claude's. When codex reports
  untrusted hooks after a wiring edit, run `/hooks` once in an interactive `codex`; never pass
  `--dangerously-bypass-hook-trust` from a skill.
- A plan-file review returns gaps, not bugs, ranked on the same scale.
- Reviewers share this tree because an uncommitted diff exists nowhere else. A worktree per
  reviewer would drift from it.
