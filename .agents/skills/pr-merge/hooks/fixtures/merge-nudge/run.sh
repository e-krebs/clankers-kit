#!/usr/bin/env bash
# Runs every merge-nudge fixture case and asserts on its output; exits non-zero on any failure.
# Locates the hook and the guards library relative to this file's own path, so it keeps working
# once these fixtures are copied into the real repo.

set -u

fixtures_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
hook="$fixtures_dir/../../merge-nudge.sh"
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
  HOOK_OUT=$(bash "$hook" < "$fixtures_dir/$1" 2>/dev/null)
  HOOK_RC=$?
}

ctx_of() {
  printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null
}

contains() {  # haystack needle
  case "$1" in
    *"$2"*) return 0 ;;
    *) return 1 ;;
  esac
}

# fires <case> <fixture>: valid JSON on stdout naming the skill to invoke
fires() {
  local case_name="$1" fixture="$2" ctx err=""
  run_hook "$fixture"
  ctx=$(ctx_of "$HOOK_OUT")
  [ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
  printf '%s' "$HOOK_OUT" | jq -e . >/dev/null 2>&1 || err="${err:+$err; }output is not valid JSON: $HOOK_OUT"
  printf '%s' "$HOOK_OUT" | jq -e '.hookSpecificOutput.hookEventName == "UserPromptSubmit"' >/dev/null 2>&1 \
    || err="${err:+$err; }hookEventName is not UserPromptSubmit"
  contains "$ctx" "pr-merge" || err="${err:+$err; }context does not name pr-merge: $ctx"
  contains "$ctx" "SKILL.md" || err="${err:+$err; }context does not say how to invoke it: $ctx"
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

# --- syntax checks ---------------------------------------------------------
if bash -n "$hook" 2>/tmp/mn-syn-hook.$$; then
  pass "syntax:hook"
else
  fail_case "syntax:hook" "bash -n failed: $(head -3 /tmp/mn-syn-hook.$$ 2>/dev/null)"
fi
rm -f /tmp/mn-syn-hook.$$ 2>/dev/null

if [ -f "$libfile" ] && bash -n "$libfile" 2>/tmp/mn-syn-lib.$$; then
  pass "syntax:lib"
else
  fail_case "syntax:lib" "missing or bash -n failed: $libfile"
fi
rm -f /tmp/mn-syn-lib.$$ 2>/dev/null

# --- fires ------------------------------------------------------------------
fires "fires-pr" "fires-pr.json"

case_name="fires-pr-logs-nudge"
logged=$(tail -1 "$AGENTS_HOOK_LOG" 2>/dev/null)
case "$logged" in
  *" merge-nudge nudge -") pass "$case_name" ;;
  *) fail_case "$case_name" "log tail: $logged" ;;
esac

fires "fires-pull-request" "fires-pull-request.json"
fires "fires-that" "fires-that.json"
silent "merge-production" "merge-production.json"
silent "upper-negation" "upper-negation.json"

# --- silence ----------------------------------------------------------------
silent "negated" "negated.json"
silent "notification" "notification.json"
silent "unrelated" "unrelated.json"
silent "subagent" "subagent.json"
silent "malformed" "malformed.json"

exit $overall
