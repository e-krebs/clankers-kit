#!/usr/bin/env bash
# Runs every push-nudge fixture case and asserts on its output; exits non-zero on any failure.
# Locates the hook and the hook-log lib relative to this file's own path, so it keeps working
# once these fixtures are copied into the real repo.

set -u

fixtures_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
hook="$fixtures_dir/../../push-nudge.sh"
export AGENTS_HOOKS_LIB="$fixtures_dir/../../../../../hooks/lib"

overall=0
work=$(mktemp -d "${TMPDIR:-/tmp}/push-nudge-fixture.XXXXXX")
export AGENTS_HOOK_LOG="$work/hook-events.log"
trap 'rm -rf "$work" 2>/dev/null' EXIT

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

# fires <case> <fixture>: valid JSON on stdout naming the skill to invoke, and the sandbox log
# gains a push-nudge line
fires() {
  local case_name="$1" fixture="$2" ctx err="" logged
  run_hook "$fixture"
  ctx=$(ctx_of "$HOOK_OUT")
  [ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
  printf '%s' "$HOOK_OUT" | jq -e . >/dev/null 2>&1 || err="${err:+$err; }output is not valid JSON: $HOOK_OUT"
  printf '%s' "$HOOK_OUT" | jq -e '.hookSpecificOutput.hookEventName == "PostToolUse"' >/dev/null 2>&1 \
    || err="${err:+$err; }hookEventName is not PostToolUse"
  contains "$ctx" "pr-followup" || err="${err:+$err; }context does not name pr-followup: $ctx"
  contains "$ctx" "SKILL.md" || err="${err:+$err; }context does not say how to invoke it: $ctx"
  logged=$(tail -1 "$AGENTS_HOOK_LOG" 2>/dev/null)
  contains "$logged" "push-nudge" || err="${err:+$err; }log tail missing push-nudge: $logged"
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
if bash -n "$hook" 2>/tmp/pn-syn-hook.$$; then
  pass "syntax:hook"
else
  fail_case "syntax:hook" "bash -n failed: $(head -3 /tmp/pn-syn-hook.$$ 2>/dev/null)"
fi
rm -f /tmp/pn-syn-hook.$$ 2>/dev/null

if [ -f "$AGENTS_HOOKS_LIB/hook-log.sh" ] && bash -n "$AGENTS_HOOKS_LIB/hook-log.sh" 2>/tmp/pn-syn-lib.$$; then
  pass "syntax:lib"
else
  fail_case "syntax:lib" "missing or bash -n failed: $AGENTS_HOOKS_LIB/hook-log.sh"
fi
rm -f /tmp/pn-syn-lib.$$ 2>/dev/null

# --- fires ------------------------------------------------------------------
fires "fires" "sample-posttooluse-shell.json"
fires "fires-gh-pr-create" "gh-pr-create.json"

# --- silence ----------------------------------------------------------------
silent "silent-pretooluse" "sample-pretooluse-shell.json"
silent "silent-help" "sample-posttooluse-help.json"
silent "silent-dry-run" "dry-run.json"
silent "silent-malformed" "malformed.json"

exit $overall
