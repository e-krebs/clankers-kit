#!/usr/bin/env bash
# PostToolUse(Bash) hook: after a git push, gh pr create, or gh stack push/submit, nudge the
# agent to run the pr-followup skill so CI gets watched. Skips -h/--help/--dry-run runs.
# Fails open on bad stdin, a non-match, or a missing hook-log lib.
# codex: yes

input=$(jq -c 'select(type == "object")' 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -n "$cmd" ] || exit 0
HOOK_SESSION=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)

printf '%s' "$cmd" | grep -qE 'git[[:space:]]+push([[:space:]]|$)|gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$)|gh[[:space:]]+stack[[:space:]]+(push|submit)([[:space:]]|$)' || exit 0
printf '%s' "$cmd" | grep -qE '(^|[[:space:]])(-h|--help|--dry-run)([[:space:]]|$)' && exit 0

hooks_lib="${AGENTS_HOOKS_LIB:-$(dirname "${BASH_SOURCE[0]}")/../../../hooks/lib}"
[ -f "$hooks_lib/hook-log.sh" ] || hooks_lib="$HOME/.claude/hooks/lib"

jq -n '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:"A git push, gh pr create, or gh stack push/submit just ran. MANDATORY: run the pr-followup skill now (the Skill tool where it exists, else its SKILL.md) to watch CI and follow up. Do not merely tell the user to run it."}}'
# the nudge fires with or without the log; the write is best-effort
[ -f "$hooks_lib/hook-log.sh" ] && HOOK_SESSION="$HOOK_SESSION" bash "$hooks_lib/hook-log.sh" push-nudge nudge
exit 0
