#!/usr/bin/env bash
# UserPromptSubmit hook, advisory: replaces the inline settings.json entry that named
# alg-ticket-kickoff. Chains a "pick up the next ticket/PR/task" request into ticket-kickoff then
# the planning skill. A typed /ticket-kickoff arrives here as a prompt expansion (<command-name>...), not
# a Skill call, so it gets only the planning skill half. Skips notifications and negated phrasing.
# Wired: UserPromptSubmit.
# codex: yes

input=$(jq -c 'select(type=="object")' 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0

HOOK_SESSION=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)

agent_id=$(printf '%s' "$input" | jq -r '.agent_id // empty' 2>/dev/null)
[ -z "$agent_id" ] || exit 0

prompt=$(printf '%s' "$input" | jq -r '.prompt // empty' 2>/dev/null)
[ -n "$prompt" ] || exit 0

hooks_lib="${AGENTS_HOOKS_LIB:-$(dirname "${BASH_SOURCE[0]}")/../../../hooks/lib}"
[ -f "$hooks_lib/prompt-guards.sh" ] || hooks_lib="$HOME/.claude/hooks/lib"
source "$hooks_lib/prompt-guards.sh" || exit 0

case "$prompt" in
  *'<task-notification>'*|*'[SYSTEM NOTIFICATION'*) exit 0 ;;
  *'<command-name>/ticket-kickoff'*)
    emit_context "UserPromptSubmit" "After the ticket digest is in context, run the planning skill, the installed skill whose description covers writing the plan file (the Skill tool where it exists, else its SKILL.md)."
    exit 0
    ;;
esac

prompt_is_notification "$prompt" && exit 0

if prompt_matches "$prompt" "$NUDGE_PICKUP_RE"; then
  emit_context "UserPromptSubmit" "The user wants to start their next work item. Run the ticket-kickoff skill now (the Skill tool where it exists, else its SKILL.md). A mention of PR here means their next ticket or task. Then run the planning skill once the ticket is read."
fi

exit 0
