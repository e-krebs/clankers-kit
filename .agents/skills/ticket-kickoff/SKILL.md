---
name: ticket-kickoff
description: Kick off work from a tracker item — read the issue and any linked spec (PRD/RFC), plan in plan-mode, then on approval move it to In Progress. Use when picking up or kicking off a ticket — a specific one (PROJ-42) or your next To Do ("pick up the next ticket"). Don't use to query status or bulk-edit issues.
---

# ticket-kickoff

The front door of the work lifecycle. Read the tracker item, lean on your **normal plan-mode
flow** for the planning itself, and on plan approval move the item to **In Progress**. Reads
happen while planning; every mutation is deferred until you approve the plan.

## Safety

- All tracker / spec-doc / codebase reads are **read-only**.
- Mutations — creating an item, refreshing the base branch, the In Progress move — are **deferred
  until plan approval (`ExitPlanMode`)**; nothing mutates while planning. To skip one, drop its
  line from the plan before approving.
- The In Progress move is **best-effort** — a tracker error never blocks the work, and the move is
  silently skipped when none applies (no item / already In Progress / tracker unreachable).
- Don't invent an existing item's content — read it. (Drafting a new item in Step 1 is authored
  from the scoped intent and confirmed with you.)

## Step 0 — Resolve & read (read-only)

- Authenticate / resolve access to your tracker if it needs it (cache any workspace or project id
  so you resolve it once).
- Identify the item: an explicit ID in the prompt · else auto-detect an issue key (`[A-Z]{2,}-\d+`)
  in the branch name / `<base>..HEAD` commits · else a "mine, not started" picker via a tracker
  query (items assigned to you with a not-started status, highest priority first) · else the
  no-item path (Step 1).
- Read it → a concise **digest**: goal, an **acceptance-criteria checklist**, type, status,
  assignee, linked items/subtasks. Pull any linked **spec doc (PRD/RFC)** — directly-linked pages
  only — as planning context.
- Discover the In Progress transition: read the item's available transitions and pick the one
  whose **target status** (case-insensitive) is **In Progress** — match the target, not the
  transition's display name (e.g. a transition called "Start Progress" lands on "In Progress").
  Outcomes to carry forward: a matched transition · the candidate list (when transitions exist but
  none target In Progress, for a picker) · nothing-applicable (already In Progress, or tracker
  unreachable — skip silently).

## Step 1 — No item? Offer to create (read-only gathering)

Ask whether to create a tracker item. If yes: draft a **title + description** from the scoped
intent and show it for confirm/edit, then gather — which **parent/epic**, **add to the current
sprint/iteration?**, **assign to me?**. Prefer an **available issue-creation skill or tool** for
the actual creation (it handles parent links, sprint, and custom-field discovery); fall back to
your tracker's create API (with the gathered fields) when none is available. Creation is a
mutation → **deferred to exit**. If creation is declined, draft the item into the plan file and
skip the move (the real item gets created later, when the work is done).

## Step 2 — Plan (normal plan-mode flow)

Lean on your standard plan-mode planning — explore the codebase guided by the item/spec, draft the
plan file (context from the item, approach, the acceptance-criteria checklist, files to touch,
verification). Don't re-specify your planning flow here.

Record a **Deferred kickoff actions** block in the plan file (each line droppable by editing):
create the item (if chosen) · refresh the base (if chosen) · move `<ITEM>` (`<current> → In
Progress`), or the picker candidates if no transition targets In Progress. Listing them explicitly
keeps them surviving into the post-approval turn.

## Step 3 — Approve & kick off (`ExitPlanMode` → deferred execution)

On approval, run the chosen deferred actions in order:

1. **Create item** (if chosen) — via the delegated creation skill/tool, or the create-API fallback.
2. **Refresh base** (if chosen) — `git fetch` and bring the base branch current with origin.
3. **In Progress move** — transition the item to In Progress via the resolved transition id; report
   the move. Best-effort — on error, report and continue.

Then work begins.

## Gotchas

- Item **already In Progress** → no move.
- **No transition targets In Progress** → offer a picker of available transitions plus Skip. Match
  on target status, not the transition's display name.
- **Tracker / spec-doc unreachable** → skip that read and proceed; never block the work.
- Every mutation is **deferred to plan approval**. If you catch yourself creating or transitioning
  an item while still planning, stop — that belongs in the post-`ExitPlanMode` turn.
- Tracker write calls (create / transition) may **prompt for permission** unless allowlisted.
