#!/usr/bin/env bash
# PostToolUse(Bash) hook: after a git push, gh pr create, or gh stack push/submit, nudge the
# agent to run the pr-followup skill so CI gets watched. Skips -h/--help/--dry-run runs, and
# skips while a fresh "push-nudge-hold" file sits in the repo's git common dir: a stack submit
# writes it before publishing and removes it after its own follow-up pass, then triggers the watch
# itself. A hold older than 30 minutes is ignored and removed, so a crashed run cannot mute the nudge.
# Fails open on bad stdin, a non-match, or a missing hook-log lib.
# codex: yes

input=$(jq -c 'select(type == "object")' 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -n "$cmd" ] || exit 0
HOOK_SESSION=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)

printf '%s' "$cmd" | grep -qE 'git[[:space:]]+push([[:space:]]|$)|gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$)|gh[[:space:]]+stack[[:space:]]+(push|submit)([[:space:]]|$)' || exit 0
printf '%s' "$cmd" | grep -qE '(^|[[:space:]])(-h|--help|--dry-run)([[:space:]]|$)' && exit 0

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
common=$(git -C "${cwd:-.}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
if [ -n "$common" ] && [ -e "$common/push-nudge-hold" ]; then
  [ -n "$(find "$common/push-nudge-hold" -mmin -30 2>/dev/null)" ] && exit 0
  rm -f "$common/push-nudge-hold" 2>/dev/null
fi

hooks_lib="${AGENTS_HOOKS_LIB:-$(dirname "${BASH_SOURCE[0]}")/../../../hooks/lib}"
[ -f "$hooks_lib/hook-log.sh" ] || hooks_lib="$HOME/.claude/hooks/lib"

jq -n '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:"A git push, gh pr create, or gh stack push/submit just ran. MANDATORY: run the pr-followup skill now (the Skill tool where it exists, else its SKILL.md) to watch CI and follow up. Do not merely tell the user to run it."}}'
# the nudge fires with or without the log; the write is best-effort
[ -f "$hooks_lib/hook-log.sh" ] && HOOK_SESSION="$HOOK_SESSION" bash "$hooks_lib/hook-log.sh" push-nudge nudge
exit 0
