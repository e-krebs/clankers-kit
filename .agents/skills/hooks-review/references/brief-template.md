# Hook brief template

One file per approved candidate at `~/.claude/plans/hook-<slug>.md`. It is self-contained: a
later planning session reads it with no transcript. Six headings, in this order.

```markdown
# Hook brief — <rule in one clause>

## Problem

<The rule, who stated it, and what goes wrong when it is missed. Two or three sentences.>

## Evidence

<One line per item: the source (memory file, transcript date and session, prose file:line,
log count), with a link where one exists. The count from the candidate table.>

## Hook sketch

- Event and matcher: <PreToolUse Bash | UserPromptSubmit | PostToolUse Write|Edit | ...>
- Field and test: <the stdin field and the regex or condition>
- Outcome: <deny with this reason text | additionalContext with this text>
- Fail-open: <what the hook does on malformed input, a missing profile, a subagent>
- Wiring: <Claude only, or Codex too, with the reason>

## Fixture cases

<One line per case: name, input shape, expected deny or silence.>

## Acceptance

<The suite command, and one live check that shows the hook firing once.>

## Commit shape

`<type>(hooks): <subject>` for <the hook, its suite, the wiring entries>.
```
