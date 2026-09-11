#!/usr/bin/env bash
# Runs every commit-subject-gate fixture case and asserts on its output; exits non-zero on any
# failure. Locates the hook relative to this file's own path so it still works once these
# fixtures are copied into the real repo.

set -u

fixtures_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
hook="$fixtures_dir/../../commit-subject-gate.sh"
libfile="$fixtures_dir/../../../skills/workflow-profile/scripts/resolve-profile.sh"
export AGENTS_WORKFLOW_RESOLVER="$libfile"

overall=0
root=$(mktemp -d "${TMPDIR:-/tmp}/csg.XXXXXX")
log_dir=$(mktemp -d "${TMPDIR:-/tmp}/hooklog.XXXXXX")
export AGENTS_HOOK_LOG="$log_dir/hook-events.log"
trap 'rm -rf "$root" "$log_dir" 2>/dev/null' EXIT

pass() { printf 'PASS %s\n' "$1"; }
fail_case() { printf 'FAIL %s: %s\n' "$1" "$2"; overall=1; }

new_root() {
  mktemp -d "$root/root.XXXXXX"
}

# make_repo <dirname> [remote-url] -> prints repo path
make_repo() {
  local parent name="$1" remote="${2:-}" repo
  parent=$(new_root)
  repo="$parent/$name"
  mkdir -p "$repo"
  ( cd "$repo" && git init -q && git config user.email t@t.com && git config user.name t ) >/dev/null 2>&1
  if [ -n "$remote" ]; then
    ( cd "$repo" && git remote add origin "$remote" ) >/dev/null 2>&1
  fi
  printf '%s' "$repo"
}

# copy_profiles <src-dir> -> prints path to a fresh temp copy
copy_profiles() {
  local src="$1" dest
  dest=$(new_root)
  if [ -d "$src" ]; then
    cp -R "$src/." "$dest/" 2>/dev/null
  fi
  printf '%s' "$dest"
}

# missing_profiles_dir -> prints a path under $root that is never created
missing_profiles_dir() {
  printf '%s' "$root/never-created-$$"
}

HOOK_OUT=""
HOOK_RC=0
run_hook() {
  local dir="$1" fixture="$2" prof="$3"
  HOOK_OUT=$(cd "$dir" && AGENTS_WORKFLOW_PROFILES="$prof" bash "$hook" < "$fixture" 2>/dev/null)
  HOOK_RC=$?
}

deny_reason_of() {
  printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null
}

is_deny() {
  printf '%s' "$1" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1
}

contains() {  # haystack needle
  case "$1" in
    *"$2"*) return 0 ;;
    *) return 1 ;;
  esac
}

# --- syntax checks ---------------------------------------------------------
if bash -n "$hook" 2>/tmp/csg-syn-hook.$$; then
  pass "syntax:hook"
else
  fail_case "syntax:hook" "bash -n failed: $(cat /tmp/csg-syn-hook.$$ 2>/dev/null)"
fi
rm -f /tmp/csg-syn-hook.$$ 2>/dev/null

if bash -n "$libfile" 2>/tmp/csg-syn-lib.$$; then
  pass "syntax:lib"
else
  fail_case "syntax:lib" "bash -n failed: $(cat /tmp/csg-syn-lib.$$ 2>/dev/null)"
fi
rm -f /tmp/csg-syn-lib.$$ 2>/dev/null

conv_prof=$(copy_profiles "$fixtures_dir/profiles-conventional")
free_prof=$(copy_profiles "$fixtures_dir/profiles-freeform")
empty_prof=$(copy_profiles "$fixtures_dir/profiles-empty")
scoped_prof=$(copy_profiles "$fixtures_dir/profiles-scoped")
plain_prof=$(copy_profiles "$fixtures_dir/profiles-plain")
never_prof=$(missing_profiles_dir)

# --- valid: type(scope): text passes ------------------------------------------------
case_name="valid"
repo=$(make_repo "repo" "https://github.com/acme/proj.git")
run_hook "$repo" "$fixtures_dir/valid.json" "$conv_prof"
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ -z "$HOOK_OUT" ] || err="${err:+$err; }expected no deny, got: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- missing-scope: 'feat: add x' denied --------------------------------------------
case_name="missing-scope"
repo=$(make_repo "repo" "https://github.com/acme/proj.git")
run_hook "$repo" "$fixtures_dir/missing-scope.json" "$conv_prof"
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
is_deny "$HOOK_OUT" || err="${err:+$err; }expected a deny, got: $HOOK_OUT"
reason=$(deny_reason_of "$HOOK_OUT")
contains "$reason" "feat: add x" || err="${err:+$err; }deny reason missing the subject"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- ticket-key: subject carries ACME-123 denied ----------------------------------
case_name="ticket-key"
repo=$(make_repo "repo" "https://github.com/acme/proj.git")
run_hook "$repo" "$fixtures_dir/ticket-key.json" "$conv_prof"
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
is_deny "$HOOK_OUT" || err="${err:+$err; }expected a deny, got: $HOOK_OUT"
reason=$(deny_reason_of "$HOOK_OUT")
contains "$reason" "ticket key" || err="${err:+$err; }deny reason missing 'ticket key'"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- scoped-ticket-key: 'conventional w/ scope' says nothing about ticket refs, passes ---
case_name="scoped-ticket-key"
repo=$(make_repo "repo" "https://github.com/scoped/proj.git")
run_hook "$repo" "$fixtures_dir/scoped-ticket-key.json" "$scoped_prof"
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ -z "$HOOK_OUT" ] || err="${err:+$err; }expected no deny (no ticket rule in the row), got: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- plain-noscope: plain 'conventional' accepts 'feat: add x' ----------------------
case_name="plain-noscope"
repo=$(make_repo "repo" "https://github.com/plain/proj.git")
run_hook "$repo" "$fixtures_dir/plain-noscope.json" "$plain_prof"
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ -z "$HOOK_OUT" ] || err="${err:+$err; }expected no deny (no scope rule in the row), got: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- plain-notype: plain 'conventional' still denies 'add x' ------------------------
case_name="plain-notype"
repo=$(make_repo "repo" "https://github.com/plain/proj.git")
run_hook "$repo" "$fixtures_dir/plain-notype.json" "$plain_prof"
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
is_deny "$HOOK_OUT" || err="${err:+$err; }expected a deny, got: $HOOK_OUT"
reason=$(deny_reason_of "$HOOK_OUT")
contains "$reason" "add x" || err="${err:+$err; }deny reason missing the subject"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- utf-code: 'UTF-8' in the subject is not a ticket key, passes -------------------
case_name="utf-code"
repo=$(make_repo "repo" "https://github.com/acme/proj.git")
run_hook "$repo" "$fixtures_dir/utf-code.json" "$conv_prof"
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ -z "$HOOK_OUT" ] || err="${err:+$err; }expected no deny, got: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- heredoc-valid: heredoc form, clean subject, passes -----------------------------
case_name="heredoc-valid"
repo=$(make_repo "repo" "https://github.com/acme/proj.git")
run_hook "$repo" "$fixtures_dir/heredoc-valid.json" "$conv_prof"
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ -z "$HOOK_OUT" ] || err="${err:+$err; }expected no deny, got: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- heredoc-body-ticket: ticket key in the body is free, passes --------------------
case_name="heredoc-body-ticket"
repo=$(make_repo "repo" "https://github.com/acme/proj.git")
run_hook "$repo" "$fixtures_dir/heredoc-body-ticket.json" "$conv_prof"
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ -z "$HOOK_OUT" ] || err="${err:+$err; }expected no deny, got: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- message-equals: --message=chore(x): y passes -----------------------------------
case_name="message-equals"
repo=$(make_repo "repo" "https://github.com/acme/proj.git")
run_hook "$repo" "$fixtures_dir/message-equals.json" "$conv_prof"
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ -z "$HOOK_OUT" ] || err="${err:+$err; }expected no deny, got: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- dash-f: -F file skipped ---------------------------------------------------------
case_name="dash-f"
repo=$(make_repo "repo" "https://github.com/acme/proj.git")
run_hook "$repo" "$fixtures_dir/dash-f.json" "$conv_prof"
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ -z "$HOOK_OUT" ] || err="${err:+$err; }expected no deny, got: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- amend-no-edit: --amend --no-edit skipped ----------------------------------------
case_name="amend-no-edit"
repo=$(make_repo "repo" "https://github.com/acme/proj.git")
run_hook "$repo" "$fixtures_dir/amend-no-edit.json" "$conv_prof"
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ -z "$HOOK_OUT" ] || err="${err:+$err; }expected no deny, got: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- dollar-subject: a $-prefixed subject fails open ---------------------------------
case_name="dollar-subject"
repo=$(make_repo "repo" "https://github.com/acme/proj.git")
run_hook "$repo" "$fixtures_dir/dollar-subject.json" "$conv_prof"
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ -z "$HOOK_OUT" ] || err="${err:+$err; }expected no deny, got: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- freeform-profile: a would-be-denied subject passes under a non-conventional profile
case_name="freeform-profile"
repo=$(make_repo "repo" "https://github.com/free/proj.git")
run_hook "$repo" "$fixtures_dir/freeform-profile.json" "$free_prof"
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ -z "$HOOK_OUT" ] || err="${err:+$err; }expected the gate to skip (freeform profile), got: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- no-profile: a would-be-denied subject passes when nothing resolves -------------
case_name="no-profile"
repo=$(make_repo "repo" "https://github.com/nobody/nowhere.git")
run_hook "$repo" "$fixtures_dir/no-profile.json" "$empty_prof"
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ -z "$HOOK_OUT" ] || err="${err:+$err; }expected the gate to skip (no profile), got: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- two-dash-m: only the first -m is the subject, second (with a ticket key) is body
case_name="two-dash-m"
repo=$(make_repo "repo" "https://github.com/acme/proj.git")
run_hook "$repo" "$fixtures_dir/two-dash-m.json" "$conv_prof"
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ -z "$HOOK_OUT" ] || err="${err:+$err; }expected no deny, got: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- first-m-wins: a later --message= is body, not the subject
case_name="first-m-wins"
repo=$(make_repo "repo" "https://github.com/acme/proj.git")
run_hook "$repo" "$fixtures_dir/first-m-wins.json" "$conv_prof"
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ -z "$HOOK_OUT" ] || err="${err:+$err; }expected no deny, got: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- segment-isolation: 'git status && git commit -m "feat: x"' still gets isolated -
case_name="segment-isolation"
repo=$(make_repo "repo" "https://github.com/acme/proj.git")
run_hook "$repo" "$fixtures_dir/segment-isolation.json" "$conv_prof"
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
is_deny "$HOOK_OUT" || err="${err:+$err; }expected a deny, got: $HOOK_OUT"
reason=$(deny_reason_of "$HOOK_OUT")
contains "$reason" "feat: x" || err="${err:+$err; }deny reason missing the isolated subject"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- malformed: bad JSON stays silent, exit 0 ----------------------------------------
case_name="malformed"
repo=$(make_repo "repo" "https://github.com/acme/proj.git")
run_hook "$repo" "$fixtures_dir/malformed.json" "$conv_prof"
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ -z "$HOOK_OUT" ] || err="${err:+$err; }expected no output, got: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- missing-profiles-dir: AGENTS_WORKFLOW_PROFILES points nowhere, stays silent -----
case_name="missing-profiles-dir"
repo=$(make_repo "repo" "https://github.com/acme/proj.git")
run_hook "$repo" "$fixtures_dir/missing-profiles-dir.json" "$never_prof"
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ -z "$HOOK_OUT" ] || err="${err:+$err; }expected no output, got: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- agent-id: a subagent session stays silent regardless of the subject -----------
case_name="agent-id"
repo=$(make_repo "repo" "https://github.com/acme/proj.git")
run_hook "$repo" "$fixtures_dir/agent-id.json" "$conv_prof"
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ -z "$HOOK_OUT" ] || err="${err:+$err; }expected no output, got: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

exit $overall
