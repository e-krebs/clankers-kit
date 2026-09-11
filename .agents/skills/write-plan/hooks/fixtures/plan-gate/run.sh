#!/usr/bin/env bash
# Runs every plan-gate fixture case and asserts on its output; exits non-zero on any failure.
# Locates the hook relative to this file's own path so it still works once these fixtures are
# copied into the real repo. Static fixtures carry no "cwd" field — the hook falls back to $PWD,
# so run_hook cd's into the dynamically-created repo before invoking it, same as
# fixtures/workflow-profile-nudge/run.sh. Only the planFilePath cases build JSON at run time
# (the absolute path can't be known ahead of time); that's plumbing, not a deny pattern.

set -u

fixtures_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
hook="$fixtures_dir/../../plan-gate.sh"
libfile="$fixtures_dir/../../../../../skills/workflow-profile/scripts/resolve-profile.sh"
export AGENTS_WORKFLOW_RESOLVER="$libfile"

overall=0
root=$(mktemp -d "${TMPDIR:-/tmp}/pg.XXXXXX")
log_dir=$(mktemp -d "${TMPDIR:-/tmp}/hooklog.XXXXXX")
export AGENTS_HOOK_LOG="$log_dir/hook-events.log"
trap 'rm -rf "$root" "$log_dir" 2>/dev/null' EXIT

pass() { printf 'PASS %s\n' "$1"; }
fail_case() { printf 'FAIL %s: %s\n' "$1" "$2"; overall=1; }
skip_case() { printf 'SKIP %s: %s\n' "$1" "$2"; }

new_root() { mktemp -d "$root/root.XXXXXX"; }

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

copy_profiles() {
  local src="$1" dest
  dest=$(new_root)
  if [ -d "$src" ]; then
    cp -R "$src/." "$dest/" 2>/dev/null
  fi
  printf '%s' "$dest"
}

# copy_plan_pair [html-fixture-name] -> prints the path to a temp copy of the generic
# `Source: plan.html` stub, with the named HTML fixture (if any) copied alongside it as
# plan.html so the stub's relative Source: line resolves. Omit the name to leave the stub
# alone in an empty dir, for the missing-target case.
copy_plan_pair() {
  local html_name="$1" dir
  dir=$(new_root)
  cp "$fixtures_dir/plans/html/stub.md" "$dir/stub.md" 2>/dev/null
  if [ -n "$html_name" ]; then
    cp "$fixtures_dir/plans/html/$html_name" "$dir/plan.html" 2>/dev/null
  fi
  printf '%s' "$dir/stub.md"
}

HOOK_OUT=""
HOOK_RC=0
run_hook() {  # <dir> <fixture-file> <profiles-dir>
  local dir="$1" fixture="$2" prof="$3"
  HOOK_OUT=$(cd "$dir" && AGENTS_WORKFLOW_PROFILES="$prof" bash "$hook" < "$fixture" 2>/dev/null)
  HOOK_RC=$?
}

run_hook_json() {  # <dir> <json> <profiles-dir> — for the two cases that need a built payload
  local dir="$1" json="$2" prof="$3"
  HOOK_OUT=$(cd "$dir" && printf '%s' "$json" | AGENTS_WORKFLOW_PROFILES="$prof" bash "$hook" 2>/dev/null)
  HOOK_RC=$?
}

decision_of() { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null; }
reason_of()   { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null; }
ctx_of()      { printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null; }
contains() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }

# --- syntax checks -----------------------------------------------------------
if bash -n "$hook" 2>/tmp/pg-syn.$$; then
  pass "syntax:hook"
else
  fail_case "syntax:hook" "bash -n failed: $(head -1 /tmp/pg-syn.$$ 2>/dev/null)"
fi
rm -f /tmp/pg-syn.$$ 2>/dev/null

if bash -n "$libfile" 2>/tmp/pg-syn2.$$; then
  pass "syntax:resolve-profile-lib"
else
  fail_case "syntax:resolve-profile-lib" "bash -n failed: $(head -1 /tmp/pg-syn2.$$ 2>/dev/null)"
fi
rm -f /tmp/pg-syn2.$$ 2>/dev/null

# --- valid plan: silent allow -------------------------------------------------
case_name="valid-plan-allows-silently"
repo=$(make_repo "repo" "https://github.com/acme/widgets.git")
prof=$(copy_profiles "$fixtures_dir/profiles-resolved")
run_hook "$repo" "$fixtures_dir/valid.json" "$prof"
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
# style advisory context is allowed on a valid plan; a deny is not
printf '%s' "$HOOK_OUT" | grep -q 'permissionDecision' && err="${err:+$err; }expected no deny, got: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- missing Model pick heading -> deny (resolved profile) -------------------
case_name="missing-model-pick-denies"
rm -f "${TMPDIR:-/tmp}/claude-plan-gate-case-missing-model-pick" 2>/dev/null
repo=$(make_repo "repo" "https://github.com/acme/widgets.git")
prof=$(copy_profiles "$fixtures_dir/profiles-resolved")
run_hook "$repo" "$fixtures_dir/missing-model-pick.json" "$prof"
decision=$(decision_of "$HOOK_OUT")
reason=$(reason_of "$HOOK_OUT")
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ "$decision" = "deny" ] || err="${err:+$err; }expected permissionDecision=deny, got: $HOOK_OUT"
contains "$reason" "Model pick" || err="${err:+$err; }reason doesn't name Model pick: $reason"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- reordered headings -> deny (resolved profile) ----------------------------
case_name="reordered-headings-denies"
rm -f "${TMPDIR:-/tmp}/claude-plan-gate-case-reordered" 2>/dev/null
repo=$(make_repo "repo" "https://github.com/acme/widgets.git")
prof=$(copy_profiles "$fixtures_dir/profiles-resolved")
run_hook "$repo" "$fixtures_dir/reordered.json" "$prof"
decision=$(decision_of "$HOOK_OUT")
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ "$decision" = "deny" ] || err="${err:+$err; }expected permissionDecision=deny, got: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- TBD in Model pick -> deny (resolved profile) -----------------------------
case_name="tbd-model-pick-denies"
rm -f "${TMPDIR:-/tmp}/claude-plan-gate-case-tbd" 2>/dev/null
repo=$(make_repo "repo" "https://github.com/acme/widgets.git")
prof=$(copy_profiles "$fixtures_dir/profiles-resolved")
run_hook "$repo" "$fixtures_dir/tbd.json" "$prof"
decision=$(decision_of "$HOOK_OUT")
reason=$(reason_of "$HOOK_OUT")
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ "$decision" = "deny" ] || err="${err:+$err; }expected permissionDecision=deny, got: $HOOK_OUT"
contains "$reason" "placeholder" || err="${err:+$err; }reason doesn't mention the placeholder: $reason"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- unresolved profile -> advisory context, not deny -------------------------
case_name="unresolved-profile-advisory"
rm -f "${TMPDIR:-/tmp}/claude-plan-gate-case-unresolved" 2>/dev/null
repo=$(make_repo "repo" "https://github.com/acme/widgets.git")
prof=$(copy_profiles "$fixtures_dir/profiles-empty")
run_hook "$repo" "$fixtures_dir/unresolved-profile.json" "$prof"
decision=$(decision_of "$HOOK_OUT")
ctx=$(ctx_of "$HOOK_OUT")
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ -z "$decision" ] || err="${err:+$err; }expected no permissionDecision, got: $decision"
contains "$ctx" "placeholder" || err="${err:+$err; }expected the advisory message in additionalContext: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- planFilePath fallback when plan is empty ---------------------------------
case_name="planfilepath-fallback"
repo=$(new_root)
prof=$(copy_profiles "$fixtures_dir/profiles-empty")
json=$(jq -nc --arg pf "$fixtures_dir/plans/valid.md" \
  '{session_id:"case-planfilepath",hook_event_name:"PreToolUse",tool_name:"ExitPlanMode",tool_input:{plan:"",planFilePath:$pf}}')
run_hook_json "$repo" "$json" "$prof"
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
printf '%s' "$HOOK_OUT" | grep -q 'permissionDecision' && err="${err:+$err; }expected no deny (valid plan read via file), got: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- stall guard: 4th denial-worthy run in the same session allows -----------
case_name="stall-guard-allows-on-4th"
repo=$(make_repo "repo" "https://github.com/acme/widgets.git")
prof=$(copy_profiles "$fixtures_dir/profiles-resolved")
rm -f "${TMPDIR:-/tmp}/claude-plan-gate-case-stall-guard" 2>/dev/null
run_hook "$repo" "$fixtures_dir/stall-guard.json" "$prof"; d1=$(decision_of "$HOOK_OUT")
run_hook "$repo" "$fixtures_dir/stall-guard.json" "$prof"; d2=$(decision_of "$HOOK_OUT")
run_hook "$repo" "$fixtures_dir/stall-guard.json" "$prof"; d3=$(decision_of "$HOOK_OUT")
run_hook "$repo" "$fixtures_dir/stall-guard.json" "$prof"; d4=$(decision_of "$HOOK_OUT"); out4="$HOOK_OUT"
err=""
[ "$d1" = "deny" ] || err="${err:+$err; }1st run not denied: $d1"
[ "$d2" = "deny" ] || err="${err:+$err; }2nd run not denied: $d2"
[ "$d3" = "deny" ] || err="${err:+$err; }3rd run not denied: $d3"
[ -z "$d4" ] || err="${err:+$err; }4th run still denied"
[ -z "$out4" ] || err="${err:+$err; }4th run emitted output: $out4"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi
rm -f "${TMPDIR:-/tmp}/claude-plan-gate-case-stall-guard" 2>/dev/null

# --- malformed JSON: exit 0, no output ----------------------------------------
case_name="malformed"
repo=$(make_repo "repo" "https://github.com/acme/widgets.git")
prof=$(copy_profiles "$fixtures_dir/profiles-resolved")
run_hook "$repo" "$fixtures_dir/malformed.json" "$prof"
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ -z "$HOOK_OUT" ] || err="${err:+$err; }expected no output, got: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- missing planFilePath file: exit 0, no output -----------------------------
case_name="missing-file"
repo=$(new_root)
prof=$(copy_profiles "$fixtures_dir/profiles-resolved")
json=$(jq -nc --arg pf "$fixtures_dir/plans/does-not-exist.md" \
  '{session_id:"case-missing-file",hook_event_name:"PreToolUse",tool_name:"ExitPlanMode",tool_input:{plan:"",planFilePath:$pf}}')
run_hook_json "$repo" "$json" "$prof"
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ -z "$HOOK_OUT" ] || err="${err:+$err; }expected no output, got: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- agent_id set: silence regardless of plan content -------------------------
case_name="agent-id-silence"
repo=$(make_repo "repo" "https://github.com/acme/widgets.git")
prof=$(copy_profiles "$fixtures_dir/profiles-resolved")
run_hook "$repo" "$fixtures_dir/agent-id-silence.json" "$prof"
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ -z "$HOOK_OUT" ] || err="${err:+$err; }expected no output, got: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- both plan and planFilePath absent: allow ---------------------------------
case_name="both-absent-allows"
repo=$(new_root)
prof=$(copy_profiles "$fixtures_dir/profiles-resolved")
run_hook "$repo" "$fixtures_dir/both-absent.json" "$prof"
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ -z "$HOOK_OUT" ] || err="${err:+$err; }expected no output, got: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- style advisory: a valid ten-heading plan with a bold lead-in still allows, and carries
# the style miss as advisory context (style never blocks). Needs python3 and the committed
# style-metrics/measure.py with --document support. Skipped when this checkout has no
# .claude/style-metrics directory at all; still fails when the directory exists but python3 or
# the --document flag is missing, so a wrong scorer path can never pass silently.
case_name="style-advisory-allows-with-context"
style_metrics_dir="$fixtures_dir/../../../../../../.claude/style-metrics"
scorer="$style_metrics_dir/measure.py"
if [ ! -d "$style_metrics_dir" ]; then
  skip_case "$case_name" "no style-metrics directory in this checkout"
elif command -v python3 >/dev/null 2>&1 \
   && python3 "$scorer" --help 2>/dev/null | grep -q -- '--document'; then
  repo=$(make_repo "repo" "https://github.com/acme/widgets.git")
  prof=$(copy_profiles "$fixtures_dir/profiles-resolved")
  scratch_home=$(new_root)
  HOOK_OUT=$(cd "$repo" && HOME="$scratch_home" AGENTS_WORKFLOW_PROFILES="$prof" bash "$hook" < "$fixtures_dir/style-advisory.json" 2>/dev/null)
  HOOK_RC=$?
  decision=$(decision_of "$HOOK_OUT")
  ctx=$(ctx_of "$HOOK_OUT")
  err=""
  [ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
  [ -z "$decision" ] || err="${err:+$err; }expected no permissionDecision (style never blocks), got: $decision"
  contains "$ctx" "plan-gate style (advisory):" || err="${err:+$err; }expected the style advisory prefix, got: $HOOK_OUT"
  contains "$ctx" "bold" || err="${err:+$err; }expected a bold finding, got: $ctx"
  if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi
else
  fail_case "$case_name" "python3 or measure.py --document not found at $scorer"
fi

# --- HTML source of truth: Source: <path>.html means the HTML is the plan --------------------

# --- valid plan behind Source: -> silent allow ------------------------------
case_name="html-source-valid"
repo=$(make_repo "repo" "https://github.com/acme/widgets.git")
prof=$(copy_profiles "$fixtures_dir/profiles-resolved")
stub=$(copy_plan_pair "valid.html")
json=$(jq -nc --arg sid "case-html-valid" --arg pf "$stub" \
  '{session_id:$sid,hook_event_name:"PreToolUse",tool_name:"ExitPlanMode",tool_input:{plan:"",planFilePath:$pf}}')
run_hook_json "$repo" "$json" "$prof"
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
printf '%s' "$HOOK_OUT" | grep -q 'permissionDecision' && err="${err:+$err; }expected no deny, got: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- Model pick holds only TBD in the HTML -> deny (resolved profile) --------
case_name="html-source-missing-model"
rm -f "${TMPDIR:-/tmp}/claude-plan-gate-case-html-missing-model" 2>/dev/null
repo=$(make_repo "repo" "https://github.com/acme/widgets.git")
prof=$(copy_profiles "$fixtures_dir/profiles-resolved")
stub=$(copy_plan_pair "missing-model.html")
json=$(jq -nc --arg sid "case-html-missing-model" --arg pf "$stub" \
  '{session_id:$sid,hook_event_name:"PreToolUse",tool_name:"ExitPlanMode",tool_input:{plan:"",planFilePath:$pf}}')
run_hook_json "$repo" "$json" "$prof"
decision=$(decision_of "$HOOK_OUT")
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ "$decision" = "deny" ] || err="${err:+$err; }expected permissionDecision=deny, got: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- Source: names a file that doesn't exist -> fail open, allow silently ----
case_name="html-source-file-missing"
repo=$(make_repo "repo" "https://github.com/acme/widgets.git")
prof=$(copy_profiles "$fixtures_dir/profiles-resolved")
stub=$(copy_plan_pair "")
json=$(jq -nc --arg sid "case-html-file-missing" --arg pf "$stub" \
  '{session_id:$sid,hook_event_name:"PreToolUse",tool_name:"ExitPlanMode",tool_input:{plan:"",planFilePath:$pf}}')
run_hook_json "$repo" "$json" "$prof"
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ -z "$HOOK_OUT" ] || err="${err:+$err; }expected no output (missing HTML fails open), got: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- Model pick wraps its content in <p>/<code> tags, names Opus -> allow ----
case_name="html-tags-not-placeholders"
repo=$(make_repo "repo" "https://github.com/acme/widgets.git")
prof=$(copy_profiles "$fixtures_dir/profiles-resolved")
stub=$(copy_plan_pair "tags.html")
json=$(jq -nc --arg sid "case-html-tags" --arg pf "$stub" \
  '{session_id:$sid,hook_event_name:"PreToolUse",tool_name:"ExitPlanMode",tool_input:{plan:"",planFilePath:$pf}}')
run_hook_json "$repo" "$json" "$prof"
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
printf '%s' "$HOOK_OUT" | grep -q 'permissionDecision' && err="${err:+$err; }expected no deny, got: $HOOK_OUT"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

exit $overall
