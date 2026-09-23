# Inventory prompts

Three read-only worker packets, launched in one message. Each opens with the config repo
root, the read-only rule, and the Bash constraints (no `xargs` beyond grep, wc and ls, and no
`echo` of `$(...)` or an UPPERCASE variable; the Read, Grep and Glob tools first). Each closes with "return
file:line for every claim and an uncertainties list; propose no fixes". Adjust the file lists
when the layout moves.

## Packet 1 — wiring and triggers

Scope: every `.agents/hooks/*.sh`, `.agents/skills/*/hooks/*.sh`, `.agents/hooks/lib/*.sh`,
every `hooks.json` fragment (`.agents/hooks/hooks.json`, `.agents/skills/*/hooks/hooks.json`),
the composed `hooks` key of `.claude/settings.json` and `.codex/user-hooks.json` including
their inline command entries, and every `fixtures/<name>/run.sh` under both hook roots.

Per script, report:

1. The event and matcher it is wired on in each wiring file, or "Claude-only".
2. What it does in one line (denies X, injects Y, side effect Z) with the exact deny or context
   text it emits, trimmed to 120 chars.
3. Its trigger: the regex or keyword list, quoted.
4. Every external target: skills it tells the agent to run (check each exists under
   `.agents/skills/<name>/SKILL.md`), files it reads, env vars, binaries.
5. Its fixture suite and case count, or "none".
6. Header claims that look stale (a tool, path, flag or env var absent from the repo).

Then the cross-hook overlaps: pairs on one event with overlapping triggers or competing
directives, quoted with file:line. Then the inline entries with the same six fields.

## Packet 2 — prose against hooks

Scope: `.agents/AGENTS.md`, `.claude/output-styles/*.md`, every `.agents/skills/*/SKILL.md` and
`references/*.md`, `README.md`, against what the hooks enforce (read each hook's header and its
deny or context strings first).

Report three lists, each item with file:line and the quoted line trimmed to 150 chars:

- A. Hook-redundant prose: a sentence restating what a hook already denies or injects. Name the
  hook. Note when the prose also serves a reader without that hook (Codex, Cursor).
- B. Unenforced mechanical rules: prose stating a checkable rule that no hook enforces.
  Mechanical means a script could check it from a tool input or a prompt. Say which event and
  matcher a hook would need.
- C. Contradictions: prose against a hook, hook against hook, the `permissions.allow` list
  against a deny rule, or a skill step that types a command the hooks deny.

Then dead references: prose naming a hook, file, env var, path or skill that no longer exists.

## Packet 3 — history and signals

Per hook script:

1. First commit (date, subject) with `git log --follow --diff-filter=A`, and the last commit
   that changed its logic (ignore renames and wording-only commits). Run each `--follow` query
   alone: a parallel batch cross-contaminates the output.
2. Commits whose subject names the hook.
3. Its fixture suite result: run its `fixtures/<name>/run.sh` (under `.agents/hooks/` or the
   owning skill's `hooks/`) as one call per suite and report the PASS and FAIL counts.

Then the memory signals: lines in `.claude/projects/*/memory/*.md` (never the `.jsonl`
transcripts) that name a hook, a deny message, or a workaround for one.

Then the event log: `~/.claude/hook-events.log`, lines of `<stamp> <session> <hook> <outcome>
<rule>`. Report the log's earliest date, and the count per hook, outcome and rule
(`cut -d' ' -f3-5 | sort | uniq -c | sort -rn`). List the logging hooks with zero lines.

Then the two housekeeping hooks (`session-cleanup.sh`, `canonical-memory.sh`): what each
cleans or creates, whether the target is present on this machine, and whether another script
does the same job.
