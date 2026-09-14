#!/usr/bin/env bash
# UserPromptSubmit hook, advisory: nudges toward the write-plan skill. Branch A fires once per
# session when the harness starts in plan mode and the first prompt reads like a task (12+ words,
# no trailing "?"), but yields to the merge and pick-up-next-ticket nudges — it still consumes its
# marker when it yields. Branch B fires on every prompt that uses a planning trigger phrase. Skips
# notifications and negated phrasing. Wired: UserPromptSubmit.
# Also wired from ~/.codex/hooks.json; a codex exec probe reported permission_mode as bypassPermissions,
# and interactive plan mode was not probed, so the plan branch is Claude-only until observed.
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
# shellcheck source=../../../hooks/lib/prompt-guards.sh
source "$hooks_lib/prompt-guards.sh" || exit 0

prompt_is_notification "$prompt" && exit 0

# an explicit veto silences both branches
printf '%s' "$prompt" | grep -qiE "(don'?t|do not|never|without)([[:space:]]+[[:alnum:]]+){0,2}[[:space:]]+(plan|planning)" && exit 0

should_emit=0

permission_mode=$(printf '%s' "$input" | jq -r '.permission_mode // empty' 2>/dev/null)
session_id=$(printf '%s' "$input" | jq -r '.session_id // "unknown"' 2>/dev/null)
marker="${TMPDIR:-/tmp}/claude-plan-nudge-${session_id//[^A-Za-z0-9_-]/}"

if [ "$permission_mode" = "plan" ] && [ ! -e "$marker" ]; then
  # shellcheck disable=SC2086  # word splitting is the point: the words are counted
  set -- $prompt
  word_count=$#
  trimmed="${prompt%"${prompt##*[![:space:]]}"}"
  case "$trimmed" in
    *'?') is_question=1 ;;
    *) is_question=0 ;;
  esac
  if [ "$word_count" -ge 12 ] && [ "$is_question" -eq 0 ]; then
    : > "$marker" 2>/dev/null
    prompt_matches_sibling_nudge "$prompt" || should_emit=1
  fi
fi

if prompt_matches "$prompt" "plan (this|it|out)|let'?s plan|make a plan|how would you (approach|tackle)"; then
  should_emit=1
fi

[ "$should_emit" -eq 1 ] || exit 0

emit_context "UserPromptSubmit" "Planning request detected. Run the write-plan skill now (the Skill tool where it exists, else its SKILL.md). It owns the plan file, the interview and the plan review."
exit 0
