#!/usr/bin/env bash
# Runs every plan-nudge fixture case and asserts on its output; exits non-zero on any failure.
# Locates the hook relative to this file's own path so it still works once these fixtures are
# copied into the real repo.

set -u

fixtures_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
hook="$fixtures_dir/../../plan-nudge.sh"
libfile="$fixtures_dir/../../../../../hooks/lib/prompt-guards.sh"
AGENTS_HOOKS_LIB="$(dirname "$libfile")"
export AGENTS_HOOKS_LIB

overall=0
log_dir=$(mktemp -d "${TMPDIR:-/tmp}/hooklog.XXXXXX")
export AGENTS_HOOK_LOG="$log_dir/hook-events.log"
trap 'rm -rf "$log_dir" 2>/dev/null' EXIT

pass() { printf 'PASS %s\n' "$1"; }
fail_case() { printf 'FAIL %s: %s\n' "$1" "$2"; overall=1; }

HOOK_OUT=""
HOOK_RC=0
run_hook() {
  HOOK_OUT=$(bash "$hook" < "$1" 2>/dev/null)
  HOOK_RC=$?
}

ctx_of() { printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null; }
contains() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }

if bash -n "$hook" 2>/tmp/pn-syn.$$; then
  pass "syntax:hook"
else
  fail_case "syntax:hook" "bash -n failed: $(head -1 /tmp/pn-syn.$$ 2>/dev/null)"
fi
rm -f /tmp/pn-syn.$$ 2>/dev/null

if bash -n "$libfile" 2>/tmp/pn-syn2.$$; then
  pass "syntax:prompt-guards-lib"
else
  fail_case "syntax:prompt-guards-lib" "bash -n failed: $(head -1 /tmp/pn-syn2.$$ 2>/dev/null)"
fi
rm -f /tmp/pn-syn2.$$ 2>/dev/null

# --- branch A fires once, then silent on the same session ---------------------
case_name="branch-a-fires-once-then-silent"
rm -f "${TMPDIR:-/tmp}/claude-plan-nudge-case-branch-a" 2>/dev/null
run_hook "$fixtures_dir/branch-a-once.json"
ctx1=$(ctx_of "$HOOK_OUT")
rc1="$HOOK_RC"
run_hook "$fixtures_dir/branch-a-once.json"
out2="$HOOK_OUT"
rc2="$HOOK_RC"
err=""
[ "$rc1" -eq 0 ] || err="${err:+$err; }first run exit $rc1"
[ "$rc2" -eq 0 ] || err="${err:+$err; }second run exit $rc2"
contains "$ctx1" "write-plan" || err="${err:+$err; }first run missing write-plan mention: $ctx1"
[ -z "$out2" ] || err="${err:+$err; }second run emitted output: $out2"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi
rm -f "${TMPDIR:-/tmp}/claude-plan-nudge-case-branch-a" 2>/dev/null

# --- short prompt: silent -------------------------------------------------------
case_name="short-prompt-silent"
run_hook "$fixtures_dir/short-prompt-silent.json"
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ -z "$HOOK_OUT" ] || err="${err:+$err; }expected no output, got: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- trailing "?": silent --------------------------------------------------------
case_name="trailing-question-silent"
run_hook "$fixtures_dir/trailing-question-silent.json"
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ -z "$HOOK_OUT" ] || err="${err:+$err; }expected no output, got: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- branch B fires on every prompt with a trigger phrase ----------------------
case_name="branch-b-fires"
run_hook "$fixtures_dir/branch-b-fires.json"
ctx=$(ctx_of "$HOOK_OUT")
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
contains "$ctx" "write-plan" || err="${err:+$err; }missing write-plan mention: $ctx"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- negated phrasing: silent -----------------------------------------------------
case_name="negated-silent"
run_hook "$fixtures_dir/negated-silent.json"
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ -z "$HOOK_OUT" ] || err="${err:+$err; }expected no output, got: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- negated long prompt in plan mode: branch A stays silent too --------------------
case_name="negated-branch-a-silent"
run_hook "$fixtures_dir/negated-branch-a.json"
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ -z "$HOOK_OUT" ] || err="${err:+$err; }expected no output, got: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- task-notification: silent -----------------------------------------------------
case_name="notification-silent"
run_hook "$fixtures_dir/notification-silent.json"
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ -z "$HOOK_OUT" ] || err="${err:+$err; }expected no output, got: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- command-name expansion: silent -------------------------------------------------
case_name="command-name-silent"
run_hook "$fixtures_dir/command-name-silent.json"
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ -z "$HOOK_OUT" ] || err="${err:+$err; }expected no output, got: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- agent_id: silent -------------------------------------------------------------
case_name="agent-id-silence"
run_hook "$fixtures_dir/agent-id-silence.json"
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ -z "$HOOK_OUT" ] || err="${err:+$err; }expected no output, got: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- malformed: silent -------------------------------------------------------------
case_name="malformed"
run_hook "$fixtures_dir/malformed.json"
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ -z "$HOOK_OUT" ] || err="${err:+$err; }expected no output, got: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- branch A yields to the merge nudge -----------------------------------------
case_name="branch-a-yields-to-merge"
rm -f "${TMPDIR:-/tmp}/claude-plan-nudge-case-yield-merge" 2>/dev/null
run_hook "$fixtures_dir/branch-a-yields-to-merge.json"
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ -z "$HOOK_OUT" ] || err="${err:+$err; }expected no output, got: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi
rm -f "${TMPDIR:-/tmp}/claude-plan-nudge-case-yield-merge" 2>/dev/null

# --- branch A yields to the pick-up-next-ticket nudge ---------------------------
case_name="branch-a-yields-to-pickup"
rm -f "${TMPDIR:-/tmp}/claude-plan-nudge-case-yield-pickup" 2>/dev/null
run_hook "$fixtures_dir/branch-a-yields-to-pickup.json"
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ -z "$HOOK_OUT" ] || err="${err:+$err; }expected no output, got: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi
rm -f "${TMPDIR:-/tmp}/claude-plan-nudge-case-yield-pickup" 2>/dev/null

# --- branch A still fires on a create-ticket request (not a sibling nudge) -----
case_name="branch-a-fires-on-create-ticket"
rm -f "${TMPDIR:-/tmp}/claude-plan-nudge-case-create-ticket" 2>/dev/null
run_hook "$fixtures_dir/branch-a-fires-on-create-ticket.json"
ctx=$(ctx_of "$HOOK_OUT")
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
contains "$ctx" "write-plan" || err="${err:+$err; }missing write-plan mention: $ctx"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi
rm -f "${TMPDIR:-/tmp}/claude-plan-nudge-case-create-ticket" 2>/dev/null

# --- branch A yield still consumes the marker (silent after, same session) -----
case_name="branch-a-yield-consumes-marker"
rm -f "${TMPDIR:-/tmp}/claude-plan-nudge-case-yield-merge" 2>/dev/null
run_hook "$fixtures_dir/branch-a-yields-to-merge.json"
out1="$HOOK_OUT"
rc1="$HOOK_RC"
run_hook "$fixtures_dir/branch-a-after-yield.json"
out2="$HOOK_OUT"
rc2="$HOOK_RC"
err=""
[ "$rc1" -eq 0 ] || err="${err:+$err; }first run exit $rc1"
[ -z "$out1" ] || err="${err:+$err; }first run emitted output: $out1"
[ "$rc2" -eq 0 ] || err="${err:+$err; }second run exit $rc2"
[ -z "$out2" ] || err="${err:+$err; }second run emitted output: $out2"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi
rm -f "${TMPDIR:-/tmp}/claude-plan-nudge-case-yield-merge" 2>/dev/null

exit $overall
