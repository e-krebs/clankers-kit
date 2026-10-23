#!/usr/bin/env bash
# UserPromptSubmit hook, the Codex followthrough: blocks the "Implement this plan?" approval and
# hands the user the plan's Run fence to start in a new terminal. Both picker choices send exactly
# "Implement the plan." with no plan text, so the plan comes from the marker plan-gate-codex wrote
# for this session; a latest <proposed_plan> block embedded in the prompt wins over it. A Claude-form
# fence gets a codex launch line from codex.md's row for the tier that runs the plan in tiers.md. Plan mode forbids writes, so a plan
# whose Execute path sits under ${CODEX_HOME:-~/.codex}/plans/ is saved there now, from the latest
# <proposed_plan> block in transcript_path (or the prompt). Silent without a Run fence holding an
# Execute line, and for subagent prompts and notifications. Removes the marker after a block.
# Wired: UserPromptSubmit.
# codex: only

APPROVAL_PREFIXES=("Implement the plan.")

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
# shellcheck source=lib/plan-run-fence.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/plan-run-fence.sh" || exit 0

prompt_is_notification "$prompt" && exit 0

trimmed="${prompt#"${prompt%%[![:space:]]*}"}"
approved=0
for prefix in "${APPROVAL_PREFIXES[@]}"; do
  [ "${trimmed#"$prefix"}" = "$trimmed" ] || approved=1
done
[ "$approved" -eq 1 ] || exit 0

sid=${HOOK_SESSION//[^A-Za-z0-9_-]/}
marker=""
[ -z "$sid" ] || marker="${TMPDIR:-/tmp}/codex-plan-latest-$sid"

# latest_block: stdin's latest <proposed_plan> block, an unclosed one included, after "found"
latest_block() {
  awk '
    index($0, "<proposed_plan>") { found = 1; buf = ""; sub(/.*<proposed_plan>/, ""); open = 1 }
    open && index($0, "</proposed_plan>") { sub(/<\/proposed_plan>.*/, ""); buf = buf $0 "\n"; open = 0; next }
    open { buf = buf $0 "\n" }
    END { if (found) printf "found\n%s", buf }'
}
fence_path() {
  plan_run_fence | sed -n -e 's/.*Execute the plan at \([^"]*\).*/\1/p' -e 's/^claude --agent .*"\/execute-plan \([^"]*\)".*/\1/p' | sed -n '1s/[[:space:]]*$//p'
}
plans_dir="${CODEX_HOME:-$HOME/.codex}/plans"
saved_on_approval() {
  case "$1" in */../*|*/./*) return 1 ;; "$plans_dir"/*.md) return 0 ;; esac
  return 1
}

block=$(printf '%s\n' "$prompt" | latest_block)
from_text=0
if [ -n "$block" ]; then
  plan=${block#found}
  from_text=1
else
  [ -n "$marker" ] && [ -f "$marker" ] || exit 0
  path=$(head -1 "$marker" 2>/dev/null)
  [ -n "$path" ] || exit 0
  plan=""
  transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
  if saved_on_approval "$path" && [ -f "$transcript" ]; then
    candidate=$(jq -r 'select(.type == "response_item" and .payload.role == "assistant")
      | .payload.content[]? | select(.type == "output_text") | .text // empty' "$transcript" 2>/dev/null \
      | latest_block)
    candidate=${candidate#found}
    if [ -n "$candidate" ] && [ "$(printf '%s\n' "$candidate" | fence_path)" = "$path" ]; then
      plan=$candidate
      from_text=1
    fi
  fi
  if [ -z "$plan" ]; then
    [ -f "$path" ] || exit 0
    plan=$(cat "$path" 2>/dev/null)
  fi
fi

fence=$(printf '%s\n' "$plan" | plan_run_fence)
if [ -z "$fence" ]; then
  # an embedded plain plan supersedes an earlier write-plan plan
  [ -z "$block" ] || [ -z "$marker" ] || rm -f "$marker" 2>/dev/null
  exit 0
fi

save_note=""
if [ "$from_text" -eq 1 ]; then
  target=$(printf '%s\n' "$plan" | fence_path)
  if saved_on_approval "$target"; then
    if ! { mkdir -p "$(dirname "$target")" && printf '%s\n' "$plan" | sed '/./,$!d' > "$target"; } 2>/dev/null; then
      save_note="
The hook could not save the plan to $target; save the approved plan there before you run it."
    fi
  fi
fi

shown=$fence
execute_line=$(printf '%s\n' "$fence" | sed -n 's/^claude --agent .*"\/execute-plan \([^"]*\)".*/Execute the plan at \1/p' | head -1)
if [ -n "$execute_line" ]; then
  models_dir="${AGENTS_WORKFLOW_MODELS:-$HOME/.agents/workflow-models}"
  # shellcheck source=lib/plan-tiers.sh
  source "$(dirname "${BASH_SOURCE[0]}")/lib/plan-tiers.sh" || exit 0
  run_tier=$(_tier_of_kind "$RUN_KIND")
  row=$(awk -F'|' -v want="$run_tier" '{ t = $2; gsub(/[[:space:]]/, "", t) } want != "" && tolower(t) == want {
      m = $3; e = $4; gsub(/[[:space:]]/, "", m); gsub(/[[:space:]]/, "", e); print m "\t" e; exit }' \
    "$models_dir/codex.md" 2>/dev/null)
  model=${row%%$'\t'*} effort=${row#*$'\t'}
  [ -z "$row" ] || shown="$shown
codex -m $model -c model_reasoning_effort=$effort \"$execute_line\""
fi

[ -z "$marker" ] || rm -f "$marker" 2>/dev/null
hook_log nudge
jq -nc --arg r "Plan approved. Open a new terminal and run:
$shown$save_note" '{decision:"block",reason:$r}'
exit 0
