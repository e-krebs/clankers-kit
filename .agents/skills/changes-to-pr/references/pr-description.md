# PR description — section rules and the review block

Apply these repo-agnostic principles when drafting the PR body from the repo's PR template:

- Be concise — a sentence or short bullets per section; describe key choices, not a code
  walkthrough.
- Fill conditional sections (environment variables, dependencies) **only** when Step 0 detected
  them.
- Put the ticket reference where the profile's Commit convention row allows it. Under "ticket ref
  in PR body only" that is the motivation / "why" section alone, where the forge autolinks it;
  omit it when there is no ticket or no tracker.
- Keep the sections the template marks as always-present (screenshots, previews); omit sections
  that have no content.
- Honor the PR-description conventions already in context — the repo's CLAUDE.md, your memory —
  such as what belongs in a Testing / QA section.

## Agent review section

When a review ran (just now, or earlier this session), add a short "Agent review" section:

- what was looked at, and what was not assessed (coverage)
- a summary of the findings plus an overall verdict
- one line naming which findings were applied to the tree and which were left as reported

Omit it entirely when no review ran. On an existing PR, replace a prior "Agent review" section
rather than stacking a second one.
