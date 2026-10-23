# Claude models per tier

[tiers.md](tiers.md) says which tier fits the work. Models are aliases that track the latest
generation; edit this file when that changes. Effort comes from the agent definition, not the
call: dispatch a subagent with `subagent_type: <tier>` to get both. The tiers that run and write a plan
are agents too, so a new session starts as one with `claude --agent <tier>`. A main session switches the model with
`/model <model>` and the effort with `/effort <level>`.

| Tier     | Model  | Effort |
| -------- | ------ | ------ |
| trivial  | haiku  | low    |
| routine  | haiku  | low    |
| focused  | haiku  | medium |
| coupled  | haiku  | medium |
| judgment | sonnet | low    |
| executor | sonnet | low    |
| planner  | sonnet | medium |
