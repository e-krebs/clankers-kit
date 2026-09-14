# The workflow skill set

A composable set: every skill reads the same workflow profile and runs on its own, hooks are
optional glue that route from one stage to the next, and any stage can be entered by hand or
replaced by another skill that reads the same rows. The profile is the only shared contract.

The diagram lives in [workflow-map.html](workflow-map.html), a self-contained page with the
same tables as below; open it in a browser. The usual order is ticket-kickoff → write-plan →
implement per the plan → verify → review-changes → changes-to-pr → pr-followup → pr-merge, and
hooks route one stage into the next; without any hook, every skill still works when typed as
`/name`.

## Stages

| Stage | Skill | Enters through | Profile rows it reads | Hands off to |
| --- | --- | --- | --- | --- |
| Set up | workflow-profile | typed only | writes them all | a new session |
| Kick off | ticket-kickoff | "pick up the next ticket", `/ticket-kickoff` | Ticket system, Tracker rules | the planning stage |
| Plan | write-plan | "plan this", the kickoff chain, `/write-plan` | all, plus Reviewers for the plan review | the plan file's Steps |
| Verify | verify | the plan's Closing steps, `/verify` | Install command, Verify commands, Browser check | the review stage |
| Review | review-changes | the plan's Closing steps, `/review-changes` | Reviewers | the PR stage |
| Land | changes-to-pr | "commit and PR this", `/changes-to-pr` | Commit policy, Commit convention, PR shape, Remote, Ticket system | the push hook |
| Watch | pr-followup | the push hook | CI watcher, Ticket system | the merge stage |
| Merge | pr-merge | "merge the PR", `/pr-merge` | PR shape, Commit policy, Ticket system | done |

## Hooks, the glue

A hook lives in the `hooks/` directory of the skill it routes to, next to its `hooks.json`
fragment and fixtures; the composer wires them (see the repo README). commit-subject-gate
enforces a profile row rather than a skill, so it stays in the shared `.agents/hooks/`.

| Hook | Lives in | Event | Effect |
| --- | --- | --- | --- |
| workflow-profile-nudge | workflow-profile | SessionStart | injects the resolved rows, or nudges once to run the setup |
| pick-up-next-ticket | ticket-kickoff | UserPromptSubmit | routes "pick up the next ticket" to the kickoff, then planning |
| plan-nudge | write-plan | UserPromptSubmit | routes a planning phrase, or a task-shaped first prompt in plan mode |
| merge-nudge | pr-merge | UserPromptSubmit | routes "merge the PR" |
| kickoff-plan-chain | ticket-kickoff | PostToolUse Skill | chains the kickoff into planning |
| plan-gate, plan-followthrough | write-plan | ExitPlanMode, pre and post | hold the plan to the ten-heading contract, then order the post-approval steps |
| push-nudge | pr-followup | PostToolUse Bash | routes a git push or PR creation to the CI watch |
| commit-subject-gate | shared hooks | PreToolUse Bash | blocks a subject off the Commit convention row |

## Composing it differently

- A repo with `direct commits to main` stops at changes-to-pr's commit: pr-followup and
  pr-merge never fire, and nothing else changes.
- A repo with no tracker skips every ticket step; the same skills run.
- A repo that ships its own review skill gets it named in the plan next to review-changes.
- Adding a stage means one new skill that reads the rows it needs, and, when a phrase or an
  event should trigger it, one hook that routes to it.
