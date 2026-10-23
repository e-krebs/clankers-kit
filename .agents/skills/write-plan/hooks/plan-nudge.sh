#!/usr/bin/env bash
# UserPromptSubmit hook, advisory: nudges toward the write-plan skill. Branch A fires once per
# session when the harness starts in plan mode, or in default mode in an interactive Claude Code
# session (CLAUDECODE=1, entrypoint not sdk*), and the first prompt reads like a task (12+ words,
# no trailing "?"), but yields to the merge and pick-up-next-ticket nudges — it still consumes its
# marker when it yields. Branch B fires on every prompt that uses a planning trigger phrase, and on "let's work on" it tells the agent to ask whether to plan first. Both
# branches yield to plan-execute. Skips notifications and negated phrasing. Outside plan mode on
# Claude, the message also says to call EnterPlanMode after the ticket step. Wired: UserPromptSubmit.
# Also wired on Codex, where every session reports permission_mode "default"; the interactive-Claude
# guard keeps branch A silent there and in headless claude -p runs. With --codex as $1 (a
# codex-invoked hook, even one launched from a Claude Code session and inheriting its env)
# interactive_claude is forced to 0, since inherited CLAUDECODE/CLAUDE_CODE_ENTRYPOINT would
# otherwise wrongly look like an interactive Claude session.
# codex: yes args=--codex

codex=0
[ "${1:-}" = "--codex" ] && codex=1

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

# plan-execute owns an execute request, in both branches
trimmed="${prompt#"${prompt%%[![:space:]]*}"}"
[[ $trimmed =~ $NUDGE_EXECUTE_RE ]] && exit 0

# an explicit veto silences both branches
printf '%s' "$prompt" | grep -qiE "(don'?t|do not|never|without)([[:space:]]+[[:alnum:]]+){0,2}[[:space:]]+(plan|planning)" && exit 0

should_emit=0

permission_mode=$(printf '%s' "$input" | jq -r '.permission_mode // empty' 2>/dev/null)
session_id=$(printf '%s' "$input" | jq -r '.session_id // "unknown"' 2>/dev/null)
marker="${TMPDIR:-/tmp}/claude-plan-nudge-${session_id//[^A-Za-z0-9_-]/}"

interactive_claude=0
if [ "$codex" -eq 0 ] && [ "$CLAUDECODE" = "1" ]; then
  case "$CLAUDE_CODE_ENTRYPOINT" in
    sdk*) ;;
    *) interactive_claude=1 ;;
  esac
fi

if { [ "$permission_mode" = "plan" ] || { [ "$permission_mode" = "default" ] && [ "$interactive_claude" -eq 1 ]; }; } && [ ! -e "$marker" ]; then
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

ask_first=0
if [ "$should_emit" -eq 0 ] && prompt_matches "$prompt" "let'?s work on"; then
  should_emit=1
  ask_first=1
fi

[ "$should_emit" -eq 1 ] || exit 0

if [ "$ask_first" -eq 1 ]; then
  emit_context "UserPromptSubmit" "The user may want a plan for this work. Ask whether to plan it first (the harness's question tool where it has one, else one question). On yes, run the write-plan skill. On no, carry on."
  exit 0
fi

msg="Planning request detected. Run the write-plan skill now (the Skill tool where it exists, else its SKILL.md). It owns the plan file, the interview and the plan review."
[ "$codex" -eq 1 ] || [ "$permission_mode" = "plan" ] || msg="$msg After its ticket step, load EnterPlanMode with ToolSearch select:EnterPlanMode,ExitPlanMode and call it."
emit_context "UserPromptSubmit" "$msg"
exit 0
