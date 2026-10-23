#!/usr/bin/env bash
# Runs every plan-gate fixture case and asserts on its output; exits non-zero on any failure.
# Locates the hook relative to this file's own path so it still works once these fixtures are
# copied into the real repo. Static fixtures carry no "cwd" field — the hook falls back to $PWD,
# so run_hook cd's into the dynamically-created repo before invoking it, same as
# fixtures/workflow-profile-nudge/run.sh. The planFilePath cases and the one-rule variants build
# their JSON at run time from plans/valid.md; that's plumbing, not a deny pattern.

set -u

fixtures_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
hook="$fixtures_dir/../../plan-gate.sh"
libfile="$fixtures_dir/../../../../../skills/workflow-profile/scripts/resolve-profile.sh"
export AGENTS_WORKFLOW_RESOLVER="$libfile"
# the seed tier files, never the live ~/.agents/workflow-models
export AGENTS_WORKFLOW_MODELS="$fixtures_dir/../../../../../workflow-models"
. "$fixtures_dir/../tiers.sh"

overall=0
root=$(mktemp -d "${TMPDIR:-/tmp}/pg.XXXXXX")
log_dir=$(mktemp -d "${TMPDIR:-/tmp}/hooklog.XXXXXX")
export AGENTS_HOOK_LOG="$log_dir/hook-events.log"
trap 'rm -rf "$root" "$log_dir" 2>/dev/null' EXIT

pass() { printf 'PASS %s\n' "$1"; }
fail_case() { printf 'FAIL %s: %s\n' "$1" "$2"; overall=1; }

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

HOOK_OUT=""
HOOK_RC=0
run_hook() {  # <dir> <fixture-file> <profiles-dir>
  local dir="$1" fixture="$2" prof="$3"
  HOOK_OUT=$(cd "$dir" && AGENTS_WORKFLOW_PROFILES="$prof" bash "$hook" < <(fill_exec < "$fixture") 2>/dev/null)
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

valid_plan=$(fill_exec < "$fixtures_dir/plans/valid.md")

# plan_copy <plan-text> -> path of a temp copy whose Execute line names that same path
plan_copy() {
  local dir
  dir=$(new_root)
  printf '%s\n' "$1" | sed -e "s|Execute the plan at [^\"]*|Execute the plan at $dir/widget-import.md|g" -e "s|/execute-plan [^\"]*|/execute-plan $dir/widget-import.md|g" > "$dir/widget-import.md"
  printf '%s' "$dir/widget-import.md"
}

# edit_plan <sed-args...> -> valid.md with one rule broken (or one harmless change made)
edit_plan() { printf '%s\n' "$valid_plan" | sed "$@"; }

# check_plan <case> <plan-text> <deny|allow> <substring of the reason or context, or ""> [rule]
# [planFilePath]. The rule, when given, must appear in the hook log as a deny or an advise.
# KEEP_COUNTERS=1 keeps the session's counters, for the budget case.
check_plan() {
  local name="$1" plan="$2" want="$3" needle="$4" want_rule="${5:-}" pf="${6:-}" json decision text err=""
  [ "${KEEP_COUNTERS:-}" = 1 ] || rm -f "${TMPDIR:-/tmp}/claude-plan-gate-case-$name" 2>/dev/null
  repo=$(make_repo "repo" "https://github.com/acme/widgets.git")
  prof=$(copy_profiles "$fixtures_dir/profiles-resolved")
  json=$(jq -nc --arg sid "case-$name" --arg plan "$plan" --arg pf "$pf" \
    '{session_id:$sid,hook_event_name:"PreToolUse",tool_name:"ExitPlanMode",tool_input:({plan:$plan} + (if $pf == "" then {} else {planFilePath:$pf} end))}')
  : > "$AGENTS_HOOK_LOG"
  run_hook_json "$repo" "$json" "$prof"
  decision=$(decision_of "$HOOK_OUT")
  [ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
  if [ "$want" = "deny" ]; then
    [ "$decision" = "deny" ] || err="${err:+$err; }expected deny, got: $HOOK_OUT"
    text=$(reason_of "$HOOK_OUT")
  else
    [ -z "$decision" ] || err="${err:+$err; }expected no deny, got: $HOOK_OUT"
    text=$(ctx_of "$HOOK_OUT")
  fi
  [ -z "$needle" ] || contains "$text" "$needle" || err="${err:+$err; }expected '$needle' in: $text"
  [ -z "$want_rule" ] || grep -qE " (deny|advise) $want_rule\$" "$AGENTS_HOOK_LOG" 2>/dev/null \
    || err="${err:+$err; }rule '$want_rule' not logged: $(cat "$AGENTS_HOOK_LOG" 2>/dev/null)"
  [ "${KEEP_COUNTERS:-}" = 1 ] || rm -f "${TMPDIR:-/tmp}/claude-plan-gate-case-$name" 2>/dev/null
  if [ -z "$err" ]; then pass "$name"; else fail_case "$name" "$err"; fi
}

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

# --- missing Run heading -> deny (resolved profile) ---------------------------
case_name="missing-run-denies"
rm -f "${TMPDIR:-/tmp}/claude-plan-gate-case-missing-run" 2>/dev/null
repo=$(make_repo "repo" "https://github.com/acme/widgets.git")
prof=$(copy_profiles "$fixtures_dir/profiles-resolved")
run_hook "$repo" "$fixtures_dir/missing-run.json" "$prof"
decision=$(decision_of "$HOOK_OUT")
reason=$(reason_of "$HOOK_OUT")
err=""
[ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
[ "$decision" = "deny" ] || err="${err:+$err; }expected permissionDecision=deny, got: $HOOK_OUT"
contains "$reason" "'Run'" || err="${err:+$err; }reason doesn't name Run: $reason"
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

# --- TBD in Run -> deny (resolved profile) ------------------------------------
case_name="tbd-run-denies"
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
pf=$(plan_copy "$valid_plan")
json=$(jq -nc --arg pf "$pf" \
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
case_name="not-in-plan-mode-denies"
repo=$(make_repo "repo" "https://github.com/acme/widgets.git")
prof=$(copy_profiles "$fixtures_dir/profiles-resolved")
: > "$AGENTS_HOOK_LOG"
run_hook_json "$repo" "$(jq -c '. + {permission_mode:"default"}' "$fixtures_dir/valid.json")" "$prof"
err=""
[ "$(decision_of "$HOOK_OUT")" = "deny" ] || err="expected deny, got: $HOOK_OUT"
contains "$(reason_of "$HOOK_OUT")" "EnterPlanMode" || err="${err:+$err; }no EnterPlanMode order"
run_hook_json "$repo" "$(jq -c '. + {permission_mode:"plan"}' "$fixtures_dir/valid.json")" "$prof"
contains "$(reason_of "$HOOK_OUT")" "not in plan mode" && err="${err:+$err; }plan mode denied as not in plan mode"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

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

# --- file layout: the Briefs pointer and brief files beside the plan ---------------------------
# pointer_dir <brief id>... -> dir holding widget-import.md (pointer layout) and widget-import.briefs/<id>.md
pointer_dir() {
  local dir id
  [ "$#" -gt 0 ] || set -- S0 S1 S3
  dir=$(new_root)
  mkdir "$dir/widget-import.briefs"
  { printf '%s\n' "$valid_plan" | sed -e "s|/Users/example/.claude/plans/widget-import.md|$dir/widget-import.md|g" -e '/^## Briefs$/,$d'
    printf '## Briefs\n\nBriefs: %s/widget-import.briefs/, one file per delegated row.\n' "$dir"; } > "$dir/widget-import.md"
  for id in "$@"; do printf 'Brief %s\n' "$id" > "$dir/widget-import.briefs/$id.md"; done
  printf '%s' "$dir"
}

pf_dir=$(pointer_dir)
check_plan "pointer-layout-allows" "$(cat "$pf_dir/widget-import.md")" allow "" "" "$pf_dir/widget-import.md"
pf_dir=$(pointer_dir S0 S1)
check_plan "pointer-brief-missing-denies" "$(cat "$pf_dir/widget-import.md")" deny \
  "Steps row S3 is delegated, but its brief file $pf_dir/widget-import.briefs/S3.md is missing or empty." brief "$pf_dir/widget-import.md"
pf_dir=$(pointer_dir)
: > "$pf_dir/widget-import.briefs/S3.md"
check_plan "pointer-brief-empty-denies" "$(cat "$pf_dir/widget-import.md")" deny \
  "Steps row S3 is delegated, but its brief file $pf_dir/widget-import.briefs/S3.md is missing or empty." brief "$pf_dir/widget-import.md"
pf_dir=$(pointer_dir)
seq 26 > "$pf_dir/widget-import.briefs/S3.md"
check_plan "pointer-brief-over-25-advises" "$(cat "$pf_dir/widget-import.md")" allow \
  "plan-gate: brief file $pf_dir/widget-import.briefs/S3.md has 26 lines" brief "$pf_dir/widget-import.md"
check_plan "pointer-without-planfile-allows" "$(cat "$pf_dir/widget-import.md")" allow "" ""
check_plan "done-when-text-denies" "$(edit_plan "s/| \`yarn test\` |/| yarn test |/")" deny \
  "Steps row S1 has a Done when that is not one backticked command." done-when

# --- one rule at a time, each from valid.md --------------------------------------------------

check_plan "bad-tier-denies" "$(edit_plan "s/^\(| ➖ | S1 .*\)| ${TIER_B} |/\1| orchestration |/")" \
  deny "Steps row S1 has tier 'orchestration'" tier
check_plan "delegated-row-without-brief-denies" "$(edit_plan '/^### S3 /d')" \
  deny "Steps row S3 is delegated, but Briefs has no '### S3'." brief
check_plan "plan-running-row-without-brief-allows" "$(edit_plan -e "s/^\(| ➖ | S1 .*\)| ${TIER_B} |/\1| $RUN_TIER |/" -e '/^### S1 /d')" \
  allow "" ""
check_plan "s10-brief-does-not-cover-s1" "$(edit_plan 's/^### S1 /### S10 /')" \
  deny "Steps row S1 is delegated" brief
check_plan "empty-steps-table-denies" "$(edit_plan '/^| ➖ | S[0-9] /d')" \
  deny "the Steps section has no table" steps
check_plan "malformed-steps-row-denies" "$(edit_plan 's/^| ➖ | S1 | Keep empty rows |/| ➖ | S1 |/')" \
  deny "the Steps section has no table" steps
check_plan "steps-header-changed-denies" "$(edit_plan 's/^| State | # | Task | Tier |/| State | # | Tier |/')" \
  deny "the Steps section has no table" steps
check_plan "bad-state-denies" "$(edit_plan 's/^| ➖ | S1 /| [done] | S1 /')" \
  deny "the Steps section has no table" steps
check_plan "in-progress-and-done-states-allow" "$(edit_plan -e 's/^| ➖ | S0 /| ✅ | S0 /' -e 's/^| ➖ | S1 /| ▶️ | S1 /')" \
  allow "" ""
check_plan "missing-approval-row-denies" "$(edit_plan '/^| ➖ | S4 | Approval/d')" \
  deny "Steps must end with the Review, Gates, Approval and Hand-off rows" closing
check_plan "gates-before-review-denies" "$(edit_plan -e 's/^| ➖ | S2 | Review: /| ➖ | S2 | GATESWAP /' -e 's/^| ➖ | S3 | Gates: /| ➖ | S3 | Review: /' -e 's/^| ➖ | S2 | GATESWAP /| ➖ | S2 | Gates: /')" \
  deny "Steps must end with the Review, Gates, Approval and Hand-off rows" closing
check_plan "review-row-without-count-denies" "$(edit_plan "s/${TIER_A} tier × 1/${TIER_A} tier/")" \
  deny "Steps must end with the Review, Gates, Approval and Hand-off rows" closing
check_plan "review-row-ascii-x-allows" "$(edit_plan "s/${TIER_A} tier × 1/${TIER_A} tier x 1/")" \
  allow "" ""
check_plan "no-fence-denies" "$(edit_plan '/^```$/d')" \
  deny "the Run section has no fenced block" fence
check_plan "no-agent-line-denies" "$(edit_plan '/^claude --agent /d')" \
  deny "the Run section has no fenced block" fence
check_plan "wrong-agent-denies" "$(edit_plan "s/--agent $RUN_TIER/--agent $NONDELEGABLE_TIER/")" \
  deny "the Run fence names agent '$NONDELEGABLE_TIER'; the line must be: claude --agent $RUN_TIER" run
check_plan "claude-fence-extra-line-denies" "$(edit_plan '/^claude --agent /i\
extra line
')" deny "the Run section has no fenced block" fence
check_plan "missing-run-rules-line-denies" "$(edit_plan '/^Run rules: /d')" \
  deny "names no absolute path to execute-plan/references/run-rules.md" run
check_plan "relative-run-rules-path-denies" "$(edit_plan "s|\`/Users/example/.agents/skills/execute-plan/references/run-rules.md\`|\`references/run-rules.md\`|")" \
  deny "names no absolute path to execute-plan/references/run-rules.md" run
check_plan "old-write-plan-run-rules-path-denies" "$(edit_plan 's|/execute-plan/references/run-rules.md|/write-plan/references/run-rules.md|')" \
  deny "names no absolute path to execute-plan/references/run-rules.md" run
check_plan "heading-inside-fence-ignored" "$(edit_plan '/^The importer drops/i\
```\
## Steps\
### S1 quoted\
```\
')" allow "" ""
check_plan "nested-fence-heading-ignored" "$(edit_plan '/^- Keep the empty row/a\
````\
```\
## Steps\
```\
````\
')" allow "" ""
check_plan "tilde-fence-heading-ignored" "$(edit_plan '/^- Keep the empty row/a\
~~~\
## Steps\
```\
## Run\
~~~\
')" allow "" ""
check_plan "run-fence-after-nested-block-allows" "$(edit_plan '/^Session tier: /a\
````markdown\
```\
claude --agent '"$NONDELEGABLE_TIER"' "Execute the plan at /elsewhere/plan.md"\
```\
````\
')" allow "" ""
check_plan "run-fence-after-quoted-opener-allows" "$(edit_plan '/^Session tier: /a\
````\
```\
````\
')" allow "" ""
check_plan "brief-inside-fence-does-not-count" "$(edit_plan -e 's/^### S3 Gates$/```\
### S3 Gates\
```/')" deny "Steps row S3 is delegated" brief
missing_link="/nonexistent-$$/plans/widget-import-spec.md"
check_plan "missing-link-advisory-only" "$(edit_plan "s|^The importer drops|See [the spec]($missing_link#L3) and [the plan]($fixtures_dir/plans/valid.md). The importer drops|")" \
  allow "plan-gate: the plan links a file that does not exist: $missing_link." link
case_name="existing-link-not-reported"
if contains "$(ctx_of "$HOOK_OUT")" "valid.md"; then fail_case "$case_name" "an existing link was reported: $HOOK_OUT"; else pass "$case_name"; fi

# --- planFilePath: the Execute line must name it -----------------------------------------------
pf=$(plan_copy "$valid_plan")
check_plan "fence-path-matches-planfilepath-allows" "$(cat "$pf")" allow "" "" "$pf"
check_plan "fence-path-differs-from-planfilepath-denies" "$valid_plan" \
  deny "the Run section has no fenced block" fence "$pf"

# --- the Codex fence: one launch line, its model from codex.md ---------------------------------
codex_plan=$(edit_plan -e "s|^claude --agent $RUN_TIER \"/execute-plan \(.*\)\"\$|codex -m $RUN_CODEX_MODEL -c model_reasoning_effort=$RUN_CODEX_EFFORT \"Execute the plan at \1\"|")
check_plan "codex-fence-allows" "$codex_plan" allow "" ""
check_plan "codex-fence-unlisted-model-denies" "$(printf '%s\n' "$codex_plan" | sed "s/-m $RUN_CODEX_MODEL/-m $RUN_MODEL/")" \
  deny "names no model from ~/.agents/workflow-models/codex.md" run
check_plan "codex-fence-extra-line-denies" "$(printf '%s\n' "$codex_plan" | sed '/^codex -m /i\
extra line
')" deny "the Run section has no fenced block" fence
check_plan "codex-fence-path-matches-planfilepath-allows" \
  "$(printf '%s\n' "$codex_plan" | sed "s|at /Users/example/.claude/plans/widget-import.md|at $pf|")" allow "" "" "$pf"
check_plan "codex-fence-path-differs-from-planfilepath-denies" "$codex_plan" \
  deny "the Run section has no fenced block" fence "$pf"

# --- the Codex fence's model and effort must equal the exec row of codex.md
check_plan "plan-running-pair-allows" "$valid_plan" allow "" ""
check_plan "codex-plan-running-pair-case-insensitive-allows" \
  "$(printf '%s\n' "$codex_plan" | sed "s/effort=$RUN_CODEX_EFFORT/effort=$(printf '%s' "$RUN_CODEX_EFFORT" | tr '[:lower:]' '[:upper:]')/")" allow "" ""
check_plan "codex-wrong-effort-denies" \
  "$(printf '%s\n' "$codex_plan" | sed "s/effort=$RUN_CODEX_EFFORT/effort=$RUN_CODEX_OTHER_EFFORT/")" \
  deny "the Run section must name the $RUN_TIER row of codex.md: $RUN_CODEX_MODEL at $RUN_CODEX_EFFORT effort" run

# --- the model list comes from the workflow-models dir: a name only its claude.md knows allows; with
# no tiers.md, or one without a Kind column, the tier checks cannot run and the plan denies ---------
case_name="models-dir-feeds-run"
repo=$(make_repo "repo" "https://github.com/acme/widgets.git")
prof=$(copy_profiles "$fixtures_dir/profiles-resolved")
models=$(new_root)
printf '| Tier | Model | Effort |\n| --- | --- | --- |\n| %s | Zephyr | none |\n| %s | Zephyr | low |\n| %s | Zephyr | medium |\n| %s | Zephyr | high |\n| %s | Zephyr | high |\n' "$TIER_FIRST" "$TIER_A" "$TIER_B" "$TIER_LAST" "$RUN_TIER" > "$models/claude.md"
cp "$AGENTS_WORKFLOW_MODELS/tiers.md" "$models/tiers.md"
nokind=$(new_root)
cp "$models/claude.md" "$nokind/claude.md"
awk -F'|' '/^\|/ { print "|" $2 "|" $3 "|"; next } { print }' "$AGENTS_WORKFLOW_MODELS/tiers.md" > "$nokind/tiers.md"
zephyr=$valid_plan
err=""
for mode in dir no-models no-kind; do
  rm -f "${TMPDIR:-/tmp}/claude-plan-gate-case-models-$mode" 2>/dev/null
  case "$mode" in
    dir) plan=$zephyr dir=$models want=allow ;;
    no-models) plan=$zephyr dir="$root/no-models" want=deny ;;
    no-kind) plan=$zephyr dir=$nokind want=deny ;;
  esac
  json=$(jq -nc --arg sid "case-models-$mode" --arg plan "$plan" \
    '{session_id:$sid,hook_event_name:"PreToolUse",tool_name:"ExitPlanMode",tool_input:{plan:$plan}}')
  HOOK_OUT=$(cd "$repo" && printf '%s' "$json" | AGENTS_WORKFLOW_MODELS="$dir" AGENTS_WORKFLOW_PROFILES="$prof" bash "$hook" 2>/dev/null)
  decision=$(printf '%s' "$HOOK_OUT" | jq -r '.hookSpecificOutput.permissionDecision // empty' 2>/dev/null)
  got=allow; [ "$decision" = "deny" ] && got=deny
  [ "$got" = "$want" ] || err="${err:+$err; }$mode: want $want, got $got ($HOOK_OUT)"
  rm -f "${TMPDIR:-/tmp}/claude-plan-gate-case-models-$mode" 2>/dev/null
done
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

exit $overall
