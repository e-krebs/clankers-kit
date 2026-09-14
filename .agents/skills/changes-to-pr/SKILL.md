---
name: changes-to-pr
description: Turn working-tree changes into atomic commits and, where the repo's policy calls for one, a branch and a PR with a drafted description. Use when the user says open/cut/ship a PR for my changes, or commit and PR this. Not for promoting a draft to ready, merging, or watching CI.
---

# changes-to-pr

Turn the working tree into a commit series and carry it as far as the repo's policy allows: a
commit on the default branch, a pushed branch, or a PR with a ready description. A review can run
first.

## Safety

- Nothing is committed, pushed, or sent to the forge before the user approves the Gate 2 plan.
- A hand-written (non-template) PR body is the user's to keep: surface it at Gate 2 and replace it
  only on explicit approval.
- Respect `.gitignore`; never commit secrets, tokens, internal URLs, or credentials, and surface
  anything suspicious in the Gate 2 plan.

## Profile

Read the workflow profile rows from context — the session-start hook injects the resolved table.
When they are absent from context, run
`bash ~/.agents/skills/workflow-profile/scripts/resolve-profile.sh --rows` and read its table.
These rows shape the run:

- Commit policy — `direct commits to main`: commit on the default branch and stop, no branch and
  no PR. `PRs, never direct`: branch, commits, PR.
- Remote — `local-only`: stop at the commit, nothing is pushed.
- Ticket system — `none`: no ticket question and no tracker move anywhere in this run.
- Commit convention — the subject shape, and where a ticket reference may appear.
- PR shape — how the PR opens: draft-first, squash, CODEOWNERS review.

Done when the rows are in hand and the commit / branch / PR / ticket path is settled.

## Step 0 — Inspect (no questions yet)

Run in parallel: the current branch (`git branch --show-current`); the base, from the profile's
Default branch cross-checked against `git symbolic-ref --quiet refs/remotes/origin/HEAD`; the
changes (`git status --porcelain` → staged + unstaged + untracked, minus `.gitignore`); the full
diff to commit (`git diff <base>` plus the contents of untracked files); and the branch lead
(`git log --oneline <base>..HEAD`, the commits unique to the current branch).

From the diff, analyze concerns (does the change span more than one separable concern?), env vars
(`process.env.*`, `import.meta.env.*`, `ENV["…"]`, `.env*`), and dependency-manifest changes.

Done when that analysis is in hand, or the graceful abort fired on a clean tree or a detached HEAD.

## Step 1 — Gate 1 (one batched question round)

Ask only what applies, in one round, through the harness's question tool when it has one, else as
numbered questions in prose. When the user opts to draft a ticket description or to split into
several PRs, read [references/split-path.md](references/split-path.md) for the procedure first.

1. Ticket — only when Ticket system names a tracker. Detect the ID through the detection order in
   the profile's `## Tracker rules`; on a hit ask to confirm, else offer: give an ID · draft a
   description · none.
2. Where the commits land — only under `PRs, never direct`, and only when the current branch is
   not the base: current branch · a new branch off it (stacked) · a new branch off `<base>`
   (independent, omitted when the changes depend on commits unique to the current branch, which
   branching off the base would drop). On the base branch no question is asked: a new branch off
   `<base>` is created.
3. Split — when several concerns were detected: one PR, or one branch + commits + PR per concern.
   Name the detected concerns in the question.
4. Review — only when no review summary is in context and no plan prescribes one.

Done when every applicable item has an answer.

## Step 2 — Build the plan

- Review. With a plan in context, read its Closing steps review line for the tier and the reviewer
  count and delegate to the review capability with exactly those; without a plan, offer one
  judgment-tier reviewer. Reviewers are read-only — they return a report and change nothing. Apply
  the findings you accept yourself, then re-read the Step 0 diff, because the tree moved.
- Branch name, when creating one: `type/desc` — `type` from the primary concern, `desc` a short
  kebab summary, no ticket ID; append `-2`, `-3`… when taken.
- Commit split. When the plan in context prescribed a split (files per commit, subjects), follow
  it. Otherwise group by concern at file granularity, dropping to hunk level only when one tracked
  file genuinely mixes concerns; new and untracked files go whole into one commit. Subjects follow
  the Commit convention row, the scope taken from the change's feature or area, including where
  that row allows a ticket reference. The title is the
  primary concern's subject, same convention.
- PR description, skipped under `direct commits to main`: read the repo's PR template at runtime
  (`.github/pull_request_template.md`, or the repo's configured location) and use its sections and
  inline hints as the structure, drafted from the full diff. When drafting the body, read
  [references/pr-description.md](references/pr-description.md) for the section rules and the
  Agent review block.
- Tracker move, only with a tracker and a ticket in hand: follow the profile's `## Tracker rules`
  to resolve the move to the work-started state, carrying one outcome to Gate 2 — a matched
  transition, the picker candidates, or nothing applicable.

Done when the split and, where they apply, the branch name, description and move are drafted.

## Step 3 — Gate 2 (one consolidated approval)

Show one plan: the commit split (subjects + files), plus the branch name and the full PR
description where they apply. Self-check the drafted body first — save it to a file and run
`grep -nE '<!--|\bTODO\b|\.\.\.' <body-file>`; any hit is a placeholder to fix before the PR is
created, while whether the what and why sections carry real content stays judgment, not grep. When
an existing PR's body is non-template, warn that it would be replaced and let the user keep it.

When a tracker move applies, batch its own question into this same interaction: move `<TICKET>`
(`<current>` → the work-started state)? — or the rules' picker plus Skip when no transition targets
that state. With no move applicable, ask nothing.

Done when the user approves, or edits and approves.

## Step 4 — Execute

The tracker move goes first when it was approved: the work has started, so that state should not
wait on the push or be blocked by it. Best-effort, per the rules.

1. Branch — only under `PRs, never direct`, and only when creating one:
   `git checkout -b <name> <base-or-current>`, which carries the working tree over. Under
   `direct commits to main`, the current branch must be the Default branch; on any other branch,
   say so and stop before committing.
2. Commits — `git reset` to unstage, then per planned commit `git add <files>` at file level, or
   `git apply --cached` with a generated patch at hunk level, then `git commit -m "<subject>"`. On
   an apply failure, abort cleanly, leave the tree intact, and report which commit failed.
3. Stop here when Commit policy is `direct commits to main` (report the commits that landed on the
   default branch) or Remote is `local-only` (report that nothing was pushed).
4. Push: `git push -u origin <branch>`.
5. PR, per the PR shape row. No PR yet: `gh pr create --base <base> --title "<title>" --body-file -`
   (heredoc the body), with `--draft` when the shape is draft-first. Existing PR: push the commits,
   then `gh pr edit <n> --body-file -` only when the user approved replacing the body.

Close by naming what follows: with a CI watcher in the profile, a hook hands off to the CI watch;
with `none`, say plainly that no CI watch follows and the PR is the user's to advance.

Done when the commits exist and, where the rows call for it, the PR is created or updated.

## Gotchas

- The Default branch row and `origin/HEAD` disagree in a stale clone; the profile row wins, and the
  mismatch is worth one line to the user.
- `direct commits to main` still earns the concern split — several commits on the default branch,
  one per concern, in the order the user chose.
- A ticket reference belongs only where the Commit convention row puts it; under "ticket ref in PR
  body only", a subject carrying an ID is a commit a gate hook blocks.
