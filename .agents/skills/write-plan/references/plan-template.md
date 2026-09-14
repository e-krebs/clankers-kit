# Plan template

Ten `## ` headings, in this order, spelled exactly as below — a hook parses them. Replace each
hint with content. Ticket, Deferred kickoff actions and Verification may read `n/a`; the other
seven always carry content. The order after Model pick mirrors the run order: kickoff actions,
then steps, then verification, then the closing steps.

```markdown
# Plan — <one clause naming the change>

Source: <brief path, ticket key, or the request in one line>. <Who decided what, and where.>

## Context

<Why now, what prompted it, and the outcome once it lands. Three to five sentences.>

## Decisions

<Every decision the interview and the review settled, one line each: the choice, who made it,
the alternative it beat. A reader must not need the transcript to know why the plan looks like
this.>

## Ticket

<The linked ticket as a link, or a drafted title plus description when the profile names a
tracker and no ticket exists yet. `n/a` when the profile names no tracker.>

## Approach + Files

<The one recommended approach in a short paragraph, then every file it touches, one per line
with what changes in it. Alternatives belong here only when the user rejected one explicitly.>

## Model pick

<Tier from the tiers table, the model that tier maps to for the provider running the build, a
one-line rationale, and the command that switches: `/model opus`. Name a real model; a
placeholder here is denied at the gate.>

## Deferred kickoff actions

<Mutations that run on approval, not before: create the ticket from the Ticket section, refresh
the base branch, move the tracker to its started state using the profile's Tracker rules. `n/a`
when none apply.>

## Steps + delegation

<Ordered steps. Tag each `judge` (stays with the main agent) or `worker` (delegated, with the
tier it runs at). Every worker that writes files or runs a gate gets its own worktree; parallel
read-only workers share the tree. Name the skill each step invokes: `/<verify skill>`,
`/<repo review skill>`.>

## Verification

<The gate commands the profile lists, with their working directory, and the skill that runs
them (`/<verify skill>`). Add the browser pass when the change is user-facing: the profile's dev-server
command, the base URL, the page path, and whether the check is network + console (behavioural)
or a screenshot (visual). `n/a` when neither applies.>

## Closing steps

1. Gates: `/<verify skill>`.
2. Review, <tier> tier x <count>: `/<review skill>` on the working tree, `/<repo review
   skill>` on the changed <language>. <Count comes from the size rule over the profile's
   Reviewers row.>
3. Hand-off: `/<pr skill>`. Commit split: `<type>(<scope>): <subject>` for <files>;
   `<type>(<scope>): <subject>` for <files>.

## Plan review

<Which independent agents reviewed this plan before approval, when, how many findings each
returned, and what changed as a result. Name an agent; the gate checks for one. An edit to the
plan after this review adds a line here once the plan is re-reviewed.>
```

## Rules the template carries

- Every step is written as a step. Nothing reads "default yes", and nothing is offered: the
  user deletes the steps they decline before approving.
- The `/<...>` placeholders are filled from the skills installed in the session that writes the
  plan, by name, in every section. The template itself names none.
- The tables in a plan keep a source line when their numbers come from somewhere — a command,
  a query, a transcript.
- When the plan lives in HTML (see the HTML rendering reference), the markdown file is a stub:
  the H1, one `Source: <plan>.html` line, then the ten headings with one pointer line each.
