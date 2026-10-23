#!/usr/bin/env bash
# Runs every plan-approved-guard fixture case and asserts on its output; exits non-zero on any
# failure. The marker lives under TMPDIR, so this script points TMPDIR at a sandbox and writes the
# marker itself where a case needs one.

set -u

fixtures_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
hook="$fixtures_dir/../../plan-approved-guard.sh"
AGENTS_HOOKS_LIB="$fixtures_dir/../../../../../hooks/lib"
export AGENTS_HOOKS_LIB
export AGENTS_WORKFLOW_MODELS="$fixtures_dir/../../../../../workflow-models"
. "$fixtures_dir/../tiers.sh"

overall=0
sandbox=$(mktemp -d "${TMPDIR:-/tmp}/pag.XXXXXX")
export TMPDIR="$sandbox"
export AGENTS_HOOK_LOG="$sandbox/hook-events.log"
trap 'rm -rf "$sandbox" 2>/dev/null' EXIT

pass() { printf 'PASS %s\n' "$1"; }
fail_case() { printf 'FAIL %s: %s\n' "$1" "$2"; overall=1; }

if ! bash -n "$hook" 2>"$sandbox/syn"; then
  fail_case "syntax:hook" "bash -n failed: $(head -1 "$sandbox/syn")"
fi

block='Plan approved. Open a new terminal and run:
claude --agent '"$RUN_TIER"' "Execute the plan at /Users/e/.claude/plans/demo.md"'

marker_of() { printf '%s/claude-plan-approved-%s' "$sandbox" "$1"; }
arm() { printf '%s\n' "$block" > "$(marker_of "$1")"; }

HOOK_OUT="" HOOK_RC=0
run_json() {  # <event> <session> [tool] [agent_id] [last_assistant_message]
  local json
  json=$(jq -nc --arg ev "$1" --arg sid "$2" --arg tool "${3:-}" --arg aid "${4:-}" --arg last "${5:-}" \
    '{hook_event_name:$ev,session_id:$sid} + (if $tool == "" then {} else {tool_name:$tool,tool_input:{}} end) + (if $aid == "" then {} else {agent_id:$aid} end) + (if $last == "" then {} else {last_assistant_message:$last} end)')
  HOOK_OUT=$(printf '%s' "$json" | bash "$hook" 2>/dev/null)
  HOOK_RC=$?
}
decision_of() { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null; }
reason_of()   { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null; }

expect_silent() {
  err=""
  [ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
  [ -z "$HOOK_OUT" ] || err="${err:+$err; }expected no output, got: $HOOK_OUT"
  if [ -z "$err" ]; then pass "$1"; else fail_case "$1" "$err"; fi
}

expect_deny() {
  err=""
  [ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
  [ "$(decision_of "$HOOK_OUT")" = "deny" ] || err="${err:+$err; }expected deny, got: $HOOK_OUT"
  case "$(reason_of "$HOOK_OUT")" in
    "The plan is approved and this session ends here. Reply with the block below verbatim, then end the turn. A fresh session runs the plan.
$block") ;;
    *) err="${err:+$err; }reason mismatch: $(reason_of "$HOOK_OUT")" ;;
  esac
  grep -q " plan-approved-guard deny approved$" "$AGENTS_HOOK_LOG" 2>/dev/null || err="${err:+$err; }deny not logged"
  if [ -z "$err" ]; then pass "$1"; else fail_case "$1" "$err"; fi
}

# no marker: every event is silent
run_json PreToolUse s1 Bash;            expect_silent "no-marker-pretooluse-silent"
run_json Stop s1;                       expect_silent "no-marker-stop-silent"

# marker: every tool is denied, with the block in the reason, and the marker stays
arm s2
: > "$AGENTS_HOOK_LOG"
run_json PreToolUse s2 Bash;            expect_deny "marker-denies-bash"
run_json PreToolUse s2 ExitPlanMode;    expect_deny "marker-denies-exitplanmode"
if [ -f "$(marker_of s2)" ]; then pass "marker-stays-after-deny"; else fail_case "marker-stays-after-deny" "marker removed by PreToolUse"; fi

# another session's marker does not reach this one
run_json PreToolUse s3 Bash;            expect_silent "other-session-silent"

# a subagent is never denied
run_json PreToolUse s2 Bash agent-7;    expect_silent "subagent-silent"

# Stop with the block in the reply removes the marker, then the next tool call is free
run_json Stop s2 "" "" "$block"
expect_silent "stop-with-block-silent"
if [ -f "$(marker_of s2)" ]; then fail_case "stop-clears-marker" "marker still there"; else pass "stop-clears-marker"; fi
run_json PreToolUse s2 Bash;            expect_silent "after-stop-pretooluse-silent"

# Stop without the launch line in the reply blocks the stop, twice, then gives up and clears
expect_block() {
  err=""
  [ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
  [ "$(printf '%s' "$HOOK_OUT" | jq -r '.decision // empty')" = "block" ] || err="${err:+$err; }expected block, got: $HOOK_OUT"
  case "$(printf '%s' "$HOOK_OUT" | jq -r '.reason // empty')" in
    "The plan is approved and this session ends here. Reply with the block below verbatim, then end the turn. A fresh session runs the plan.
$block") ;;
    *) err="${err:+$err; }reason mismatch: $HOOK_OUT" ;;
  esac
  if [ -z "$err" ]; then pass "$1"; else fail_case "$1" "$err"; fi
}
arm s6
: > "$AGENTS_HOOK_LOG"
run_json Stop s6 "" "" "Done, the plan is approved.";           expect_block "stop-without-block-blocks"
if [ -f "$(marker_of s6)" ]; then pass "block-keeps-marker"; else fail_case "block-keeps-marker" "marker removed"; fi
run_json Stop s6 "" "" "Still no block.";                       expect_block "stop-without-block-blocks-again"
run_json Stop s6 "" "" "Still no block.";                       expect_silent "stop-budget-spent-silent"
if [ -f "$(marker_of s6)" ]; then fail_case "budget-clears-marker" "marker still there"; else pass "budget-clears-marker"; fi
if grep -q " plan-approved-guard block approved$" "$AGENTS_HOOK_LOG" && grep -q " plan-approved-guard advise budget:approved$" "$AGENTS_HOOK_LOG"; then
  pass "stop-blocks-logged"
else
  fail_case "stop-blocks-logged" "$(cat "$AGENTS_HOOK_LOG")"
fi

# the reply may hold the launch line in any wrapping, a fence included
arm s7
run_json Stop s7 "" "" '```
claude --agent '"$RUN_TIER"' "Execute the plan at /Users/e/.claude/plans/demo.md"
```';                                                            expect_silent "stop-fenced-line-silent"
if [ -f "$(marker_of s7)" ]; then fail_case "fenced-clears-marker" "marker still there"; else pass "fenced-clears-marker"; fi

# UserPromptSubmit removes it too
arm s4
run_json UserPromptSubmit s4;           expect_silent "prompt-silent"
if [ -f "$(marker_of s4)" ]; then fail_case "prompt-clears-marker" "marker still there"; else pass "prompt-clears-marker"; fi

# an unknown event with a marker is silent and leaves it
arm s5
run_json Notification s5;               expect_silent "other-event-silent"
if [ -f "$(marker_of s5)" ]; then pass "other-event-keeps-marker"; else fail_case "other-event-keeps-marker" "marker removed"; fi

# no session id, malformed input: silent
HOOK_OUT=$(printf '{"hook_event_name":"PreToolUse"}' | bash "$hook" 2>/dev/null); HOOK_RC=$?; expect_silent "no-session-silent"
HOOK_OUT=$(printf 'not json' | bash "$hook" 2>/dev/null); HOOK_RC=$?; expect_silent "malformed-silent"

exit $overall
