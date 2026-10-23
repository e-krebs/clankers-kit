#!/usr/bin/env bash
# Runs every plan-followthrough fixture case and asserts on its output; exits non-zero on any
# failure. Locates the hook relative to this file's own path so it still works once these
# fixtures are copied into the real repo.

set -u

fixtures_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
hook="$fixtures_dir/../../plan-followthrough.sh"
libfile="$fixtures_dir/../../../../../hooks/lib/prompt-guards.sh"
AGENTS_HOOKS_LIB="$(dirname "$libfile")"
export AGENTS_HOOKS_LIB
export AGENTS_WORKFLOW_MODELS="$fixtures_dir/../../../../../workflow-models"
. "$fixtures_dir/../tiers.sh"

overall=0
log_dir=$(mktemp -d "${TMPDIR:-/tmp}/hooklog.XXXXXX")
export AGENTS_HOOK_LOG="$log_dir/hook-events.log"
# the hook writes the approved-plan marker under TMPDIR, so point it at the sandbox
export TMPDIR="$log_dir"
trap 'rm -rf "$log_dir" 2>/dev/null' EXIT
LAST_FIXTURE=""

pass() { printf 'PASS %s\n' "$1"; }
fail_case() { printf 'FAIL %s: %s\n' "$1" "$2"; overall=1; }

HOOK_OUT=""
HOOK_RC=0
run_hook() {
  LAST_FIXTURE="$1"
  HOOK_OUT=$(fill_exec < "$1" | bash "$hook" 2>/dev/null)
  HOOK_RC=$?
}

ctx_of() { printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null; }

if bash -n "$hook" 2>/tmp/pft-syn.$$; then
  pass "syntax:hook"
else
  fail_case "syntax:hook" "bash -n failed: $(head -1 /tmp/pft-syn.$$ 2>/dev/null)"
fi
rm -f /tmp/pft-syn.$$ 2>/dev/null

if bash -n "$libfile" 2>/tmp/pft-syn2.$$; then
  pass "syntax:prompt-guards-lib"
else
  fail_case "syntax:prompt-guards-lib" "bash -n failed: $(head -1 /tmp/pft-syn2.$$ 2>/dev/null)"
fi
rm -f /tmp/pft-syn2.$$ 2>/dev/null

run_hook_filepath() {
  LAST_FIXTURE="$1"
  mkdir -p "$log_dir/plans"
  fill_exec < "$fixtures_dir/plans/run-block.md" > "$log_dir/plans/run-block.md"
  HOOK_OUT=$(sed "s|__FIXTURES__|$log_dir|" "$1" | bash "$hook" 2>/dev/null)
  HOOK_RC=$?
}

expect_silent() {
  err=""
  [ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
  [ -z "$HOOK_OUT" ] || err="${err:+$err; }expected no output, got: $HOOK_OUT"
  if [ -z "$err" ]; then pass "$1"; else fail_case "$1" "$err"; fi
}

# expect_context <case> <model> <effort> <plan path> — asserts the context, that the turn is not
# stopped, and that the marker plan-approved-guard reads holds the block.
expect_context() {
  local name=$1 model=$2 effort=$3 path=$4 ctx cont stop event sid marker
  err=""
  [ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
  cont=$(printf '%s' "$HOOK_OUT" | jq -r '.continue // "absent"' 2>/dev/null)
  stop=$(printf '%s' "$HOOK_OUT" | jq -r '.stopReason // empty' 2>/dev/null)
  event=$(printf '%s' "$HOOK_OUT" | jq -r '.hookSpecificOutput.hookEventName // empty' 2>/dev/null)
  ctx=$(ctx_of "$HOOK_OUT")
  [ "$cont" = "absent" ] || err="${err:+$err; }continue is '$cont', expected absent"
  [ -z "$stop" ] || err="${err:+$err; }stopReason is set: $stop"
  [ "$event" = "PostToolUse" ] || err="${err:+$err; }hookEventName is '$event'"
  block="Plan approved. Open a new terminal and run:
claude --agent $RUN_TIER \"/execute-plan $path\"
In the VS Code extension, start a new session and type:
\`\`\`
/model $model
/effort $effort
/execute-plan $path
\`\`\`"
  [ "$ctx" = "Plan approved. Reply with the block below verbatim, as plain text with the fence kept, then end the turn. Run no step: a fresh session runs the plan, and every tool call is denied until this turn ends.
$block" ] || err="${err:+$err; }additionalContext mismatch: $ctx"
  sid=$(jq -r '.session_id // empty' "$LAST_FIXTURE" 2>/dev/null)
  marker="$TMPDIR/claude-plan-approved-$sid"
  if [ -n "$sid" ]; then
    [ -f "$marker" ] || err="${err:+$err; }marker missing: $marker"
    [ "$(cat "$marker" 2>/dev/null)" = "$block" ] || err="${err:+$err; }marker text differs"
    rm -f "$marker" 2>/dev/null
  fi
  if [ -z "$err" ]; then pass "$name"; else fail_case "$name" "$err"; fi
}

run_hook "$fixtures_dir/run-block.json"
expect_context "run-block" "$RUN_MODEL" "$RUN_EFFORT" "/Users/e/.claude/plans/demo.md"

run_hook "$fixtures_dir/quoted-run.json"
expect_context "quoted-run-ignored" "$RUN_MODEL" "$RUN_EFFORT" "/Users/e/.claude/plans/real.md"

run_hook "$fixtures_dir/non-run-fence-first.json"
expect_context "non-run-fence-first" "$RUN_MODEL" "$RUN_EFFORT" "/Users/e/.claude/plans/demo.md"

run_hook "$fixtures_dir/indented-run.json"
expect_context "indented-run-trimmed" "$RUN_MODEL" "$RUN_EFFORT" "/Users/e/.claude/plans/indented.md"

run_hook "$fixtures_dir/codex-only.json"
codex_expected="Plan approved. Open a new terminal and run:
codex -m $RUN_CODEX_MODEL -c model_reasoning_effort=$RUN_CODEX_EFFORT \"Execute the plan at /Users/e/.claude/plans/demo.md\""
codex_ctx=$(ctx_of "$HOOK_OUT")
if [ "$HOOK_RC" -eq 0 ] && [ "${codex_ctx#*ends.
}" = "$codex_expected" ] && [ -z "$(printf '%s' "$HOOK_OUT" | jq -r '.continue // empty')" ]; then
  pass "codex-only-fence"
else
  fail_case "codex-only-fence" "exit $HOOK_RC; context: $codex_ctx"
fi

run_hook_filepath "$fixtures_dir/filepath-only.json"
expect_context "filepath-only" "$RUN_MODEL" "$RUN_EFFORT" "/Users/e/.claude/plans/demo.md"

run_hook "$fixtures_dir/no-run.json"
expect_silent "no-run-silent"

run_hook "$fixtures_dir/ten-heading.json"
expect_silent "ten-heading-silent"

run_hook "$fixtures_dir/is-agent.json"
expect_silent "is-agent-silence"

run_hook "$fixtures_dir/agent-id-silence.json"
expect_silent "agent-id-silence"

run_hook "$fixtures_dir/malformed.json"
expect_silent "malformed"

exit $overall
