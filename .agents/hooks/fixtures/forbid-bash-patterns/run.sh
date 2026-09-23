#!/usr/bin/env bash
# Runs every forbid-bash-patterns fixture case and asserts on its output; exits non-zero on any
# failure. Locates the hook relative to this file's own path so it still works once these
# fixtures are copied into the real repo.

set -u

fixtures_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
hook="$fixtures_dir/../../forbid-bash-patterns.sh"

overall=0

pass() { printf 'PASS %s\n' "$1"; }
fail_case() { printf 'FAIL %s: %s\n' "$1" "$2"; overall=1; }

# --- sandboxes for the yarn-repo-scoped rules --------------------------------------------
# yarn_dir looks like a yarn repo root (git repo + yarn.lock, plus a subdir to check repo-root
# resolution from a nested cwd); plain_dir is its own git root with no yarn.lock, so a $TMPDIR
# that sits inside a yarn repo cannot leak a yarn.lock into the case through the walk-up.
yarn_dir=$(mktemp -d "${TMPDIR:-/tmp}/fbp-yarn.XXXXXX")
plain_dir=$(mktemp -d "${TMPDIR:-/tmp}/fbp-plain.XXXXXX")
log_dir=$(mktemp -d "${TMPDIR:-/tmp}/hooklog.XXXXXX")
export AGENTS_HOOK_LOG="$log_dir/hook-events.log"
trap 'rm -rf "$yarn_dir" "$plain_dir" "$log_dir"' EXIT
(cd "$yarn_dir" && git init -q)
(cd "$plain_dir" && git init -q)
: > "$yarn_dir/yarn.lock"
mkdir -p "$yarn_dir/sub"

# with_cwd <case-file> <dir> -> writes a copy of <case-file> with .cwd=<dir> into a temp file
# inside <dir>, and prints that file's path.
with_cwd() {
  local case_file="$1" dir="$2" out
  out=$(mktemp "$dir/fbp-case.XXXXXX")   # no dot-suffix: this mktemp only substitutes a
                                          # trailing run of X's, not one followed by more text
  jq --arg c "$dir" '.cwd = $c' "$case_file" > "$out"
  printf '%s' "$out"
}

HOOK_OUT=""
HOOK_RC=0
run_hook() {  # $1 = case file, $2 = optional mode arg
  local fixture="$1" mode="${2:-}"
  if [ -n "$mode" ]; then
    HOOK_OUT=$(bash "$hook" "$mode" < "$fixture" 2>/dev/null)
  else
    HOOK_OUT=$(bash "$hook" < "$fixture" 2>/dev/null)
  fi
  HOOK_RC=$?
}

is_deny() {
  printf '%s' "$1" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1
}

deny_reason_of() {
  printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null
}

# assert_deny <name> <case-file> [mode]
assert_deny() {
  local name="$1" file="$2" mode="${3:-}" err="" reason
  run_hook "$file" "$mode"
  [ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
  is_deny "$HOOK_OUT" || err="${err:+$err; }expected a deny, got: $HOOK_OUT"
  if [ -z "$err" ]; then
    reason=$(deny_reason_of "$HOOK_OUT")
    [ -n "$reason" ] || err="empty deny reason"
  fi
  if [ -z "$err" ]; then pass "$name"; else fail_case "$name" "$err"; fi
}

# assert_allow <name> <case-file> [mode]
assert_allow() {
  local name="$1" file="$2" mode="${3:-}" err=""
  run_hook "$file" "$mode"
  [ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
  [ -z "$HOOK_OUT" ] || err="${err:+$err; }expected no output, got: $HOOK_OUT"
  if [ -z "$err" ]; then pass "$name"; else fail_case "$name" "$err"; fi
}

# assert_yarn_case <label> <case-file> [mode] — for a rule that only fires when the payload
# cwd's repo root holds a yarn.lock: asserts deny from the yarn repo root, deny from a subdir
# of it (repo-root resolution), and allow from a plain (non-yarn) directory.
assert_yarn_case() {
  local label="$1" file="$2" mode="${3:-}" tag=""
  [ -n "$mode" ] && tag="codex-"
  assert_deny  "${tag}${label}-yarn-root" "$(with_cwd "$file" "$yarn_dir")"     "$mode"
  assert_deny  "${tag}${label}-yarn-sub"  "$(with_cwd "$file" "$yarn_dir/sub")" "$mode"
  assert_allow "${tag}${label}-plain"     "$(with_cwd "$file" "$plain_dir")"   "$mode"
}

# --- syntax check -----------------------------------------------------------
if bash -n "$hook" 2>/tmp/fbp-syn.$$; then
  pass "syntax:hook"
else
  fail_case "syntax:hook" "bash -n failed"
fi
rm -f /tmp/fbp-syn.$$ 2>/dev/null

# --- claude mode (default): deny, one per rule ------------------------------
assert_deny "deny-echo-var"      "$fixtures_dir/deny-echo-var.json"

case_name="deny-echo-var-logs-rule"
logged=$(tail -1 "$AGENTS_HOOK_LOG" 2>/dev/null)
case "$logged" in
  *" forbid-bash-patterns deny echo") pass "$case_name" ;;
  *) fail_case "$case_name" "log tail: $logged" ;;
esac

assert_deny "deny-echo-subst"    "$fixtures_dir/deny-echo-subst.json"
assert_deny "deny-echo-loop"     "$fixtures_dir/deny-echo-loop.json"
assert_deny "deny-xargs-rm"      "$fixtures_dir/deny-xargs-rm.json"
assert_deny "deny-find-delete"   "$fixtures_dir/deny-find-delete.json"
assert_deny "deny-sort-o"        "$fixtures_dir/deny-sort-o.json"

# --- claude mode: allow ------------------------------------------------------
# The next seven cases cover the six dropped rules (sed and cat get one each); they stay as
# allow cases so a re-added rule is a deliberate edit here too.
assert_allow "allow-cd"         "$fixtures_dir/allow-cd.json"
assert_allow "allow-git-c"      "$fixtures_dir/allow-git-c.json"
assert_allow "allow-awk"        "$fixtures_dir/allow-awk.json"
assert_allow "allow-cat"        "$fixtures_dir/allow-cat.json"
assert_allow "allow-sed"        "$fixtures_dir/allow-sed.json"
assert_allow "allow-for-loop"   "$fixtures_dir/allow-for-loop.json"
assert_allow "allow-python-c"   "$fixtures_dir/allow-python-c.json"
assert_allow "allow-git-status" "$fixtures_dir/allow-git-status.json"
assert_allow "allow-xargs-grep" "$fixtures_dir/allow-xargs-grep.json"
assert_allow "allow-xargs-wc"   "$fixtures_dir/allow-xargs-wc.json"
assert_allow "allow-xargs-ls"   "$fixtures_dir/allow-xargs-ls.json"
assert_allow "allow-echo-exit"  "$fixtures_dir/allow-echo-exit.json"
assert_allow "allow-echo-lower"      "$fixtures_dir/allow-echo-lower.json"
assert_allow "allow-echo-pipestatus" "$fixtures_dir/allow-echo-pipestatus.json"
assert_allow "allow-yarn-test"  "$fixtures_dir/allow-yarn-test.json"
assert_allow "allow-tree"       "$fixtures_dir/allow-tree.json"

# --- codex mode: every rule still runs (the arg is a reserved seam, not a relaxation) ---
assert_deny "codex-deny-xargs-rm"    "$fixtures_dir/deny-xargs-rm.json"    codex
assert_deny "codex-deny-find-delete" "$fixtures_dir/deny-find-delete.json" codex
assert_deny "codex-deny-echo-var"    "$fixtures_dir/deny-echo-var.json"    codex
assert_deny "codex-deny-sort-o"      "$fixtures_dir/deny-sort-o.json"      codex
assert_allow "codex-allow-cat"       "$fixtures_dir/allow-cat.json"        codex

# --- yarn-repo-scoped rules: deny in a yarn repo (root and subdir), allow in a plain dir,
#     in both claude and codex mode ------------------------------------------------------
assert_yarn_case "deny-npx"           "$fixtures_dir/deny-npx.json"
assert_yarn_case "deny-npm"           "$fixtures_dir/deny-npm.json"
assert_yarn_case "deny-yarn-jest"     "$fixtures_dir/deny-yarn-jest.json"
assert_yarn_case "deny-yarn-run-lint" "$fixtures_dir/deny-yarn-run-lint.json"
assert_yarn_case "deny-yarn-cwd"      "$fixtures_dir/deny-yarn-cwd.json"

assert_yarn_case "deny-npx"           "$fixtures_dir/deny-npx.json"           codex
assert_yarn_case "deny-npm"           "$fixtures_dir/deny-npm.json"           codex
assert_yarn_case "deny-yarn-jest"     "$fixtures_dir/deny-yarn-jest.json"     codex
assert_yarn_case "deny-yarn-run-lint" "$fixtures_dir/deny-yarn-run-lint.json" codex
assert_yarn_case "deny-yarn-cwd"      "$fixtures_dir/deny-yarn-cwd.json"      codex

# --- $PWD fallback: a cwd-less payload uses the hook's own working directory as cwd --------
pwd_fallback_out=$(cd "$yarn_dir" && bash "$hook" < "$fixtures_dir/deny-npx.json" 2>/dev/null)
if is_deny "$pwd_fallback_out"; then
  pass "pwd-fallback-deny-npx"
else
  fail_case "pwd-fallback-deny-npx" "expected a deny, got: $pwd_fallback_out"
fi

# --- unknown mode falls back to claude ---------------------------------------
assert_deny "bogus-mode-deny-echo-var" "$fixtures_dir/deny-echo-var.json" bogus

exit $overall
