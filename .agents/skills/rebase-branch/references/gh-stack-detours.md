# `gh stack` detours

This file covers two cases that branch off the cascade's main sequence. S1 in
[gh-stack-cascade.md](gh-stack-cascade.md) sends you here, and that file's Report section still
applies.

## An explicit base argument

`gh stack rebase` targets the stack's own trunk and ignores any base you pass. If the base the
user named **is** the trunk, cascade. Otherwise **ask**:

- **Cascade the stack onto its trunk.** The named base is ignored, so say so.
- **Take this branch out of the stack.** Run `gh stack unstack --local` **first**, then close
  this file and follow [plain-rebase.md](plain-rebase.md), handling a dirty tree per pre-flight's
  guard on the way. The unstack is required. Leaving the metadata in place keeps a recorded base
  SHA that is now wrong, and that SHA feeds the cascade's `--onto` cut point (its S3). Skipping
  the unstack therefore sets up a silent drop for the next run, whoever runs it. (Without
  `--local` it also unstacks the PRs on GitHub, though queued and auto-merge PRs stay stacked.
  Add `gh pr edit --base` if the PR's base must move too.)
- **Abort.**

## Metadata present, `gh stack` not installed

Pre-flight's lookup exited 0 or 3 (the metadata file exists) but `gh` reports
`unknown command "stack"`. Warn that this repo has a stack and no tooling to cascade it, then
**ask**:

- **Install it.** Run `gh extension install github/gh-stack`, then start over.
- **Single-branch rebase anyway.** Warn that the branches above are **orphaned** and each needs
  its own rebase, bottom-up. Then close this file and follow
  [plain-rebase.md](plain-rebase.md), handling a dirty tree per
  [SKILL.md's Dirty tree](../SKILL.md#dirty-tree) on the way.
- **Abort.**

Branch names come from the lookup's line, which names every member of this branch's stack bottom
to top. On exit 3 the file lists another stack and not this branch, so name no branch. Say only
that the repo has a stack elsewhere and that this branch is untracked here.
