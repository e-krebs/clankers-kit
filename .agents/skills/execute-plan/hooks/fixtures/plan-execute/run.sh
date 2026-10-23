#!/usr/bin/env bash
# Runs every plan-execute fixture case and asserts on its output; exits non-zero on any failure.
# Builds each input from the plan fixtures' absolute paths at run time, and points HOME at a
# sandbox for the ~/ case. Locates the hook relative to this file's own path.

set -u

fixtures_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
hook="$fixtures_dir/../../plan-execute.sh"
libfile="$fixtures_dir/../../../../../hooks/lib/prompt-guards.sh"
AGENTS_HOOKS_LIB="$(cd "$(dirname "$libfile")" && pwd)"
export AGENTS_HOOKS_LIB
plans="$fixtures_dir/plans"
export AGENTS_WORKFLOW_MODELS="$fixtures_dir/../../../../../workflow-models"
. "$fixtures_dir/../../../../write-plan/hooks/fixtures/tiers.sh"

overall=0
sandbox=$(mktemp -d "${TMPDIR:-/tmp}/plan-execute.XXXXXX")
export AGENTS_HOOK_LOG="$sandbox/hook-events.log"
trap 'rm -rf "$sandbox" 2>/dev/null' EXIT

pass() { printf 'PASS %s\n' "$1"; }
fail_case() { printf 'FAIL %s: %s\n' "$1" "$2"; overall=1; }

HOOK_OUT=""
HOOK_RC=0
run_json() {  # $1=input json, rest=hook args
  local in=$1
  shift
  HOOK_OUT=$(printf '%s' "$in" | bash "$hook" "$@" 2>/dev/null)
  HOOK_RC=$?
}
input_of() {  # $1=prompt $2=permission_mode
  jq -nc --arg p "$1" --arg m "$2" '{session_id:"case-exec",permission_mode:$m,hook_event_name:"UserPromptSubmit",prompt:$p}'
}

ctx_of() { printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null; }

expect_ctx() {  # $1=case $2=expected context
  local ctx err=""
  ctx=$(ctx_of "$HOOK_OUT")
  [ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
  [ "$ctx" = "$2" ] || err="${err:+$err; }context mismatch: $ctx"
  if [ -z "$err" ]; then pass "$1"; else fail_case "$1" "$err"; fi
}
expect_silent() {  # $1=case
  local err=""
  [ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
  [ -z "$HOOK_OUT" ] || err="${err:+$err; }expected no output, got: $HOOK_OUT"
  if [ -z "$err" ]; then pass "$1"; else fail_case "$1" "$err"; fi
}
run_msg() {  # $1=N $2=path
  printf 'Plan execution request detected. Do not write a new plan. Read lines 1-%s of %s (everything above ## Briefs), then run its Steps by the rules in its ## Run section. Read an '"$RUN_TIER"' row'"'"'s brief when that row starts.' "$1" "$2"
}
run_msg_briefs() {  # $1=N $2=path $3=briefs folder
  printf '%s Briefs are in %s: each dispatched worker reads its own S<n>.md there. If the brief file of a dispatched row is missing or empty, stop and report it instead of dispatching. A row at '"$RUN_TIER"' with no brief runs from its Task cell.' "$(run_msg "$1" "$2")" "$3"
}
CODEX_PLAN_MODE_MSG="Plan execution request detected. The session is in Plan mode, so tell the user in one line to leave Plan mode with shift+tab or the mode picker and send the same prompt again, then end the turn. Write no plan."
CODEX_PARAGRAPH="On Codex, this session cannot start tier workers; run each delegated row yourself and say so in the row's report."
PLAN_MODE_MSG="Plan execution request detected. The session is in plan mode, so tell the user in one line to leave plan mode (shift+tab or the mode picker) and send the same prompt again, then end the turn. Write no plan."

if bash -n "$hook" 2>"$sandbox/syn"; then
  pass "syntax:hook"
else
  fail_case "syntax:hook" "bash -n failed: $(head -1 "$sandbox/syn" 2>/dev/null)"
fi

run_json "$(input_of "Execute the plan at $plans/new.md" default)"
expect_ctx "fires-with-briefs-line" "$(run_msg 26 "$plans/new.md")"

present_rules="$sandbox/rules/run-rules.md"
mkdir -p "$sandbox/rules" && : > "$present_rules"
sed "s|/Users/example/.agents/skills/execute-plan/references/run-rules.md|$present_rules|" "$plans/run-rules.md" > "$sandbox/present-rules.md"
run_json "$(input_of "Execute the plan at $sandbox/present-rules.md" default)"
expect_ctx "names-run-rules-path" "Plan execution request detected. Do not write a new plan. Read lines 1-32 of $sandbox/present-rules.md (everything above ## Briefs) and the $RUN_TIER rules at $present_rules, then run its Steps by those rules. Read an $RUN_TIER row's brief when that row starts."

run_json "$(input_of "Execute the plan at $plans/run-rules.md" default)"
expect_ctx "missing-run-rules-file-stops" "Plan execution request detected. Do not write a new plan. The run rules file /Users/example/.agents/skills/execute-plan/references/run-rules.md named in $plans/run-rules.md is missing, and the plan needs the skill that holds the run rules. Stop and report the missing file to the user instead of running the Steps."

run_json "$(input_of "Execute the plan at $plans/fenced-briefs.md" default)"
expect_ctx "fenced-briefs-ignored" "$(run_msg 22 "$plans/fenced-briefs.md")"

run_json "$(input_of "Execute the plan at $plans/nested-fence.md" default)"
expect_ctx "nested-and-indented-fences-ignored" "$(run_msg 32 "$plans/nested-fence.md")"

run_json "$(input_of "Execute the plan at $plans/no-briefs.md" default)"
expect_ctx "no-briefs-uses-file-length" "$(run_msg 11 "$plans/no-briefs.md")"

run_json "$(input_of "Execute the plan at $plans/file-briefs.md" default)"
expect_ctx "pointer-names-briefs-folder" "$(run_msg_briefs 16 "$plans/file-briefs.md" /Users/example/plans/file-briefs.briefs/)"

run_json "$(input_of "Execute the plan at $plans/fenced-pointer.md" default)"
expect_ctx "fenced-pointer-ignored" "$(run_msg 12 "$plans/fenced-pointer.md")"

run_json "$(input_of "Execute the plan at $plans/new.md" plan)"
expect_ctx "plan-mode-message" "$PLAN_MODE_MSG"

run_json "$(input_of "  execute the approved plan at $plans/new.md." auto)"
expect_ctx "approved-plan-wording" "$(run_msg 26 "$plans/new.md")"

mkdir -p "$sandbox/home/.claude/plans"
cp "$plans/new.md" "$sandbox/home/.claude/plans/tilde.md"
HOOK_OUT=$(input_of "Execute the plan at ~/.claude/plans/tilde.md" default | HOME="$sandbox/home" bash "$hook" 2>/dev/null)
HOOK_RC=$?
expect_ctx "tilde-path" "$(run_msg 26 "$sandbox/home/.claude/plans/tilde.md")"

run_json "$(input_of "Execute the plan at $plans/missing.md" default)"
expect_silent "missing-file-silent"

run_json "$(input_of "Execute the plan at $plans/old.md" default)"
expect_silent "old-ten-heading-plan-silent"

run_json "$(input_of "Please review, then Execute the plan at $plans/new.md" default)"
expect_silent "not-at-prompt-start-silent"

run_json "$(input_of "<task-notification>Execute the plan at $plans/new.md</task-notification>" default)"
expect_silent "notification-silent"

run_json "$(jq -nc --arg p "Execute the plan at $plans/new.md" '{session_id:"case-exec",agent_id:"sub-1",permission_mode:"default",prompt:$p}')"
expect_silent "agent-id-silence"

HOOK_OUT=$(bash "$hook" < "$fixtures_dir/malformed.json" 2>/dev/null)
HOOK_RC=$?
expect_silent "malformed"

run_json "$(input_of "Execute the plan at $plans/new.md" plan)" --codex
expect_ctx "codex:plan-mode-message" "$CODEX_PLAN_MODE_MSG"

run_json "$(input_of "Execute the plan at $plans/new.md" default)" --codex
expect_ctx "codex:execute-context" "$(run_msg 26 "$plans/new.md")

$CODEX_PARAGRAPH"

run_json "$(input_of "Execute the plan at $plans/file-briefs.md" default)" --codex
expect_ctx "codex:pointer-names-briefs-folder" "$(run_msg_briefs 16 "$plans/file-briefs.md" /Users/example/plans/file-briefs.briefs/)

$CODEX_PARAGRAPH"

run_json "$(input_of "Execute the plan at $plans/missing.md" default)" --codex
expect_silent "codex:missing-file-silent"

run_json "$(jq -nc --arg p "Execute the plan at $plans/new.md" '{session_id:"case-exec",agent_id:"sub-1",permission_mode:"default",prompt:$p}')" --codex
expect_silent "codex:agent-id-silence"

run_json "$(input_of "<task-notification>Execute the plan at $plans/new.md</task-notification>" default)" --codex
expect_silent "codex:notification-silent"

exit $overall
