#!/usr/bin/env bash
# Runs every memory-ask-gate case and asserts on its output; exits non-zero on any failure.
# Locates the hook relative to this file's own path, so it keeps working once these fixtures are
# copied elsewhere. Every case runs against a sandbox marker dir and a sandbox log, so the suite
# is hermetic and leaves nothing behind.

set -u

fixtures_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
hook="$fixtures_dir/../../memory-ask-gate.sh"

overall=0
work=$(mktemp -d "${TMPDIR:-/tmp}/memory-ask-gate-fixture.XXXXXX")
export AGENTS_HOOK_LOG="$work/hook-events.log"
export AGENTS_MEMORY_ASKED="$work/asked"
trap 'rm -rf "$work" 2>/dev/null' EXIT

pass() { printf 'PASS %s\n' "$1"; }
fail_case() { printf 'FAIL %s: %s\n' "$1" "$2"; overall=1; }

HOOK_OUT=""
HOOK_RC=0
run_hook() {
  HOOK_OUT=$(bash "$hook" < "$fixtures_dir/$1" 2>/dev/null)
  HOOK_RC=$?
}

contains() {  # haystack needle
  case "$1" in
    *"$2"*) return 0 ;;
    *) return 1 ;;
  esac
}

deny_reason_of() {
  printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null
}

# denies <case> <fixture> <needle in the reason>
denies() {
  local case_name="$1" fixture="$2" needle="$3" err="" reason logged
  run_hook "$fixture"
  [ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
  printf '%s' "$HOOK_OUT" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1 \
    || err="${err:+$err; }not a deny: $HOOK_OUT"
  printf '%s' "$HOOK_OUT" | jq -e '.hookSpecificOutput.hookEventName == "PreToolUse"' >/dev/null 2>&1 \
    || err="${err:+$err; }hookEventName is not PreToolUse"
  reason=$(deny_reason_of "$HOOK_OUT")
  contains "$reason" "$needle" || err="${err:+$err; }reason does not name $needle: $reason"
  # the message must stay agent-neutral: no harness-specific tool name
  contains "$reason" "AskUserQuestion" && err="${err:+$err; }reason names a harness-specific tool"
  logged=$(tail -1 "$AGENTS_HOOK_LOG" 2>/dev/null)
  contains "$logged" "memory-ask-gate deny" || err="${err:+$err; }log tail missing the deny: $logged"
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

# --- syntax -----------------------------------------------------------------
if bash -n "$hook" 2>"$work/syn"; then pass syntax:hook
else fail_case syntax:hook "bash -n failed: $(head -3 "$work/syn" 2>/dev/null)"; fi

# --- the gate ---------------------------------------------------------------
denies deny-new-memory new-memory.json "ask before writing one"
# the same write, after the user's yes, is the retry the marker lets through
silent retry-passes new-memory.json

# --- exemptions -------------------------------------------------------------
silent silent-index index-file.json
silent silent-outside-store outside-store.json
silent silent-edit-tool edit-tool.json
silent silent-malformed malformed.json

# --- an existing memory file is an update, not a creation -------------------
existing="$work/.claude/projects/-home-u-Projects-acme/memory/feedback_existing.md"
mkdir -p "$(dirname "$existing")"
: > "$existing"
payload="$work/existing.json"
jq -n --arg p "$existing" '{session_id:"case-existing",tool_name:"Write",tool_input:{file_path:$p,content:"x"}}' > "$payload"
HOOK_OUT=$(bash "$hook" < "$payload" 2>/dev/null); HOOK_RC=$?
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ -z "$HOOK_OUT" ] || err="${err:+$err; }an existing memory was gated: $HOOK_OUT"
if [ -z "$err" ]; then pass silent-existing-file; else fail_case silent-existing-file "$err"; fi

# --- a second session gets its own ask --------------------------------------
payload2="$work/other-session.json"
jq '.session_id = "case-other-session"' "$fixtures_dir/new-memory.json" > "$payload2"
HOOK_OUT=$(bash "$hook" < "$payload2" 2>/dev/null); HOOK_RC=$?
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
printf '%s' "$HOOK_OUT" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1 \
  || err="${err:+$err; }the marker leaked across sessions: $HOOK_OUT"
printf '%s' "$HOOK_OUT" | jq -e '.hookSpecificOutput.hookEventName == "PreToolUse"' >/dev/null 2>&1 \
  || err="${err:+$err; }hookEventName is not PreToolUse"
if [ -z "$err" ]; then pass deny-per-session; else fail_case deny-per-session "$err"; fi

exit $overall
