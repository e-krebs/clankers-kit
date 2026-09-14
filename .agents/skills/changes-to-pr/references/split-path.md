# Draft-a-ticket branch and the split path

## Draft-a-ticket branch (Gate 1, item 1)

Reachable only when the profile's Ticket system names a tracker. From the Step 0 analysis, draft a
ticket description (summary + body) and show it for confirm or edit. **Once that description is
confirmed**, ask for the ticket ID: the user creates the ticket from the draft — optionally handing
the draft to an available ticket-creation capability, which handles create, hierarchy and sprint
sizing — then provides the ID. Continue to Step 2 with the ID in hand, so Gate 2's PR description
already carries the reference the Commit convention row allows.

## Split path (Gate 1, item 3)

Under `PRs, never direct`: run Steps 2-4 once **per concern**. Each concern gets its own branch,
its own atomic commits, its own description, and its own PR. Its `<pr-base>` is Gate 1 item 2's
binding applied per concern: under independent, every concern is cut from `<base>` and opens
against it; under stacked, the first concern is cut from the branch the user was on and each later
one from the concern before it, and each PR opens against that same branch — so the Nth PR's diff
is the Nth concern alone, not the N concerns below it. Present the per-concern plans together at a
single Gate 2. The tracker move runs **once** for the ticket, up front, before the first concern's
commits — Gate 1 collects a single ticket.

Under a PR shape carrying the stack clause, and under the stacked Gate 1 answer only, branches and
commits still run once per concern, bottom to top, while the stack is tracked once and submitted
once for the whole set. [gh-stack-path.md](gh-stack-path.md) owns that, and its P2 or P3 is this
loop. The independent answer keeps the plain items, because sibling branches off the trunk are not
a stack.

Under `direct commits to main` there is no branch and no PR to split: the split becomes one commit
group per concern on the default branch, presented together at Gate 2 and committed in the order
the user chose. Same for a `local-only` remote, where the run ends at those commits.
