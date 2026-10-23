# Lenses

Two sets: the prune flags a hook can carry, and the evidence sources a new hook can come from.
The user decides every flag and every candidate.

## Prune flags

| Flag | Check | Leans toward |
| --- | --- | --- |
| Dead | the hook's target (a tool, an event, a skill, a file) no longer exists | drop |
| Redundant owner | a rule with two or more enforcers (a hook plus an inline entry plus prose) | keep one hook, cut the rest |
| Overlap | two hooks on one event fire on one prompt with competing directives | one yields to the other |
| Over-reach | a rule that fires outside the case it was written for (a URL as a comment, npx in a repo without yarn) | scope or relax |
| Untested deny | a hook that denies and has no fixture suite | add-fixture |
| Silent rule | zero lines in the event log for a rule of a logging hook | drop, once the log and the rule are both 30+ days old |
| Prose owner | `AGENTS.md` restates a hook | keep both when Codex or Cursor read the prose |

Silent rule applies only to the hooks that call `hook_log` (from `lib/hook-log.sh`, directly
or through `lib/prompt-guards.sh`). Grep the hook roots for `hook_log` rather than trusting a
list. Read the log's earliest line and the rule's first commit first. When either is under 30
days old, the flag reads "no signal yet". The two campaign nudges also write `skip` lines, so
zero `nudge` lines beside `skip` lines means wired but never matched, not dead. An allowlist
entry wider than its deny rule (`echo`, `find`, `sort`) is by design, because the hook comments
name the allowlist as the reason the rule exists.

## Suggestion sources

Each source yields candidate rows. A row: rule (one line), evidence and count, event and
matcher, field and regex, cost. Cost: small is one regex and one fixture case, medium needs
session state or a profile row, large is a new script with its own suite.

A row stays only when it passes the mechanical test, meaning a script could check the rule
from a tool input or a prompt. A rule that needs context a script cannot see is judgment and leaves the
table with a one-line reason.

### 1. Feedback memories

`find -H ~/.claude/projects -path '*/memory/feedback_*.md'` (symlinked stores are not followed,
so each memory lands once). Each file is a correction the user gave once. Read the rule, apply
the mechanical test, name the event and matcher, and check whether a hook already covers it.

### 2. Mechanical prose rules

Packet 2's list B from the inventory. Each unenforced mechanical rule is a row with the event
and matcher the packet named.

### 3. Transcript corrections

The transcripts `~/.claude/projects/*/*.jsonl` are local and gitignored. The sample is the
transcripts modified in the last 30 days (`find -H ~/.claude/projects -name '*.jsonl' -mtime
-30`), shared by sources 3 and 5. A user turn counts only after the filter below. Without it,
hook and skill boilerplate re-enters the transcript as synthetic user turns and outnumbers real
corrections fourteen to one.

```
jq -r 'select(.type=="user") | .message.content
       | if type=="array" then map(select(.type=="text") | .text) | join(" ") else . end
       | select(test("<task-notification>|\\[SYSTEM NOTIFICATION|<command-name>|<local-command|<ide_selection|Stop hook feedback|Base directory for this skill") | not)
       | gsub("\n"; " ")' <file>.jsonl \
  | grep -iE "don'?t|do not|never|always|stop |no,|instead"
```

The marker test runs on the whole turn inside `jq`, before `gsub` flattens newlines, because a synthetic
turn whose later lines read like an instruction would otherwise survive a line-wise grep.

A correction that repeats across sessions, or that names a concrete command or format, is a row.
A one-off task instruction is not.

### 4. Hook event log

Packet 3's per-hook, outcome and rule counts from the inventory. Make no second pass over the log.
A deny rule that fires often is a prompt the agent keeps hitting. Check whether the deny message
names the alternative, and whether a nudge would preempt it. A nudge that fires often with a
typed skill right after it is working. The zero-count rules feed the Silent rule flag above.

### 5. Typed skills and repeated commands

Count typed skills across the sampled transcripts:

```
grep -oh '<command-name>/[a-z-]*' <sampled files> | sort | uniq -c | sort -rn
```

For a skill typed three or more times, read the user prompt before each invocation. A shared
phrase across those prompts is a nudge candidate on UserPromptSubmit, in the shape of
merge-nudge. A Bash command repeated across three or more sessions (grep the `tool_input.command`
fields) is an automation candidate: a skill, or a PostToolUse nudge after the command that
precedes it.
