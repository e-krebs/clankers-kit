#!/usr/bin/env bash
# Runs every plan-check case and asserts on the checker's stdout lines and exit code; exits
# non-zero on any failure. Reuses plan-gate's plans and profiles, and runs each case from outside
# the sandbox repo so a pass proves --cwd is honoured.

set -u

fixtures_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
gate_fixtures="$fixtures_dir/../plan-gate"
checker="$fixtures_dir/../../lib/plan-check.sh"
export AGENTS_WORKFLOW_RESOLVER="$fixtures_dir/../../../../../skills/workflow-profile/scripts/resolve-profile.sh"
# the seed tier files, never the live ~/.agents/workflow-models
export AGENTS_WORKFLOW_MODELS="$fixtures_dir/../../../../../workflow-models"
. "$fixtures_dir/../tiers.sh"

overall=0
root=$(mktemp -d "${TMPDIR:-/tmp}/pc.XXXXXX")
trap 'rm -rf "$root" 2>/dev/null' EXIT

pass() { printf 'PASS %s\n' "$1"; }
fail_case() { printf 'FAIL %s: %s\n' "$1" "$2"; overall=1; }

new_root() { mktemp -d "$root/root.XXXXXX"; }

repo=$(new_root)/repo
mkdir -p "$repo"
( cd "$repo" && git init -q && git remote add origin https://github.com/acme/widgets.git ) >/dev/null 2>&1
resolved_profiles="$gate_fixtures/profiles-resolved"
empty_profiles=$(new_root)

valid_plan=$(fill_exec < "$gate_fixtures/plans/valid.md")
edit_plan() { printf '%s\n' "$valid_plan" | sed "$@"; }

OUT="" RC=0
# run_check <plan-text> <profiles-dir> [plan-file-path]
run_check() {
  local file
  file="$(new_root)/plan.md"
  printf '%s\n' "$1" > "$file"
  OUT=$(cd "$root" && AGENTS_WORKFLOW_PROFILES="$2" bash "$checker" --plan "$file" --plan-file-path "${3:-}" --cwd "$repo" 2>/dev/null)
  RC=$?
}

# expect <case> <exit code> <line prefix, tab-separated, or "" for no output> [line count]
expect() {
  local name="$1" rc="$2" prefix="$3" count="${4:-1}" err="" n
  [ "$RC" -eq "$rc" ] || err="exit $RC, want $rc"
  if [ -z "$prefix" ]; then
    [ -z "$OUT" ] || err="${err:+$err; }expected no output, got: $OUT"
  else
    n=$(printf '%s\n' "$OUT" | grep -c .)
    [ "$n" -eq "$count" ] || err="${err:+$err; }expected $count line(s), got $n: $OUT"
    case "$OUT" in "$prefix"*) ;; *) err="${err:+$err; }expected a line starting '$prefix', got: $OUT" ;; esac
  fi
  if [ -z "$err" ]; then pass "$name"; else fail_case "$name" "$err"; fi
}

T=$'\t'

if bash -n "$checker" 2>/dev/null; then pass "syntax:checker"; else fail_case "syntax:checker" "bash -n failed"; fi

# --- pass -----------------------------------------------------------------------------------
run_check "$valid_plan" "$resolved_profiles"
err=""
[ "$RC" -eq 0 ] || err="exit $RC"
printf '%s\n' "$OUT" | grep -vE "^(advise${T}(link|style)${T}|$)" | grep -q . && err="${err:+$err; }unexpected line: $OUT"
if [ -z "$err" ]; then pass "valid-plan-passes"; else fail_case "valid-plan-passes" "$err"; fi

# --- one deny per rule, first failure wins ------------------------------------------------------
run_check "$(edit_plan '/^## Run$/d')" "$resolved_profiles"
expect "heading-denies" 1 "deny${T}heading${T}plan-gate: heading #4"
run_check "$(edit_plan '/^| ➖ | S[0-9] /d')" "$resolved_profiles"
expect "steps-denies" 1 "deny${T}steps${T}plan-gate: the Steps section has no table"
run_check "$(edit_plan '/^| ➖ | S4 | Approval/d')" "$resolved_profiles"
expect "closing-denies" 1 "deny${T}closing${T}plan-gate: Steps must end"
run_check "$(edit_plan "s/^\(| ➖ | S1 .*\)| ${TIER_B} |/\1| orchestration |/")" "$resolved_profiles"
expect "tier-denies" 1 "deny${T}tier${T}plan-gate: Steps row S1 has tier 'orchestration'"
run_check "$(edit_plan '/^### S3 /d')" "$resolved_profiles"
expect "brief-denies" 1 "deny${T}brief${T}plan-gate: Steps row S3 is delegated"
run_check "$(edit_plan '/^claude --agent /d')" "$resolved_profiles"
expect "fence-denies" 1 "deny${T}fence${T}plan-gate: the Run section has no fenced block"
run_check "$(edit_plan "s/--agent $RUN_TIER/--agent $NONDELEGABLE_TIER/")" "$resolved_profiles" "/Users/example/.claude/plans/widget-import.md"
expect "run-wrong-agent-denies" 1 "deny${T}run${T}plan-gate: the Run fence names agent '$NONDELEGABLE_TIER'; the line must be: claude --agent $RUN_TIER \"/execute-plan /Users/example/.claude/plans/widget-import.md\""
run_check "$valid_plan" "$resolved_profiles" "/Users/example/.claude/plans/widget-import.md"
err=""; [ "$RC" -eq 0 ] || err="exit $RC: $OUT"
if [ -z "$err" ]; then pass "run-right-line-allows"; else fail_case "run-right-line-allows" "$err"; fi
run_check "$valid_plan" "$resolved_profiles" "/elsewhere/plan.md"
expect "run-wrong-path-denies" 1 "deny${T}fence${T}"
run_check "$(edit_plan 's/^Session tier: /Session tier (TBD): /')" "$resolved_profiles"
expect "run-placeholder-denies" 1 "deny${T}run${T}plan-gate: the Run section still holds a placeholder"
run_check "$(edit_plan '/^Run rules: /d')" "$resolved_profiles"
expect "run-run-rules-denies" 1 "deny${T}run${T}plan-gate: the Run section names no absolute path to execute-plan/references/run-rules.md."
run_check "$(edit_plan "s/^- claude, ${TIER_A} tier subagent: /- one reviewer: /")" "$resolved_profiles"
expect "review-denies" 1 "deny${T}review${T}plan-gate: the Plan review section names no reviewing agent."

# --- the profile policy -----------------------------------------------------------------------
run_check "$(edit_plan '/^claude --agent /d')" "$empty_profiles"
expect "unresolved-profile-advises" 0 "advise${T}unresolved-profile:fence${T}plan-gate: the Run section has no fenced block"

# --- the Codex fence --------------------------------------------------------------------------
codex_plan=$(edit_plan \
  -e "s|^claude --agent $RUN_TIER \"/execute-plan \(.*\)\"\$|codex -m $RUN_CODEX_MODEL -c model_reasoning_effort=$RUN_CODEX_EFFORT \"Execute the plan at \1\"|")
run_check "$codex_plan" "$resolved_profiles" "/Users/example/.claude/plans/widget-import.md"
err=""
[ "$RC" -eq 0 ] || err="exit $RC: $OUT"
if [ -z "$err" ]; then pass "codex-fence-passes"; else fail_case "codex-fence-passes" "$err"; fi
run_check "$(printf '%s\n' "$codex_plan" | sed "s/-m $RUN_CODEX_MODEL/-m $RUN_MODEL/")" "$resolved_profiles"
expect "codex-fence-unlisted-model-denies" 1 "deny${T}run${T}plan-gate: the Run section names no model from ~/.agents/workflow-models/codex.md."
run_check "$(printf '%s\n' "$codex_plan" | sed "s/effort=$RUN_CODEX_EFFORT/effort=$RUN_CODEX_OTHER_EFFORT/")" "$resolved_profiles"
expect "codex-wrong-effort-denies" 1 "deny${T}run${T}plan-gate: the Run section must name the $RUN_TIER row of codex.md: $RUN_CODEX_MODEL at $RUN_CODEX_EFFORT effort, not $RUN_CODEX_MODEL at $RUN_CODEX_OTHER_EFFORT."
run_check "$codex_plan" "$resolved_profiles" "/elsewhere/plan.md"
expect "codex-fence-path-differs-denies" 1 "deny${T}fence${T}"

# --- pass-path advisories ---------------------------------------------------------------------
missing_link="/nonexistent-$$/plans/widget-import-spec.md"
run_check "$(edit_plan "s|^The importer drops|See [the spec]($missing_link#L3). The importer drops|")" "$resolved_profiles"
err=""
[ "$RC" -eq 0 ] || err="exit $RC"
printf '%s\n' "$OUT" | grep -qxF "advise${T}link${T}plan-gate: the plan links a file that does not exist: $missing_link." \
  || err="${err:+$err; }no link advise line: $OUT"
if [ -z "$err" ]; then pass "missing-link-advises"; else fail_case "missing-link-advises" "$err"; fi

# --- Done when: one backticked command, Approval and Hand-off exempt ----------------------------
run_check "$(edit_plan "s/| \`yarn test\` |/| yarn test |/")" "$resolved_profiles"
expect "done-when-text-denies" 1 "deny${T}done-when${T}plan-gate: Steps row S1 has a Done when that is not one backticked command."
run_check "$(edit_plan "s/| \`yarn test\` |/| \`yarn test\` and \`yarn lint\` |/")" "$resolved_profiles"
expect "done-when-two-spans-denies" 1 "deny${T}done-when${T}"
run_check "$valid_plan" "$resolved_profiles"
err=""
[ "$RC" -eq 0 ] || err="exit $RC"
printf '%s\n' "$OUT" | grep -q "^deny" && err="${err:+$err; }unexpected deny: $OUT"
if [ -z "$err" ]; then pass "exempt-rows-hold-text-allows"; else fail_case "exempt-rows-hold-text-allows" "$err"; fi

# --- file layout: a pointer line under Briefs, brief files beside the plan -----------------------
# pointer_dir <brief id>... -> a dir holding widget-import.md (pointer layout, Run path under the dir)
# and widget-import.briefs/<id>.md for each id
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
run_check "$(cat "$pf_dir/widget-import.md")" "$resolved_profiles" "$pf_dir/widget-import.md"
err=""
[ "$RC" -eq 0 ] || err="exit $RC: $OUT"
printf '%s\n' "$OUT" | grep -q "^deny" && err="${err:+$err; }unexpected deny: $OUT"
if [ -z "$err" ]; then pass "pointer-briefs-present-passes"; else fail_case "pointer-briefs-present-passes" "$err"; fi

pf_dir=$(pointer_dir S0 S1)
run_check "$(cat "$pf_dir/widget-import.md")" "$resolved_profiles" "$pf_dir/widget-import.md"
expect "pointer-brief-missing-denies" 1 "deny${T}brief${T}plan-gate: Steps row S3 is delegated, but its brief file $pf_dir/widget-import.briefs/S3.md is missing or empty."

pf_dir=$(pointer_dir)
: > "$pf_dir/widget-import.briefs/S3.md"
run_check "$(cat "$pf_dir/widget-import.md")" "$resolved_profiles" "$pf_dir/widget-import.md"
expect "pointer-brief-empty-denies" 1 "deny${T}brief${T}plan-gate: Steps row S3 is delegated, but its brief file $pf_dir/widget-import.briefs/S3.md is missing or empty."

pf_dir=$(pointer_dir)
sed "s|widget-import.briefs/,|other.briefs/,|" "$pf_dir/widget-import.md" > "$pf_dir/widget-import.tmp" && mv "$pf_dir/widget-import.tmp" "$pf_dir/widget-import.md"
run_check "$(cat "$pf_dir/widget-import.md")" "$resolved_profiles" "$pf_dir/widget-import.md"
expect "pointer-dir-differs-denies" 1 "deny${T}brief${T}plan-gate: the Briefs pointer names $pf_dir/other.briefs; the brief files must sit at $pf_dir/widget-import.briefs."

pf_dir=$(pointer_dir)
seq 26 > "$pf_dir/widget-import.briefs/S3.md"
run_check "$(cat "$pf_dir/widget-import.md")" "$resolved_profiles" "$pf_dir/widget-import.md"
err=""
[ "$RC" -eq 0 ] || err="exit $RC"
printf '%s\n' "$OUT" | grep -qF "advise${T}brief${T}plan-gate: brief file $pf_dir/widget-import.briefs/S3.md has 26 lines; keep a brief to 25 lines or fewer." \
  || err="${err:+$err; }no brief advise line: $OUT"
if [ -z "$err" ]; then pass "brief-over-25-warns"; else fail_case "brief-over-25-warns" "$err"; fi

pf_dir=$(pointer_dir)
seq 25 > "$pf_dir/widget-import.briefs/S3.md"
run_check "$(cat "$pf_dir/widget-import.md")" "$resolved_profiles" "$pf_dir/widget-import.md"
if printf '%s\n' "$OUT" | grep -q "^advise${T}brief"; then fail_case "brief-at-25-silent" "warned: $OUT"; else pass "brief-at-25-silent"; fi

pf_dir=$(pointer_dir S0 S1)
run_check "$(cat "$pf_dir/widget-import.md")" "$resolved_profiles"
err=""
[ "$RC" -eq 0 ] || err="exit $RC"
printf '%s\n' "$OUT" | grep -q "^deny" && err="${err:+$err; }pointer-only check denied on a missing brief: $OUT"
if [ -z "$err" ]; then pass "pointer-without-planfile-checks-pointer-only"; else fail_case "pointer-without-planfile-checks-pointer-only" "$err"; fi

run_check "$(edit_plan '/^### S3 /d')" "$resolved_profiles" "$(new_root)/widget-import.md"
expect "uncovered-row-with-planfile-denies" 1 "deny${T}brief${T}plan-gate: Steps row S3 is delegated, but Briefs has no '### S3'."

# --- unreadable or empty plan -----------------------------------------------------------------
OUT=$(bash "$checker" --plan "$root/does-not-exist.md" 2>/dev/null); RC=$?
expect "missing-file-exits-2" 2 ""
: > "$root/empty.md"
OUT=$(bash "$checker" --plan "$root/empty.md" 2>/dev/null); RC=$?
expect "empty-file-exits-2" 2 ""
OUT=$(bash "$checker" 2>/dev/null); RC=$?
expect "no-plan-arg-exits-2" 2 ""

exit $overall
