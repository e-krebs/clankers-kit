#!/usr/bin/env bash
# Runs every forbid-verbose-comments fixture case and asserts on its output; exits non-zero on
# any failure. Locates the hook relative to this file's own path, so it keeps working once these
# fixtures are copied into the real repo.

set -u

fixtures_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
hook="$fixtures_dir/../../forbid-verbose-comments.sh"

overall=0
log_dir=$(mktemp -d "${TMPDIR:-/tmp}/hooklog.XXXXXX")
export AGENTS_HOOK_LOG="$log_dir/hook-events.log"
trap 'rm -rf "$log_dir" 2>/dev/null' EXIT

pass() { printf 'PASS %s\n' "$1"; }
fail_case() { printf 'FAIL %s: %s\n' "$1" "$2"; overall=1; }

HOOK_OUT=""
HOOK_RC=0
run_hook() {
  HOOK_OUT=$(bash "$hook" < "$fixtures_dir/$1" 2>/dev/null)
  HOOK_RC=$?
}

is_deny() {
  printf '%s' "$1" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1
}

deny_reason_of() {
  printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null
}

contains() {  # haystack needle
  case "$1" in
    *"$2"*) return 0 ;;
    *) return 1 ;;
  esac
}

# denies <case> <fixture> <substring the reason must name>
denies() {
  local case_name="$1" fixture="$2" want="$3" err=""
  run_hook "$fixture"
  [ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
  is_deny "$HOOK_OUT" || err="${err:+$err; }expected a deny, got: $HOOK_OUT"
  contains "$(deny_reason_of "$HOOK_OUT")" "$want" || err="${err:+$err; }deny reason missing '$want'"
  if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi
}

# silent <case> <fixture>: exit 0, nothing on stdout
silent() {
  local case_name="$1" fixture="$2" err=""
  run_hook "$fixture"
  [ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
  [ -z "$HOOK_OUT" ] || err="${err:+$err; }expected no output, got: $HOOK_OUT"
  if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi
}

# --- syntax check -----------------------------------------------------------
if bash -n "$hook" 2>/tmp/fvc-syn.$$; then
  pass "syntax:hook"
else
  fail_case "syntax:hook" "bash -n failed: $(head -3 /tmp/fvc-syn.$$ 2>/dev/null)"
fi
rm -f /tmp/fvc-syn.$$ 2>/dev/null

# --- Edit: unchanged behavior ------------------------------------------------
denies "deny-jsdoc-edit" "deny-jsdoc-edit.json" "JSDoc"
silent "allow-terse-edit" "allow-terse-edit.json"

# --- MultiEdit: the new case --------------------------------------------------
denies "deny-jsdoc-multiedit" "deny-jsdoc-multiedit.json" "JSDoc"
silent "allow-terse-multiedit" "allow-terse-multiedit.json"

# --- JavaScript: the new case --------------------------------------------------
denies "deny-jsdoc-js" "deny-jsdoc-js.json" "JSDoc"
silent "allow-terse-js" "allow-terse-js.json"

# --- silence ------------------------------------------------------------------
silent "silent-non-code" "silent-non-code.json"
silent "silent-agent-id" "silent-agent-id.json"
silent "malformed" "malformed.json"

exit $overall
