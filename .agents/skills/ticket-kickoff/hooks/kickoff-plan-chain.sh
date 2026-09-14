#!/usr/bin/env bash
# PostToolUse hook on the Skill tool: once ticket-kickoff finishes, chains into the planning skill.
# Advisory only. Wired: PostToolUse, matcher Skill.
# codex: no

input=$(jq -c 'select(type=="object")' 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0

HOOK_SESSION=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)

agent_id=$(printf '%s' "$input" | jq -r '.agent_id // empty' 2>/dev/null)
[ -z "$agent_id" ] || exit 0

skill=$(printf '%s' "$input" | jq -r '.tool_input.skill // empty' 2>/dev/null)
[ "$skill" = "ticket-kickoff" ] || exit 0

hooks_lib="${AGENTS_HOOKS_LIB:-$(dirname "${BASH_SOURCE[0]}")/../../../hooks/lib}"
[ -f "$hooks_lib/prompt-guards.sh" ] || hooks_lib="$HOME/.claude/hooks/lib"
# shellcheck source=../../../hooks/lib/prompt-guards.sh
source "$hooks_lib/prompt-guards.sh" || exit 0
emit_context "PostToolUse" "Ticket read. Invoke the planning skill, the installed skill whose description covers writing the plan file, via the Skill tool once the ticket digest is in context."
exit 0
