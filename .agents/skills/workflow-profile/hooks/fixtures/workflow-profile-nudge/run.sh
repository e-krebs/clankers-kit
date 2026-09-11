#!/usr/bin/env bash
# Runs every workflow-profile-nudge fixture case and asserts on its output; exits non-zero on
# any failure. Locates the hook relative to this file's own path so it still works once these
# fixtures are copied into the real repo.

set -u

fixtures_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
hook="$fixtures_dir/../../workflow-profile-nudge.sh"
libfile="$fixtures_dir/../../../../../skills/workflow-profile/scripts/resolve-profile.sh"
export AGENTS_WORKFLOW_RESOLVER="$libfile"

overall=0
root=$(mktemp -d "${TMPDIR:-/tmp}/wpn.XXXXXX")
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

# copy_profiles <src-dir> -> prints path to a fresh temp copy (so .asked writes never touch fixtures)
copy_profiles() {
  local src="$1" dest
  dest=$(new_root)
  if [ -d "$src" ]; then
    cp -R "$src/." "$dest/" 2>/dev/null
  fi
  printf '%s' "$dest"
}

HOOK_OUT=""
HOOK_RC=0
run_hook() {
  local dir="$1" fixture="$2" prof="$3"
  HOOK_OUT=$(cd "$dir" && AGENTS_WORKFLOW_PROFILES="$prof" bash "$hook" < "$fixture" 2>/dev/null)
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

# --- syntax checks ---------------------------------------------------------
if bash -n "$hook" 2>/tmp/wpn-syn-hook.$$; then
  pass "syntax:hook"
else
  fail_case "syntax:hook" "bash -n failed: $(cat /tmp/wpn-syn-hook.$$ 2>/dev/null)"
fi
rm -f /tmp/wpn-syn-hook.$$ 2>/dev/null

if bash -n "$libfile" 2>/tmp/wpn-syn-lib.$$; then
  pass "syntax:lib"
else
  fail_case "syntax:lib" "bash -n failed: $(cat /tmp/wpn-syn-lib.$$ 2>/dev/null)"
fi
rm -f /tmp/wpn-syn-lib.$$ 2>/dev/null

# --- inject-org-and-override ------------------------------------------------
case_name="inject-org-and-override"
repo=$(make_repo "repo" "https://github.com/acme/widgets.git")
prof=$(copy_profiles "$fixtures_dir/profiles-acme-widgets")
run_hook "$repo" "$fixtures_dir/inject-org-and-override.json" "$prof"
ctx=$(ctx_of "$HOOK_OUT")
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
printf '%s' "$HOOK_OUT" | jq -e . >/dev/null 2>&1 || err="${err:+$err; }output is not valid JSON: $HOOK_OUT"
contains "$ctx" "org: acme" || err="${err:+$err; }missing 'org: acme'"
contains "$ctx" "| Default branch | develop |" || err="${err:+$err; }missing overridden Default branch row"
contains "$ctx" "| Ticket system | Linear (ACME) |" || err="${err:+$err; }missing untouched org row"
contains "$ctx" "Tracker rules live in" || err="${err:+$err; }missing Tracker rules pointer"
contains "$ctx" "Only move a ticket when its branch name carries the ticket ID; never guess." && err="${err:+$err; }leaked Tracker rules body text"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- inject-org-only ---------------------------------------------------------
case_name="inject-org-only"
repo=$(make_repo "repo" "git@github.com:acme/other.git")
prof=$(copy_profiles "$fixtures_dir/profiles-acme-only")
run_hook "$repo" "$fixtures_dir/inject-org-only.json" "$prof"
ctx=$(ctx_of "$HOOK_OUT")
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
contains "$ctx" "org: acme" || err="${err:+$err; }missing 'org: acme'"
contains "$ctx" "repo override: none" || err="${err:+$err; }missing 'repo override: none'"
contains "$ctx" "| Ticket system | Linear (ACME) |" || err="${err:+$err; }missing org rows"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- nudge-once ---------------------------------------------------------------
case_name="nudge-once"
repo=$(make_repo "repo" "https://github.com/nobody/fresh")
prof=$(copy_profiles "$fixtures_dir/profiles-empty")
run_hook "$repo" "$fixtures_dir/nudge-once.json" "$prof"
ctx1=$(ctx_of "$HOOK_OUT")
rc1="$HOOK_RC"
run_hook "$repo" "$fixtures_dir/nudge-once.json" "$prof"
out2="$HOOK_OUT"
rc2="$HOOK_RC"
err=""
[ "$rc1" -eq 0 ] || err="${err:+$err; }first run exit $rc1"
[ "$rc2" -eq 0 ] || err="${err:+$err; }second run exit $rc2"
contains "$ctx1" "nobody/fresh" || err="${err:+$err; }first run missing 'nobody/fresh'"
contains "$ctx1" "nobody.md" || err="${err:+$err; }first run missing 'nobody.md'"
[ -z "$out2" ] || err="${err:+$err; }second run emitted output: $out2"
[ -e "$prof/.asked/remote-nobody-fresh" ] || err="${err:+$err; }marker file missing"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- nudge-basename -------------------------------------------------------------
case_name="nudge-basename"
repo=$(make_repo "freshbase")
prof=$(copy_profiles "$fixtures_dir/profiles-empty")
run_hook "$repo" "$fixtures_dir/nudge-basename.json" "$prof"
ctx=$(ctx_of "$HOOK_OUT")
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
contains "$ctx" "(no remote)" || err="${err:+$err; }missing '(no remote)'"
contains "$ctx" "repos/freshbase.md" || err="${err:+$err; }missing 'repos/freshbase.md'"
[ -e "$prof/.asked/basename-freshbase" ] || err="${err:+$err; }marker file missing"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- basename-override -----------------------------------------------------------
case_name="basename-override"
repo=$(make_repo "sample-repo")
prof=$(copy_profiles "$fixtures_dir/profiles-basename-only")
run_hook "$repo" "$fixtures_dir/basename-override.json" "$prof"
ctx=$(ctx_of "$HOOK_OUT")
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
contains "$ctx" "org: none" || err="${err:+$err; }missing 'org: none'"
contains "$ctx" "| Ticket system | none |" || err="${err:+$err; }missing repo-file row"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- silence-subagent -------------------------------------------------------------
case_name="silence-subagent"
repo=$(make_repo "repo" "git@github.com:acme/other.git")
prof=$(copy_profiles "$fixtures_dir/profiles-acme-only")
run_hook "$repo" "$fixtures_dir/silence-subagent.json" "$prof"
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ -z "$HOOK_OUT" ] || err="${err:+$err; }expected no output, got: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- silence-not-a-repo -------------------------------------------------------------
case_name="silence-not-a-repo"
plain=$(new_root)
prof=$(copy_profiles "$fixtures_dir/profiles-empty")
run_hook "$plain" "$fixtures_dir/silence-not-a-repo.json" "$prof"
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ -z "$HOOK_OUT" ] || err="${err:+$err; }expected no output, got: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- malformed -------------------------------------------------------------------
case_name="malformed"
repo=$(make_repo "repo" "https://github.com/acme/widgets.git")
prof=$(copy_profiles "$fixtures_dir/profiles-acme-widgets")
run_hook "$repo" "$fixtures_dir/malformed.json" "$prof"
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ -z "$HOOK_OUT" ] || err="${err:+$err; }expected no output, got: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- ssh-form -------------------------------------------------------------------
case_name="ssh-form"
repo=$(make_repo "repo" "ssh://git@github.com/acme/widgets.git")
prof=$(copy_profiles "$fixtures_dir/profiles-acme-only")
run_hook "$repo" "$fixtures_dir/ssh-form.json" "$prof"
ctx=$(ctx_of "$HOOK_OUT")
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
contains "$ctx" "org: acme" || err="${err:+$err; }missing 'org: acme'"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- ssh-port: a URI authority with a port is not owner/repo -----------------------
case_name="ssh-port"
repo=$(make_repo "repo" "ssh://git@github.com:2222/acme/widgets.git")
prof=$(copy_profiles "$fixtures_dir/profiles-acme-widgets")
run_hook "$repo" "$fixtures_dir/ssh-port.json" "$prof"
ctx=$(ctx_of "$HOOK_OUT")
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
contains "$ctx" "org: acme" || err="${err:+$err; }missing 'org: acme'"
contains "$ctx" "repo override: widgets" || err="${err:+$err; }missing 'repo override: widgets'"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- trailing-slash: '.git/' still yields the repo name ----------------------------
case_name="trailing-slash"
repo=$(make_repo "repo" "https://github.com:443/acme/widgets.git/")
prof=$(copy_profiles "$fixtures_dir/profiles-acme-widgets")
run_hook "$repo" "$fixtures_dir/trailing-slash.json" "$prof"
ctx=$(ctx_of "$HOOK_OUT")
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
contains "$ctx" "org: acme" || err="${err:+$err; }missing 'org: acme'"
contains "$ctx" "| Default branch | develop |" || err="${err:+$err; }override not applied (repo name lost)"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- override-unset-inherits: an override '—' keeps the org value, 'none' replaces it ---
case_name="override-unset-inherits"
repo=$(make_repo "repo" "https://github.com/acme/widgets.git")
prof=$(copy_profiles "$fixtures_dir/profiles-acme-unset")
run_hook "$repo" "$fixtures_dir/override-unset-inherits.json" "$prof"
ctx=$(ctx_of "$HOOK_OUT")
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
contains "$ctx" "| CI watcher | GitHub Actions |" || err="${err:+$err; }override '—' erased the org CI watcher"
contains "$ctx" "| PR shape | none |" || err="${err:+$err; }override 'none' did not replace the org PR shape"
contains "$ctx" "| Default branch | develop |" || err="${err:+$err; }missing overridden Default branch row"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- empty / scalar stdin: nothing to act on ----------------------------------------
case_name="empty-stdin"
repo=$(make_repo "repo" "https://github.com/acme/widgets.git")
prof=$(copy_profiles "$fixtures_dir/profiles-acme-widgets")
run_hook "$repo" "$fixtures_dir/empty.json" "$prof"
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ -z "$HOOK_OUT" ] || err="${err:+$err; }expected no output, got: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

case_name="scalar-stdin"
run_hook "$repo" "$fixtures_dir/scalar.json" "$prof"
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ -z "$HOOK_OUT" ] || err="${err:+$err; }expected no output, got: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

exit $overall
