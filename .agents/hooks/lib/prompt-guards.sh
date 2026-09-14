#!/usr/bin/env bash
# Sourced library for UserPromptSubmit hooks: the guards every prompt hook shares.
# Defines functions only. No sed/cat/awk, so a hook body pasted into a session never trips the
# Bash ban.

# shellcheck source=hook-log.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-log.sh"

# prompt_is_notification <prompt> — true for text an agent or the harness produced, not the
# user: a task notification, a system notification, or a typed slash command expansion. A hook
# that keys on user phrasing exits 0 on these, so a quoted phrase in a report never fires it.
prompt_is_notification() {
  case "$1" in
    *'<task-notification>'*|*'[SYSTEM NOTIFICATION'*|*'<command-name>'*) return 0 ;;
  esac
  return 1
}

# prompt_matches <prompt> <ERE> — true when the prompt holds a match of the ERE that is not
# preceded (within two words) by a negation: don't, do not, never, without. Case-insensitive.
prompt_matches() {
  local prompt="$1" re="$2" hits hit
  hits=$(printf '%s' "$prompt" | grep -oiE "(((don'?t|do not|never|without)[[:space:]]+)([[:alnum:]]+[[:space:]]+){0,2})?(${re})" 2>/dev/null) || return 1
  [ -n "$hits" ] || return 1
  while IFS= read -r hit; do
    hit=$(printf '%s' "$hit" | tr '[:upper:]' '[:lower:]')
    case "$hit" in
      don\'t*|dont*|do\ not*|never*|without*) ;;
      *) return 0 ;;
    esac
  done <<EOF
$hits
EOF
  return 1
}

# emit_context <event> <text> — prints the additionalContext JSON for a hook event.
emit_context() {
  hook_log nudge
  jq -nc --arg e "$1" --arg c "$2" '{hookSpecificOutput:{hookEventName:$e,additionalContext:$c}}'
}

# Shared regexes for the sibling nudges plan-nudge branch A yields to.
NUDGE_MERGE_RE="merge (the |this |my |that )?(pr|pull request)([^[:alnum:]]|$)"
NUDGE_PICKUP_RE='pick[[:space:]]?up[[:space:]]+((the|my|a|your|our)[[:space:]]+)?next[[:space:]]+(pr|ticket|task|issue|story)'

# prompt_matches_sibling_nudge <prompt> — true when the prompt would also fire merge-nudge or
# pick-up-next-ticket. plan-nudge branch A yields to these; create-ticket-nudge is not listed
# because it is a tracker-gated nudge, and yielding to it in a "Ticket system: none" repo would
# leave no nudge at all.
prompt_matches_sibling_nudge() {
  prompt_matches "$1" "$NUDGE_MERGE_RE" || prompt_matches "$1" "$NUDGE_PICKUP_RE"
}
