---
name: ticket-kickoff
description: "Kick off a ticket: read it and any linked spec, then hand the work to planning. Use when picking up or kicking off a ticket — a specific ID, or the next one to start ('pick up the next ticket'). Not for bulk-creating tickets, querying tracker status, or sprint management."
---

# ticket-kickoff

The front door of the ticket lifecycle: identify the ticket, read it, then hand the work to
planning. Every read happens now; every mutation waits for plan approval.

## Profile

Read the workflow profile rows from context — the session-start hook injects the resolved table.
When they are absent from context, run
`bash ~/.agents/skills/workflow-profile/scripts/resolve-profile.sh --rows` and read its table. Ticket system decides whether
Step 0 runs at all.

Done when the rows are in hand and the Ticket-system branch is chosen.

## Step 0 — Resolve and read the ticket (read-only)

This step runs only when Ticket system names a tracker. When it reads `none`, say in one line that
the repo has no tracker and go straight to Step 2 — no ticket question, no tracker call.

The tracker mechanics live in the profile's `## Tracker rules` section: workspace/cloud id
resolution, the ticket-ID detection order, transition discovery by target status, the picker for
when no transition targets the wanted state, and the best-effort contract. Read that section and
follow it — it is the single source of those rules.

- Identify the ticket through the rules' detection order. With nothing detected, offer the rules'
  picker over the user's not-started tickets; with nothing there either, take Step 1.
- Read the ticket into a concise digest: goal, an acceptance-criteria checklist, type, status,
  assignee, linked issues and subtasks. Pull any directly linked spec page (PRD, RFC) as planning
  context. An unreachable tracker or doc space means skipping that read, not stopping.
- Resolve the move to the tracker's work-started state, and carry forward which outcome applies:
  a matched transition, the picker candidates, or nothing applicable.

Done when the ticket is identified, its digest and any linked spec are read, and the work-started
move is resolved — or the no-tracker branch was taken.

## Step 1 — No ticket? Offer to create one

Ask whether to create a ticket. On yes: draft a title and description from the scoped intent, show
them for confirm or edit, then gather the fields a create needs — parent or epic, the current
sprint, the assignee. Prefer an available ticket-creation capability for the create itself, since
it handles hierarchy, sprint sizing and custom-field discovery; fall back to an inline best-effort
create with the gathered fields when none is available. Creating is a mutation, so it is deferred
to plan approval. On no, the drafted ticket rides in the plan file and no tracker move is queued.

Done when the create-or-draft choice is settled with its fields.

## Step 2 — Hand off to planning

The planning capability takes over. It explores the codebase against the digest, interviews the
user, and writes the plan file to the plan contract; its Deferred kickoff actions section
carries the lines this kickoff produced — create the ticket, refresh the base branch, move the
ticket to the work-started state — and it owns the base-refresh question.

On plan approval the deferred actions run in the order that section lists them, best-effort on
the tracker move.

Done when the planning capability holds the digest, the create-or-draft outcome, and the resolved
move.

## Gotchas

- Tracker and doc-page calls prompt for permission unless they are allowlisted.
- A digest without an acceptance-criteria checklist starves the plan's Steps section; when the
  ticket carries no criteria, draft them from the goal and say they are drafted.
