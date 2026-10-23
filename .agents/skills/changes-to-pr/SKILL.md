---
name: changes-to-pr
description: Turn working-tree changes into atomic commits and, where repo policy calls for one, a branch and a PR with a drafted description. Use when the user says open/cut/ship a PR for my changes, commit and PR this, or push these to my open PR. Not for marking a draft ready, merging, or watching CI.
---

# changes-to-pr

Turn the working tree into a commit series and carry it as far as the repo's policy allows: a
commit on the default branch, a pushed branch, or a PR with a ready description. A review can run
first.

## Safety

- Commit nothing, push nothing and send nothing to the forge before the user approves the Gate 2
  plan.
- A hand-written (non-template) PR body is the user's to keep: surface it at Gate 2 and replace it
  only on explicit approval.
- Respect `.gitignore`; never commit secrets, tokens, internal URLs, or credentials, and surface
  anything suspicious in the Gate 2 plan.

## Profile

Read the workflow profile rows from context, where the session-start hook injects the resolved
table.
When they are absent from context, run
`bash ~/.agents/skills/workflow-profile/scripts/resolve-profile.sh --rows` and read its table.
With no rows and no script (exit 127), say the profile setup is missing and stop here, before any
change. These rows shape the run:

- Git source names the forge, which decides whether a forge command runs at all.
- Commit policy. Under `direct commits to main`, commit on the default branch and stop, with no
  branch and no PR. Under `PRs, never direct`, create a branch, the commits and a PR.
- Remote. Under `local-only`, stop at the commit and push nothing.
- Ticket system. Under `none`, ask no ticket question and make no tracker move anywhere in this
  run.
- Commit convention sets the subject shape, and where a ticket reference may appear.
- Verify commands lists the checks P3b runs on the stack route. P3b reads them from
  `resolve-profile.sh --verify-commands`. Empty output counts as `—`: skip P3b and say so at Gate 2.
- PR shape sets how the PR opens: draft-first, squash, CODEOWNERS review. A value carrying the clause
  `gh stack for a multi-PR change`, or the `gh-stack` spelling, is the stack signal. Step 2 routes
  a multi-PR change as one stack. The clause has no effect on a non-GitHub source, under
  `direct commits to main` or under `local-only`, so read those three rows first. A negated
  mention such as `no gh stack here` means no stacking.

Done when the rows are in hand, the commit / branch / PR / ticket path is settled, and the stack
clause reads present or absent.

## Step 0. Inspect (no questions yet)

Run in parallel: the current branch (`git branch --show-current`); the base, from the profile's
Default branch cross-checked against `git symbolic-ref --quiet refs/remotes/origin/HEAD`; the
changes (`git status --porcelain -uall`, which lists staged, unstaged and untracked files minus
`.gitignore`), saved to the scratch file, with only the count and the first lines read inline; the
diff to commit (`git diff HEAD` plus the untracked files), written to a scratch file with only
`git diff --stat HEAD` read inline; and the branch lead
(`git log --oneline <base>..HEAD`, the commits unique to the current branch). `<base>` is the
trunk and stays the trunk for the whole run: it is what the diff and the branch lead are measured
against, not necessarily what a PR opens against. Gate 1 item 2 binds that separately, as
`<pr-base>`.

From the stat and the diff file, analyze concerns (does the change span more than one separable
concern?), env vars (grep the file for `process.env.*`, `import.meta.env.*`, `ENV["…"]`, `.env*`),
and dependency-manifest changes. Read hunks from the file only where the split or the description
needs them.

Done when that analysis is in hand, or the graceful abort fired on a clean tree or a detached HEAD.

## Step 1. Gate 1 (one batched question round)

Ask only what applies, in one round, through the harness's question tool when it has one, else as
numbered questions in prose. When the user opts to draft a ticket description or to split into
several PRs, read [references/split-path.md](references/split-path.md) for the procedure first.

1. Ticket, only when Ticket system names a tracker. Detect the ID through the detection order in
   the profile's `## Tracker rules`, whose first source, the prompt, holds the key a plan's
   Hand-off row passes. On a hit, ask to confirm. Otherwise offer three options: give an ID, draft
   a description, or none.
2. Where the commits land, only under `PRs, never direct`, and only when the current branch is
   not the base: the current branch, a new branch off it (stacked), or a new branch off `<base>`
   (independent, omitted when the changes depend on commits unique to the current branch, which
   branching off the base would drop). On the base branch no question is asked: a new branch off
   `<base>` is created. The answer binds `<pr-base>`. Where PR shape carries the stack clause the
   stacked option is offered first and pre-selected. The question still stands, because an
   independent branch off `<base>` is a legitimate answer under that row too, and it takes the
   plain items below.
3. Split, when Step 0 detected several concerns: one PR, or one branch, its commits and a PR per
   concern.
   Name the detected concerns in the question.
4. Review, only when no review summary is in context and no plan in context has a Review row.

`<pr-base>` is both the branch a new branch is cut from and the base its PR opens against. It is
per-branch, so under a split each concern binds its own.

| Item 2's answer | `<pr-base>` |
| --- | --- |
| stacked | the current branch |
| independent | `<base>` |
| on the base branch, no question asked | `<base>` |
| current branch | the existing PR's `baseRefName`, else `<base>` |

Done when every applicable item has an answer and `<pr-base>` is bound.

## Step 2. Build the plan

- Review. With a plan in context whose Review row in Steps is `✅`, skip this item: the session that ran the plan already ran the review and dispatched the fixes. When that row is not `✅` yet, read the
  tier and the reviewer count from its Task cell (`<tier> tier × 2`) and delegate to the review
  capability with exactly those; without a plan, offer one reviewer whose tier you pick from `~/.agents/workflow-models/tiers.md` by the shape of the work. Pass the diff
  file's path, not its contents. Reviewers are read-only and return only severity, file:line, the
  finding and a proposed fix, plus what they did not assess. Cap the return at 15 findings, one
  line each. Overflow goes to a scratch file named in the return. Apply the findings you accept
  yourself, then regenerate the Step 0 diff file and stat, because the tree moved.
- Branch name, when creating one: `type/desc`, where `type` comes from the primary concern and
  `desc` is a short kebab summary with no ticket ID; append `-2`, `-3`… when the name is taken.
- Commit split. When the brief of the plan's Hand-off row recommends a split (files per commit,
  subjects, files to leave out), take it as a hint and follow it unless the diff contradicts it.
  Otherwise group by concern at file granularity, dropping to hunk level only when one tracked
  file mixes concerns; new and untracked files go whole into one commit. Subjects follow the Commit
  convention row, including where that row allows a ticket reference, and take their scope from the
  change's feature or area. The title is the primary concern's subject, in the same convention.
- PR description, skipped under `direct commits to main`: read the repo's PR template at runtime
  (`.github/pull_request_template.md`, or the repo's configured location) and use its sections and
  inline hints as the structure, drafted from what the PR will carry: the Step 0 diff file, plus
  the branch lead when the commits land on the current branch. When drafting the body, read
  [references/pr-description.md](references/pr-description.md) for the section rules and the
  Agent review block.
- Tracker move, only with a tracker and a ticket in hand: follow the profile's `## Tracker rules`
  to resolve the move to the work-started state, carrying one outcome to Gate 2: a matched
  transition, the picker candidates, or nothing applicable.
- The stack, only where PR shape carries the stack clause and this run is a multi-PR change,
  meaning Gate 1 item 3 split it or item 2 answered stacked. A lone branch is not a stack and takes
  the plain items. Run no further command until you have read
  [references/gh-stack-path.md](references/gh-stack-path.md) in full, then run its P1 pre-flight,
  which is read-only. Carry into Gate 2 its route, which is `init`, `add` or degraded, and the
  mutation set it records. That file is the only source for `gh stack` invocations; treat any others
  you recall from memory as wrong.

Done when the split and, where they apply, the branch name, description, move and stack route are
drafted.

## Step 3. Gate 2 (one consolidated approval)

Show one plan: the commit split (subjects and files), plus the branch name and the full PR
description where they apply. Self-check the drafted body first. Save it to a file and run
`grep -nE '<!--|\bTODO\b|\.\.\.' <body-file>`; each hit is a placeholder to fix before creating
the PR. Whether the what and why sections carry real content stays a judgment call, not a grep. When
an existing PR's body is non-template, apply the Safety rule on it.

On the stack route the plan also names the stack it will create: the members bottom to top, the
trunk they sit on, which branch each PR opens against, that every new PR opens as a draft under a
draft-first shape, and that each PR carries temporary generated text until the title-and-body pass
finishes. It also names the whole mutation set, meaning each existing member, its unpushed commits
and any base that will move, because one submit publishes all of it. It states how each branch is
verified before the push, or that the check is skipped when the profile lists no Verify commands.
Existing members with unpushed commits are published by the same submit without verification.

When a tracker move applies, batch its own question into this same interaction: move `<TICKET>`
from `<current>` to the work-started state? When no transition targets that state, offer the
rules' picker plus Skip instead. With no move applicable, ask nothing.

Done when the user approves, or edits and approves.

## Step 4. Execute

When the user approved the tracker move, run it first: the work has started, so that state should
not wait on the push or depend on it. The move is best-effort, per the rules.

Where Step 2 picked the `init` or `add` route,
[references/gh-stack-path.md](references/gh-stack-path.md) from its P2 onwards replaces items 1, 4
and 5, and item 2's commits stay unchanged. Every other run, the degraded route included, takes the items as written.

1. Branch, only under `PRs, never direct`, and only when creating one:
   `git checkout -b <name> <pr-base>`, which carries the working tree over. Under
   `direct commits to main`, the current branch must be the Default branch; on any other branch,
   say so and stop before committing.
2. Commits. Run `git reset` to unstage, then for each planned commit `git add <files>` at file
   level, or `git apply --cached` with a generated patch at hunk level, then
   `git commit -m "<subject>"`. On
   an apply failure, abort cleanly, leave the tree intact, and report which commit failed.
3. Stop here when Commit policy is `direct commits to main` (report the commits that landed on the
   default branch) or Remote is `local-only` (report that nothing was pushed).
4. Push: `git push -u origin <branch>`.
5. PR, per the PR shape row. No PR yet:
   `gh pr create --base <pr-base> --title "<title>" --body-file -` (heredoc the body), with
   `--draft` when the shape is draft-first. Existing PR: push the commits, then
   `gh pr edit <n> --body-file -` only when the user approved replacing the body.

Close by naming what follows: with a CI watcher in the profile, a hook hands off to the CI watch;
with `none`, say plainly that no CI watch follows and the PR is the user's to advance.

Done when the commits exist and, where the rows call for it, the PR is created or updated.

## Gotchas

- The Default branch row and `origin/HEAD` disagree in a stale clone; the profile row wins, and the
  mismatch gets one line to the user.
- `direct commits to main` still gets the concern split: several commits on the default branch,
  one per concern, in the order the user chose.
- Under "ticket ref in PR body only", a gate hook blocks a commit whose subject carries an ID.
- A PR diff that carries the parent branch's commits means the `<pr-base>` binding went wrong.
