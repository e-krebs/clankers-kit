# Draft-a-ticket branch and the split path

## Draft-a-ticket branch (Gate 1, item 1)

Reachable only when the profile's Ticket system names a tracker. From the Step 0 analysis, draft a
ticket description (summary + body) and show it for confirm or edit. **Once that description is
confirmed**, ask for the ticket ID: the user creates the ticket from the draft — optionally handing
the draft to an available ticket-creation capability, which handles create, hierarchy and sprint
sizing — then provides the ID. Continue to Step 2 with the ID in hand, so Gate 2's PR description
already carries the reference the Commit convention row allows.

## Split path (Gate 1, item 3)

Under `PRs, never direct`: run Steps 2-4 once **per concern**. Each concern gets its own branch off
the chosen base (independent off `<base>`, or stacked on the previous concern's branch, per the
Gate 1 base choice), its own atomic commits, its own description, and its own PR. Present the
per-concern plans together at a single Gate 2. The tracker move runs **once** for the ticket, up
front, before the first concern's commits — Gate 1 collects a single ticket.

Under `direct commits to main` there is no branch and no PR to split: the split becomes one commit
group per concern on the default branch, presented together at Gate 2 and committed in the order
the user chose. Same for a `local-only` remote, where the run ends at those commits.
