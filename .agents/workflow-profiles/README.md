# Workflow profiles

One `| Field | Value |` table per file: `<owner>.md` is the org template (owner = the owner segment
of the git remote), `repos/<repo>.md` overrides rows for one repo, and a repo with no remote
resolves to `repos/<basename>.md` alone. `—` means unset; `none` and `n/a` are values. The
`.asked/` markers record which repos got their one-time nudge and stay local.

The resolver every consumer shares is `~/.agents/skills/workflow-profile/scripts/resolve-profile.sh`:
hooks source it, and `bash … --rows` prints the merged table for anything else.

The map of the whole skill set, with a diagram, lives in the setup skill at
`~/.agents/skills/workflow-profile/references/workflow-map.md`.

## Consumers

| Reader | Rows it uses |
| --- | --- |
| workflow-profile-nudge.sh (SessionStart) | all, injected into context |
| plan-gate.sh | whether a profile resolves (deny vs advise) |
| commit-subject-gate.sh | Commit convention |
| create-ticket-nudge.sh | Ticket system |
| write-plan, ticket-kickoff | Ticket system, Commit policy, CI watcher, Reviewers, repo facts |
| changes-to-pr, pr-followup, pr-merge | Ticket system, Commit policy, Commit convention, CI watcher, PR shape, Remote |
| verify | Install command, Verify commands, Browser check |
| review-changes | Reviewers |
