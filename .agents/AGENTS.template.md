# About {{NAME}}

<!--
  Your personal AGENTS.md — read by Claude Code as ~/.claude/CLAUDE.md and by Codex as
  ~/.codex/AGENTS.md, on every turn, so keep it terse and high-signal. AGENTS.example.md is a
  filled-in version for reference. Delete these guidance comments as you fill each section in.
  setup.sh seeds this from the answers you gave; flesh out the rest.
-->

## Role

- {{ROLE}}
<!-- who you are: seniority, what you own, whether you work across teams, your bias (frontend / backend / infra / data) -->

## Language

{{LANGUAGE}}
<!-- optional: your native language, how to read your typos, when to confirm ambiguous wording -->

## Communication style

- Cite code with a clickable `path/to/file.ts:42` reference
- For refactors and multi-file changes, propose an approach before touching code
{{COMMS}}
<!-- how should the agent talk to you and present work? propose-approach-first? ask-when-ambiguous?
     proportional solutions? preferred comment style? -->

## Tool & command preferences

<!-- shell / tool habits — e.g. save long-running output to a file and re-grep it; prefer file tools over raw shell -->

## Workflow habits

- One concern per PR
- A mechanical rule gets a hook, not prose: spec text alone doesn't hold, so enforceable rules go into hooks and the instructions file keeps the judgment calls
{{WORKFLOW}}
<!-- plan-first? one-concern-per-PR? commit convention? how do you want changes verified before "done"? -->
