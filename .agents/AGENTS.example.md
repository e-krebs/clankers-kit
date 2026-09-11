# About [example persona — this is a sample, not you]

> A worked **example** of a personal `AGENTS.md`, modeled loosely on the author's real one.
> It's here to show the *shape* of a good one — read it, then run `./setup.sh` to generate
> your own from the blank template (or copy this file and edit). Keep it terse: every line is
> context the agent re-reads on every turn, so earn each one. Claude Code reads it as
> `~/.claude/CLAUDE.md`; Codex reads it as `~/.codex/AGENTS.md`.

## Role

- Senior frontend engineer; work routinely spans several teams, not just my own
- Lean toward architectural work — reusable abstractions, conventions, codebase-wide refactors — not only feature work

## Language

- Native French speaker; English is a second language — expect the occasional awkward phrasing or typo
- For explanations and brainstorming, interpret intent generously; don't get hung up on a typo
- For action requests with consequences (git ops, deletes, deploys), if a word is ambiguous, confirm before acting

## Communication style

- Cite code with a clickable `path/to/file.ts:42` reference; a repo file named in prose takes that link too, not just inline code
- For refactors and multi-file changes, propose an approach before touching code
- When a request has more than one plausible reading, ask which I meant; for routine choices with one clear answer, just make it and say so
- Keep solutions proportional — the lightest option that catches realistic mistakes; flag heavier or cleverer approaches as opt-in rather than applying them by default
- Comments: terse or none. Omit any comment that restates a well-named symbol; reserve comments for the non-obvious *why*. Match the file's existing comment density

## Tool & command preferences

- For long-running commands: run once, save the output to a file, then re-grep the file instead of re-running (re-running wastes minutes and burns the prompt cache)
- Prefer the dedicated file tools (read / edit / search) over their raw shell equivalents

## Workflow habits

- Plan-first: for non-trivial or ambiguous work, plan before starting
- One concern per PR — split a change that mixes a refactor, a new feature, and a bugfix
- A mechanical rule gets a hook, not prose: spec text alone doesn't hold, so enforceable rules go into hooks and this file keeps the judgment calls
- Conventional commits with a scope: `feat(scope): …`, `fix(scope): …`, `chore(scope): …`; append a tracking-ticket id when there is one
- Verify UI changes in a real browser before calling them done — for behavioral changes, check the network and console too, not just a screenshot
- Before starting, write the plan (and any tracking ticket) somewhere durable — not just in chat, which is easy to lose
