---
name: ticket-kickoff
description: "Kick off a ticket: read it and any linked spec, then hand the work to planning. Use when picking up or kicking off a ticket, either a specific ID or the next one to start ('pick up the next ticket'). Not for bulk-creating tickets, querying tracker status, or sprint management."
---

# ticket-kickoff

The first stage of the ticket lifecycle: identify the ticket, read it, then hand the work to
planning. The started move and a confirmed create run during the kickoff, both best-effort; a
write the harness refuses in plan mode goes to planning, for the plan's kickoff row S0.

## Profile

Read the workflow profile rows from context, where the session-start hook injects them. When they
are absent, run `bash ~/.agents/skills/workflow-profile/scripts/resolve-profile.sh --rows`. With no
rows and no script, say the profile setup is missing and take the no-tracker branch.

Done when the rows are in hand and the Ticket-system branch is chosen.

## Step 0 — Resolve, read and start the ticket

This step runs only when Ticket system names a tracker. When it reads `none`, say in one line that
the repo has no tracker and go straight to Step 2, with no ticket question and no tracker call.

The tracker mechanics (id detection order, transitions, picker, best-effort contract) live only in
the `## Tracker rules` section of the org profile file, the first path
`resolve-profile.sh --files` prints. Read that section and follow it.

- Identify the ticket through the rules' detection order. With nothing detected, offer the rules'
  picker over the user's not-started tickets; with nothing there either, take Step 1.
- Read the ticket into a concise digest: goal, an acceptance-criteria checklist, type, status,
  assignee, linked issues and subtasks. Request only those fields. Pull any directly linked spec
  page (PRD, RFC) as planning context; a long page goes to a read-only subagent that returns only
  its requirements, acceptance criteria and open questions. When the tracker or doc space is
  unreachable, skip that read, note it in the digest, and keep going.
- Last, check the ticket's status. When it is already in the work-started state, skip the move
  silently. Otherwise resolve the move to that state (a matched transition, or the picker
  candidates when none matches) and run it now, best-effort: an error is reported and the kickoff
  goes on. When the harness refuses the write in plan mode, carry the resolved move to planning
  for row S0 instead.

Done when the ticket is identified, its digest and any linked spec are read (or noted
unreachable), and the work-started move is done, skipped, failed or handed to planning, or when
the no-tracker branch was taken.

## Step 1 — No ticket? Offer to create one

Draft a title and description from the scoped intent, then ask whether to create a ticket. On
yes: show the draft for confirm or edit, then gather the fields a create needs: parent or epic,
the current sprint, the assignee. Prefer an available ticket-creation capability for the create
itself, since it handles hierarchy, sprint sizing and custom-field discovery; fall back to an inline
best-effort create with the gathered fields when none is available. A confirmed create runs at
once, best-effort, and the new ticket then takes the Step 0 started move. When the harness
refuses the create in plan mode, carry the confirmed draft and its fields to planning for row S0.
On no, the draft goes in the plan file and no tracker write follows.

Done when the ticket is created, handed to planning, or kept as a draft.

## Step 2 — Hand off to planning

The planning capability takes over. It explores the codebase against the digest, interviews the
user, and writes the plan file to the plan contract. Hand it the digest and the outcomes: the
ticket key or the draft, and whether the started move and any create ran, failed, or were
refused in plan mode. A refused write becomes part of the plan's row S0, which also holds the
base-branch refresh when the profile has a remote. The planning capability owns that row and the
refresh.

Done when the planning capability holds the digest and the outcomes.

## Gotchas

- Tracker and doc-page calls prompt for permission unless allowlisted.
- Without an acceptance-criteria checklist in the digest, the plan's Steps section has no criteria
  to derive steps from. When the ticket carries no criteria, draft them from the goal and say they
  are drafted.
