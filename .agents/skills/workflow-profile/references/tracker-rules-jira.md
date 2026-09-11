# Tracker rules — Jira template

Append the section below to the org template, replacing `<PROJECT>` with its Jira project key.

## Tracker rules

Jira states in `<PROJECT>`: In Progress (work started), In Review (PR live and green), Done (PR merged).

1. Transition by target status. Read the ticket's transitions and pick the one whose target status (`transition.to`, case-insensitive) equals the wanted state. Match the target, not the transition's display name: a transition called "Start Progress" lands on "In Progress".
2. Resolve `cloudId` once per session through `getAccessibleAtlassianResources`, cache it, and use the UUID, not the hostname.
3. Every tracker move is best-effort. A Jira error never blocks the work: report it and continue. Skip the move silently when none applies: no ticket, already in the target state, or Jira unreachable.
4. Ticket-ID detection order: an explicit ID in the prompt, then `[A-Z]{2,}-\d+` in the PR body when a PR exists (the motivation line first), then in the branch name, then in the commits since the base, taking the first match.
5. When transitions exist but none targets the wanted state, offer a picker of the available transitions plus Skip, never a silent guess.
6. The not-started picker runs `searchJiraIssuesUsingJql` with `assignee = currentUser() AND status = "To Do" ORDER BY priority DESC`.
7. Read a ticket with `getJiraIssue` and `responseContentFormat: "markdown"`, and a directly linked Confluence PRD or RFC with `getConfluencePage` in markdown; never crawl a page tree.
