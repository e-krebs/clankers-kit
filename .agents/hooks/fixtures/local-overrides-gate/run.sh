#!/usr/bin/env bash
# Runs every local-overrides-gate fixture case and asserts on its output; exits non-zero on any
# failure. Each case builds a throwaway repo that carries the gate and its check script, so the gate
# never reads the real checkout.

set -u

fixtures_dir=$(CDPATH='' cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)
hooks_dir=$(CDPATH='' cd -P "$fixtures_dir/../.." && pwd)
gate="$hooks_dir/local-overrides-gate.sh"
check="$hooks_dir/../check-local-overrides.sh"
work=$(mktemp -d "${TMPDIR:-/tmp}/loc-overrides.XXXXXX")
export AGENTS_HOOK_LOG="$work/hook-events.log"
trap 'rm -rf "$work"' EXIT

overall=0
pass() { printf 'PASS %s\n' "$1"; }
fail_case() { printf 'FAIL %s: %s\n' "$1" "$2"; overall=1; }

# make_repo <name> <local json> <user json> -> prints a repo path carrying the gate
make_repo() {
  local repo="$work/$1"
  mkdir -p "$repo/.agents/hooks/lib" "$repo/.claude/settings"
  ( cd "$repo" && git init -q && printf '!.claude/settings.local.json\n' > .gitignore ) >/dev/null 2>&1
  cp "$gate" "$repo/.agents/hooks/"
  cp "$hooks_dir/lib/hook-log.sh" "$repo/.agents/hooks/lib/"
  cp "$check" "$repo/.agents/"
  printf '%s\n' "$2" > "$repo/.claude/settings.local.json"
  printf '%s\n' "$3" > "$repo/.claude/settings/base.json"
  printf '%s' "$repo"
}

HOOK_OUT=""
HOOK_RC=0
run_gate() {  # $1 = repo, $2 = fixture json
  HOOK_OUT=$(cd "$1" && bash "$1/.agents/hooks/local-overrides-gate.sh" < "$2" 2>/dev/null)
  HOOK_RC=$?
}

is_deny() {
  printf '%s' "$1" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1
}

reason_of() {
  printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null
}

contains() {  # haystack needle
  case "$1" in
    *"$2"*) return 0 ;;
    *) return 1 ;;
  esac
}

valid_local='{"skillOverrides":{"run":"on"}}'
hidden_user='{"skillOverrides":{"run":"user-invocable-only"}}'

# --- allow: a command that is not a commit passes, whatever the overrides say -------------
case_name="allow"
repo=$(make_repo allow "$valid_local" "{}")
run_gate "$repo" "$fixtures_dir/allow.json"
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ -z "$HOOK_OUT" ] || err="${err:+$err; }expected no output, got: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- key-not-hidden: a local key that base.json does not hide is denied -------------
case_name="key-not-hidden"
repo=$(make_repo key-not-hidden "$valid_local" '{"skillOverrides":{}}')
run_gate "$repo" "$fixtures_dir/key-not-hidden.json"
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
is_deny "$HOOK_OUT" || err="${err:+$err; }expected a deny, got: $HOOK_OUT"
contains "$(reason_of "$HOOK_OUT")" "run" || err="${err:+$err; }deny reason missing the skill name"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- value-not-on: a local value other than "on" is denied by the script check -----------
case_name="value-not-on"
repo=$(make_repo value-not-on '{"skillOverrides":{"run":"off"}}' "$hidden_user")
run_gate "$repo" "$fixtures_dir/value-not-on.json"
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
is_deny "$HOOK_OUT" || err="${err:+$err; }expected a deny, got: $HOOK_OUT"
contains "$(reason_of "$HOOK_OUT")" 'must be' || err="${err:+$err; }deny reason missing the script finding"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- check-mode: exit 0 on a clean repo, 1 on a failing one, no stdin read ------------------
case_name="check-mode"
clean=$(make_repo clean "$valid_local" "$hidden_user")
bad=$(make_repo bad "$valid_local" '{"skillOverrides":{}}')
err=""
bash "$gate" --check "$clean" </dev/null >/dev/null 2>&1 || err="clean repo exited non-zero"
bash "$gate" --check "$bad" </dev/null >/dev/null 2>&1 && err="${err:+$err; }failing repo exited 0"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

exit $overall
