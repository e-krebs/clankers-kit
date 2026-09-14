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

# --- approved-with-path -------------------------------------------------------
case_name="approved-with-path"
run_hook "$fixtures_dir/approved-with-path.json"
ctx=$(ctx_of "$HOOK_OUT")
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
contains "$ctx" "/Users/e/.claude/plans/foo-bar.md" || err="${err:+$err; }missing the saved path: $ctx"
contains "$ctx" "Deferred kickoff actions" || err="${err:+$err; }missing the ordering instruction"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- approved-without-path ----------------------------------------------------
case_name="approved-without-path"
run_hook "$fixtures_dir/approved-without-path.json"
ctx=$(ctx_of "$HOOK_OUT")
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
contains "$ctx" "Plan approved." || err="${err:+$err; }missing plain approval text: $ctx"
contains "$ctx" "Deferred kickoff actions" || err="${err:+$err; }missing the ordering instruction"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- rejected: silent ----------------------------------------------------------
case_name="rejected-silent"
run_hook "$fixtures_dir/rejected.json"
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ -z "$HOOK_OUT" ] || err="${err:+$err; }expected no output, got: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- agent_id: silent ------------------------------------------------------------
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

exit $overall
