#!/usr/bin/env bash
# PostToolUse hook on ExitPlanMode (PostToolUse fires only on approval): hands the model the plan's
# Run fence (the one launch line) as context, with the order to reply with that block
# and end the turn, and writes the marker that plan-approved-guard reads to deny every tool until
# the turn ends. Reads the plan from .tool_response.plan, else from .tool_response.filePath. Silent
# for subagents and for a plan with no Run fence holding a launch line, so old
# ten-heading plans stay quiet.
#
# Until 2026-09-28 this hook stopped the turn (continue:false) with the block as stopReason and
# systemMessage. The VSCode extension showed neither, and it shows no chat text written beside the
# ExitPlanMode call either, so the user never saw the instructions. A plain reply is the one
# channel every UI shows, hence the context plus the guard.
# A Claude fence also gets the /model and /effort lines of its tier, for the VSCode extension.
# Wired: PostToolUse, matcher ExitPlanMode.
# codex: no

input=$(jq -c 'select(type=="object")' 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0

HOOK_SESSION=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)

agent_id=$(printf '%s' "$input" | jq -r '.agent_id // empty' 2>/dev/null)
[ -z "$agent_id" ] || exit 0
is_agent=$(printf '%s' "$input" | jq -r '.tool_response.isAgent? // false' 2>/dev/null)
[ "$is_agent" != "true" ] || exit 0

hooks_lib="${AGENTS_HOOKS_LIB:-$(dirname "${BASH_SOURCE[0]}")/../../../hooks/lib}"
[ -f "$hooks_lib/prompt-guards.sh" ] || hooks_lib="$HOME/.claude/hooks/lib"
# shellcheck source=../../../hooks/lib/prompt-guards.sh
source "$hooks_lib/prompt-guards.sh" || exit 0

plan=$(printf '%s' "$input" | jq -r '.tool_response.plan? // empty' 2>/dev/null)
if [ -z "$plan" ]; then
  path=$(printf '%s' "$input" | jq -r '.tool_response.filePath? // empty' 2>/dev/null)
  [ -n "$path" ] && [ -f "$path" ] || exit 0
  plan=$(cat "$path" 2>/dev/null)
fi
[ -n "$plan" ] || exit 0

# shellcheck source=lib/plan-run-fence.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/plan-run-fence.sh" || exit 0
fence=$(printf '%s\n' "$plan" | plan_run_fence)
printf '%s\n' "$fence" | grep -q -E '"(/execute-plan|Execute the plan at) ' || exit 0

block="Plan approved. Open a new terminal and run:
$fence"

# the VSCode extension has no --agent flag: a Claude fence also gets the /model and /effort of its tier
launch=$(printf '%s\n' "$fence" | grep -m1 '^claude --agent ')
tier=${launch#claude --agent }
tier=${tier%% *}
if [ -n "$tier" ]; then
  models_dir="${AGENTS_WORKFLOW_MODELS:-$HOME/.agents/workflow-models}"
  row=$(awk -F'|' -v tier="$tier" '/^\|/ {
    for (i = 2; i < NF; i++) { c = $i; gsub(/^ +| +$/, "", c); cell[i] = c }
    if (tolower(cell[2]) == tolower(tier)) { print cell[3] "\t" cell[4]; exit }
  }' "$models_dir/claude.md" 2>/dev/null)
  IFS=$'\t' read -r model effort <<< "$row"
  plan_path=${launch#*\"/execute-plan }
  plan_path=${plan_path%\"}
  if [ -n "$model" ] && [ -n "$effort" ] && [ -n "$plan_path" ]; then
    block="$block
In the VS Code extension, start a new session and type:
\`\`\`
/model $model
/effort $effort
/execute-plan $plan_path
\`\`\`"
  fi
fi

context="Plan approved. Reply with the block below verbatim, as plain text with the fence kept, then end the turn. Run no step: a fresh session runs the plan, and every tool call is denied until this turn ends.
$block"

# the marker plan-approved-guard reads; a missing session id means no guard, and the context alone
# still carries the order
if [ -n "$HOOK_SESSION" ]; then
  marker="${TMPDIR:-/tmp}/claude-plan-approved-${HOOK_SESSION//[^A-Za-z0-9_-]/}"
  printf '%s\n' "$block" > "$marker" 2>/dev/null || true
fi

hook_log nudge
jq -nc --arg c "$context" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $c}}'
exit 0
