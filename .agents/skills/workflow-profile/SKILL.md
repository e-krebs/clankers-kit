---
name: workflow-profile
description: >-
  Create or refresh the workflow profile of the current repo — the org template plus the
  per-repo override. Use when setting up or updating that profile. Not for changing the
  tickets, branches or CI the profile describes.
disable-model-invocation: true
---

# workflow-profile

A workflow profile records how work lands in a repo: its tracker, its branch and commit
policy, its verify commands, its reviewers. Profiles live in `~/.agents/workflow-profiles/`,
which is a symlink into a dotfiles repo. Two files resolve for one repo: `<owner>.md` holds
the org template, `repos/<repo>.md` overrides the rows that differ. This skill inspects what
is there, proposes the rest, asks about the deltas in one round, and writes the tables. The
resolver every consumer shares is [scripts/resolve-profile.sh](scripts/resolve-profile.sh):
hooks source it, and a skill with no rows in context runs it with `--rows`. When the user asks
how the workflow skills fit together, or which stage to enter, load
[references/workflow-map.md](references/workflow-map.md): the map of the composable set, its
stages, and the hooks that glue them, with the diagram in `workflow-map.html` beside it.

## Steps

1. Inspect, read-only. Parse `git remote get-url origin` for owner and repo, handling the
   https, ssh and `git@` forms; with no remote, take the basename of
   `git rev-parse --show-toplevel` as the repo and note there is no owner. Resolve the real profiles directory with
   `readlink ~/.agents/workflow-profiles`. Read `<owner>.md` and `repos/<repo>.md` where they
   exist. Done when the owner, the repo, the real directory and every existing row are in hand.
2. Propose a value for each of the twelve fields in the table below. An existing file supplies
   its own rows; otherwise take the Default column, derive Default branch from
   `git symbolic-ref refs/remotes/origin/HEAD`, and list under Reviewers the review agents
   found on this machine's PATH (`command -v claude`, `command -v codex`, and any other agent
   CLI you know of). Sniff the repo facts where it
   is cheap: a lockfile suggests the install command, `package.json` scripts named test / lint /
   type-check suggest the verify commands, a dev script plus its port suggests the browser
   check. Done when every field carries a current value and a proposed value.
3. Interview the deltas in one batched question call — the harness's question tool when it has
   one, else numbered questions in prose. Ask only about fields whose proposal differs from the
   current value, showing `current → proposed` so the user picks per field. Done when every
   differing field holds the user's answer and no field was asked twice.
4. Write, through the real path from step 1. The org file gets the table created, or the chosen
   rows updated in place with every other row left byte-identical, spacing included. The repo
   override keeps only rows that deviate from the org row, plus the repo facts; delete it when
   nothing deviates and no repo fact is set. A repo with no remote has no org file, so
   `repos/<basename>.md` carries all twelve rows. When Ticket system lands on Jira, load
   [references/tracker-rules-jira.md](references/tracker-rules-jira.md) and append its
   `## Tracker rules` section to the org file with `<PROJECT>` replaced by the project key,
   unless the section is already there; another tracker leaves an existing section alone. Done
   when `git diff` in the dotfiles repo shows the chosen rows and nothing else.
5. Report one table per written file: the file, each row written, and `old → new`. Close by
   naming the next step — a new session picks the profile up through the session-start hook,
   which injects the resolved rows into context. Done when every written file has its rows
   listed and that next step is stated.

## Fields

Twelve rows, in this order. `—` means unset, while `none` and `n/a` are values a resolver
honours. The rows marked repo fact are per-repo: the org template leaves them `—` and a repo
override fills them. A cell may open with one working-directory prefix, `<dir>: <commands>`,
which applies to every command in that cell.

| Field | Meaning | Default | Example |
| --- | --- | --- | --- |
| Ticket system | tracker plus project key | `none` | `Jira (PROJ)` |
| Git source | forge and owner | `GitHub (<owner>)` | `GitHub (acme)` |
| Default branch | what PRs target | from origin/HEAD, else `main` | `develop` |
| Commit policy | how work reaches that branch | `direct commits to main` | `PRs, never direct` |
| Commit convention | commit subject shape | `conventional w/ scope` | `conventional w/ scope, ticket ref in PR body only` |
| CI watcher | CI to poll after a push | `none` | `CircleCI` |
| PR shape | review and merge habits | `n/a` | `draft-first, squash, CODEOWNERS review` |
| Remote | whether the repo has one | `yes`, or `local-only` without a remote | `yes` |
| Install command | repo fact: dependency install | `—` | `_client: yarn install` |
| Verify commands | repo fact: gates, `, `-separated | `—` | `_client: yarn test, yarn lint --quiet` |
| Browser check | repo fact: `<dev server> → <base URL>` | `—` | `_client: yarn dev:beta → http://localhost:3000` |
| Reviewers | review agents installed here | the agents on PATH | `claude, codex` |

## Gotchas

- Write through the real path that `readlink` returns: a guard hook can refuse a write through
  the `~/.agents/workflow-profiles` symlink.
- The `.asked/` markers belong to the session-start hook, which writes them to nudge once.
  Read them if useful, leave them as they are.
