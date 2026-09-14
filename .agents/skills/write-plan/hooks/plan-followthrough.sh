#!/usr/bin/env bash
# PostToolUse hook on ExitPlanMode: once the plan is approved, states the fixed order to run the
# rest of the plan-file contract in (deferred kickoff actions, then steps, then closing steps),
# and gates on the model-switch/context-clear confirmation first. Advisory only. A rejection
# returns an error result rather than the approval text, so it stays silent. Wired: PostToolUse,
# matcher ExitPlanMode.
# codex: no

input=$(jq -c 'select(type=="object")' 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0

HOOK_SESSION=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)

agent_id=$(printf '%s' "$input" | jq -r '.agent_id // empty' 2>/dev/null)
[ -z "$agent_id" ] || exit 0

hooks_lib="${AGENTS_HOOKS_LIB:-$(dirname "${BASH_SOURCE[0]}")/../../../hooks/lib}"
[ -f "$hooks_lib/prompt-guards.sh" ] || hooks_lib="$HOME/.claude/hooks/lib"
# shellcheck source=../../../hooks/lib/prompt-guards.sh
source "$hooks_lib/prompt-guards.sh" || exit 0

response=$(printf '%s' "$input" | jq -r '.tool_response | tostring' 2>/dev/null)
[ -n "$response" ] || exit 0

case "$response" in
  *'approved your plan'*) ;;
  *) exit 0 ;;
esac

path=$(printf '%s' "$response" | grep -oE '/[^ "]+\.md' | head -1)

if [ -n "$path" ]; then
  msg="Plan approved (${path})."
else
  msg="Plan approved."
fi
msg="${msg} If the plan asks for a model switch or a context clear, state the exact command in one line and wait for the user to confirm they ran it before any step. Then run Deferred kickoff actions, then Steps, then Closing steps, in order. No Step commits or pushes: the commit split under Closing steps is a recommendation the PR skill applies after the reviews."

emit_context "PostToolUse" "$msg"
exit 0
