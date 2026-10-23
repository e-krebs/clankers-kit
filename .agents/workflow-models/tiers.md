# Model tiers

Pick the tier from the shape of the work. `<provider>.md` next to this file maps each tier to a
model and effort for that provider. Skills never name a tier: the agent that dispatches a
worker picks the tier from this table by the shape of the work.

| Tier | Shape of work | Kind |
| --- | --- | --- |
| trivial | run a deterministic command or lookup, no interpretation or implementation choices | worker |
| routine | apply an established pattern locally, minor choices, solution already apparent | worker |
| focused | solve a self-contained problem, needs reasoning, dependencies stay local | worker |
| coupled | coordinate changes across components, dependencies matter, design and behavior already settled | worker |
| judgment | resolve ambiguous behavior, subtle correctness or tradeoffs, needs sustained unified reasoning | worker |
| executor | run an approved plan: dispatch rows to workers, read short reports, triage findings, merge results | run |
| planner | write the plan: split work into rows, choose a tier for each from this table, name the checks | write |

Kind is a protocol word the hooks read, whatever the Tier is called: `worker` is delegable and has
a subagent, `run` is the session that runs an approved plan and is not delegable, `write` is the
session that writes the plan and is not delegable.

When two tiers fit, pick the lower one unless you can name the uncertainty or dependency that
needs the higher one. File count and task length alone do not justify a higher tier. Keep
difficult, tightly coupled work at `judgment`, not at the tier that runs a plan.
