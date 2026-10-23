#!/usr/bin/env bash
# UserPromptSubmit hook, advisory: routes "Execute the plan at <path>" to the plan's own Run rules
# instead of a fresh planning round. Fires only when the file exists and holds both a "## Steps"
# and a "## Run" line outside fences, so an old ten-heading plan stays silent. Outside plan mode it
# points at the lines above "## Briefs" and at the run-rules.md path the Run section names, if
# any; in plan mode it asks the user to leave plan mode first.
# Skips notifications and subagent prompts. Wired: UserPromptSubmit.
# With --codex as $1 it speaks Codex: its own plan-mode wording, and a paragraph that maps rule 2's
# dispatch. Codex Plan mode reports permission_mode "default" (the mode lives only in the transcript's
# turn_context), so the plan branch stays on "plan" and does not fire there.
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
models_dir="${AGENTS_WORKFLOW_MODELS:-$HOME/.agents/workflow-models}"
# shellcheck source=../../write-plan/hooks/lib/plan-tiers.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../write-plan/hooks/lib/plan-tiers.sh" || exit 0
run_tier=$(_tier_of_kind "$RUN_KIND")
: "${run_tier:=running-session}"

prompt_is_notification "$prompt" && exit 0

trimmed="${prompt#"${prompt%%[![:space:]]*}"}"
trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
[[ $trimmed =~ $NUDGE_EXECUTE_RE ]] || exit 0

path="${trimmed#* plan at }"
path="${path%%[[:space:]]*}"
path="${path%.md*}.md"
# shellcheck disable=SC2088  # the literal ~/ from the prompt is matched, then expanded
case "$path" in
  '~/'*) path="$HOME/${path#\~/}" ;;
esac
[ -f "$path" ] || exit 0

# A fence closes only on its own marker char repeated at least as long, so a quoted fence nests.
fence_re='^ {0,3}(`{3,}|~{3,})(.*)$'
rules_re='(/[^[:space:]`)]*/run-rules\.md)'
briefs_re='^Briefs: (.*\.briefs/)'
open='' line_no=0 has_steps=0 has_run=0 briefs_line=0 in_run=0 rules='' briefs_dir=''
while IFS= read -r line || [ -n "$line" ]; do
  line_no=$((line_no + 1))
  if [[ $line =~ $fence_re ]]; then
    marker=${BASH_REMATCH[1]} rest=${BASH_REMATCH[2]}
    if [ -z "$open" ]; then
      open=$marker
      continue
    fi
    if [ "${marker:0:1}" = "${open:0:1}" ] && [ ${#marker} -ge ${#open} ] && [[ $rest =~ ^[[:space:]]*$ ]]; then
      open=''
      continue
    fi
  fi
  [ -z "$open" ] || continue
  case "$line" in
    '## Steps') has_steps=1 in_run=0 ;;
    '## Run') has_run=1 in_run=1 ;;
    '## Briefs') [ "$briefs_line" -ne 0 ] || briefs_line=$line_no; in_run=0 ;;
    'Briefs: '*) [ "$briefs_line" -gt 0 ] && [ -z "$briefs_dir" ] && [[ $line =~ $briefs_re ]] && briefs_dir=${BASH_REMATCH[1]} ;;
    '## '*) in_run=0 ;;
    *) [ "$in_run" -eq 0 ] || [ -n "$rules" ] || { [[ $line =~ $rules_re ]] && rules=${BASH_REMATCH[1]}; } ;;
  esac
done < "$path"

[ "$has_steps" -eq 1 ] && [ "$has_run" -eq 1 ] || exit 0

if [ "$briefs_line" -gt 0 ]; then
  last=$((briefs_line - 1))
else
  last=$line_no
fi

permission_mode=$(printf '%s' "$input" | jq -r '.permission_mode // empty' 2>/dev/null)

if [ "$permission_mode" = "plan" ]; then
  if [ "$codex" -eq 1 ]; then
    emit_context "UserPromptSubmit" "Plan execution request detected. The session is in Plan mode, so tell the user in one line to leave Plan mode with shift+tab or the mode picker and send the same prompt again, then end the turn. Write no plan."
  else
    emit_context "UserPromptSubmit" "Plan execution request detected. The session is in plan mode, so tell the user in one line to leave plan mode (shift+tab or the mode picker) and send the same prompt again, then end the turn. Write no plan."
  fi
else
  note=''
  [ -z "$briefs_dir" ] || note=" Briefs are in $briefs_dir: each dispatched worker reads its own S<n>.md there. If the brief file of a dispatched row is missing or empty, stop and report it instead of dispatching. A row at $run_tier with no brief runs from its Task cell."
  if [ -n "$rules" ] && [ ! -f "$rules" ]; then
    msg="Plan execution request detected. Do not write a new plan. The run rules file $rules named in $path is missing, and the plan needs the skill that holds the run rules. Stop and report the missing file to the user instead of running the Steps."
  elif [ -n "$rules" ]; then
    msg="Plan execution request detected. Do not write a new plan. Read lines 1-$last of $path (everything above ## Briefs) and the $run_tier rules at $rules, then run its Steps by those rules. Read an $run_tier row's brief when that row starts.$note"
  else
    msg="Plan execution request detected. Do not write a new plan. Read lines 1-$last of $path (everything above ## Briefs), then run its Steps by the rules in its ## Run section. Read an $run_tier row's brief when that row starts.$note"
  fi
  # the probe saw a nested codex exec fail from a default-sandbox TUI, so no dispatch form is offered
  [ "$codex" -eq 0 ] || msg="$msg

On Codex, this session cannot start tier workers; run each delegated row yourself and say so in the row's report."
  emit_context "UserPromptSubmit" "$msg"
fi
exit 0
