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
contains "$ctx1" "EnterPlanMode" && err="${err:+$err; }plan-mode run names EnterPlanMode: $ctx1"
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

# --- "let's work on" is a trigger phrase ---------------------------------------
case_name="branch-b-work-on-fires"
run_hook "$fixtures_dir/branch-b-work-on-fires.json"
ctx=$(ctx_of "$HOOK_OUT")
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
contains "$ctx" "Ask whether to plan" || err="${err:+$err; }missing ask-first wording: $ctx"
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

# --- an execute request yields to plan-execute: branch A silent -----------------
case_name="execute-plan-mode-silent"
rm -f "${TMPDIR:-/tmp}/claude-plan-nudge-case-execute-plan-mode" 2>/dev/null
run_hook "$fixtures_dir/execute-plan-mode-silent.json"
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ -z "$HOOK_OUT" ] || err="${err:+$err; }expected no output, got: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi
rm -f "${TMPDIR:-/tmp}/claude-plan-nudge-case-execute-plan-mode" 2>/dev/null

# --- an execute request holding a trigger phrase: branch B silent ---------------
case_name="execute-trigger-phrase-silent"
run_hook "$fixtures_dir/execute-trigger-phrase-silent.json"
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ -z "$HOOK_OUT" ] || err="${err:+$err; }expected no output, got: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- branch A fires in default mode, interactive Claude Code session -----------
case_name="branch-a-default-mode-fires"
rm -f "${TMPDIR:-/tmp}/claude-plan-nudge-case-default-fires" 2>/dev/null
HOOK_OUT=$(CLAUDECODE=1 CLAUDE_CODE_ENTRYPOINT=cli bash "$hook" < "$fixtures_dir/branch-a-default-mode-fires.json" 2>/dev/null)
HOOK_RC=$?
ctx=$(ctx_of "$HOOK_OUT")
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
contains "$ctx" "write-plan" || err="${err:+$err; }missing write-plan mention: $ctx"
contains "$ctx" "ToolSearch select:EnterPlanMode,ExitPlanMode" || err="${err:+$err; }missing EnterPlanMode hint: $ctx"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi
rm -f "${TMPDIR:-/tmp}/claude-plan-nudge-case-default-fires" 2>/dev/null

# --- branch A stays silent in default mode outside Claude Code (e.g. Codex) ----
case_name="branch-a-default-mode-codex-silent"
rm -f "${TMPDIR:-/tmp}/claude-plan-nudge-case-default-codex" 2>/dev/null
HOOK_OUT=$(env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT bash "$hook" < "$fixtures_dir/branch-a-default-mode-codex-silent.json" 2>/dev/null)
HOOK_RC=$?
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ -z "$HOOK_OUT" ] || err="${err:+$err; }expected no output, got: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi
rm -f "${TMPDIR:-/tmp}/claude-plan-nudge-case-default-codex" 2>/dev/null

# --- branch A stays silent in default mode for an sdk entrypoint ---------------
case_name="branch-a-default-mode-sdk-silent"
rm -f "${TMPDIR:-/tmp}/claude-plan-nudge-case-default-sdk" 2>/dev/null
HOOK_OUT=$(CLAUDECODE=1 CLAUDE_CODE_ENTRYPOINT=sdk-cli bash "$hook" < "$fixtures_dir/branch-a-default-mode-sdk-silent.json" 2>/dev/null)
HOOK_RC=$?
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ -z "$HOOK_OUT" ] || err="${err:+$err; }expected no output, got: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi
rm -f "${TMPDIR:-/tmp}/claude-plan-nudge-case-default-sdk" 2>/dev/null

# --- branch A stays silent in acceptEdits mode ----------------------------------
case_name="branch-a-accept-edits-silent"
rm -f "${TMPDIR:-/tmp}/claude-plan-nudge-case-accept-edits" 2>/dev/null
HOOK_OUT=$(CLAUDECODE=1 CLAUDE_CODE_ENTRYPOINT=cli bash "$hook" < "$fixtures_dir/branch-a-accept-edits-silent.json" 2>/dev/null)
HOOK_RC=$?
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ -z "$HOOK_OUT" ] || err="${err:+$err; }expected no output, got: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi
rm -f "${TMPDIR:-/tmp}/claude-plan-nudge-case-accept-edits" 2>/dev/null

# --- branch A stays silent for --codex even with inherited Claude env vars -----
case_name="branch-a-codex-arg-silent-with-claude-env-inherited"
rm -f "${TMPDIR:-/tmp}/claude-plan-nudge-case-codex-arg-inherited" 2>/dev/null
HOOK_OUT=$(CLAUDECODE=1 CLAUDE_CODE_ENTRYPOINT=cli bash "$hook" --codex < "$fixtures_dir/branch-a-codex-arg-silent-with-claude-env-inherited.json" 2>/dev/null)
HOOK_RC=$?
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ -z "$HOOK_OUT" ] || err="${err:+$err; }expected no output, got: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi
rm -f "${TMPDIR:-/tmp}/claude-plan-nudge-case-codex-arg-inherited" 2>/dev/null

exit $overall
