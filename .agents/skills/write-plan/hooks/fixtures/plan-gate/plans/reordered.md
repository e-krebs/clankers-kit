## Context
Why we need this, what prompted it, and the intended outcome.

## Decisions
Use the lighter approach; the user picked it over the heavier alternative.

## Approach + Files
The one recommended approach touches two files.

## Ticket
n/a

## Model pick
Tier: everyday. Claude: Sonnet. Codex: Sol. Rationale: well-scoped, several files, known
conventions. Switch: `/model sonnet`.

## Deferred kickoff actions
n/a

## Steps + delegation
1. Do the thing (worker).
2. Check the thing (judge).

## Verification
Run `yarn test`.

## Closing steps
1. Verify, then review (judgment tier x1), then hand off to the PR capability.

## Plan review
Codex (read-only) reviewed this plan and found no issues.
