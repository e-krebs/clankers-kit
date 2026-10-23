#!/usr/bin/env bash
# Runs every plan-followthrough-codex case and asserts on its output; exits non-zero on any failure.

set -u

fixtures_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
hook="$fixtures_dir/../../plan-followthrough-codex.sh"
AGENTS_HOOKS_LIB="$fixtures_dir/../../../../../hooks/lib"
AGENTS_WORKFLOW_MODELS="$fixtures_dir/../../../../../workflow-models"
export AGENTS_HOOKS_LIB AGENTS_WORKFLOW_MODELS
. "$fixtures_dir/../tiers.sh"

overall=0
tmp=$(mktemp -d "${TMPDIR:-/tmp}/pftc.XXXXXX")
export TMPDIR="$tmp" AGENTS_HOOK_LOG="$tmp/hook-events.log"
# filled copies of the plans: the hook reads them by path
plans_dir="$tmp/fixture-plans"
mkdir -p "$plans_dir"
# shellcheck disable=SC2094
for f in "$fixtures_dir"/plans/*.md; do fill_exec < "$f" > "$plans_dir/$(basename "$f")"; done
# never the live ~/.codex; its plans/ dir starts missing, as on a fresh Codex install
export CODEX_HOME="$tmp/codex-home"
trap 'rm -rf "$tmp" 2>/dev/null' EXIT

pass() { printf 'PASS %s\n' "$1"; }
fail_case() { printf 'FAIL %s: %s\n' "$1" "$2"; overall=1; }

SID=case-sid
marker="$tmp/codex-plan-latest-$SID"
APPROVAL="Implement the plan."
CODEX_FENCE="codex -m $RUN_CODEX_MODEL -c model_reasoning_effort=$RUN_CODEX_EFFORT \"Execute the plan at /Users/e/.codex/plans/demo.md\""

HOOK_OUT="" HOOK_RC=0
# run_prompt <prompt> [extra jq object merged into the payload]
run_prompt() {
  local extra='{}'
  [ -z "${2:-}" ] || extra=$2
  HOOK_OUT=$(jq -nc --arg p "$1" --arg s "$SID" --argjson x "$extra" \
    '{session_id:$s, hook_event_name:"UserPromptSubmit", permission_mode:"default", prompt:$p} + $x' \
    | bash "$hook" 2>/dev/null)
  HOOK_RC=$?
}
set_marker() { printf '%s\n' "$plans_dir/$1" > "$marker"; }

expect_silent() {
  local err=""
  [ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
  [ -z "$HOOK_OUT" ] || err="${err:+$err; }expected no output, got: $HOOK_OUT"
  if [ -z "$err" ]; then pass "$1"; else fail_case "$1" "$err"; fi
}

# expect_block <case> <fence text> — asserts the exact block JSON and that the marker is gone.
expect_block() {
  local err="" decision reason
  [ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
  decision=$(printf '%s' "$HOOK_OUT" | jq -r '.decision // empty' 2>/dev/null)
  reason=$(printf '%s' "$HOOK_OUT" | jq -r '.reason // empty' 2>/dev/null)
  [ "$decision" = "block" ] || err="${err:+$err; }decision is '$decision'"
  [ "$reason" = "Plan approved. Open a new terminal and run:
$2" ] || err="${err:+$err; }reason mismatch: $reason"
  [ ! -e "$marker" ] || err="${err:+$err; }marker not removed"
  if [ -z "$err" ]; then pass "$1"; else fail_case "$1" "$err"; fi
}

if bash -n "$hook" 2>/dev/null; then pass "syntax:hook"; else fail_case "syntax:hook" "bash -n failed"; fi
if bash -n "$fixtures_dir/../../lib/plan-run-fence.sh" 2>/dev/null; then pass "syntax:fence-lib"
else fail_case "syntax:fence-lib" "bash -n failed"; fi

# both picker choices send the same bare prompt, so the marker covers both
set_marker codex-form.md
run_prompt "$APPROVAL"
expect_block "marker-codex-form" "$CODEX_FENCE"

set_marker codex-form.md
run_prompt "  $APPROVAL
"
expect_block "marker-codex-form-padded" "$CODEX_FENCE"

run_prompt "$APPROVAL
<proposed_plan>
$(cat "$plans_dir/codex-form.md")
</proposed_plan>"
expect_block "embedded-codex-form" "$CODEX_FENCE"

set_marker claude-form.md
run_prompt "$APPROVAL"
expect_block "marker-claude-form-launch-line" "claude --agent $RUN_TIER \"/execute-plan /Users/e/.claude/plans/demo.md\"
codex -m $RUN_CODEX_MODEL -c model_reasoning_effort=$RUN_CODEX_EFFORT \"Execute the plan at /Users/e/.claude/plans/demo.md\""

rm -f "$marker"
run_prompt "$APPROVAL"
expect_silent "no-marker-silent"

set_marker codex-form.md
run_prompt "$APPROVAL
<proposed_plan>
$(cat "$plans_dir/codex-form.md")
</proposed_plan>
<proposed_plan>
$(cat "$plans_dir/no-run.md")
</proposed_plan>"
expect_silent "embedded-plain-after-write-plan-silent"
if [ ! -e "$marker" ]; then pass "embedded-plain-clears-marker"; else fail_case "embedded-plain-clears-marker" "marker kept"; fi

set_marker no-run.md
run_prompt "$APPROVAL"
expect_silent "no-run-fence-silent"

set_marker codex-form.md
run_prompt "Can you explain the plan?"
expect_silent "unrelated-prompt-silent"
if [ -e "$marker" ]; then pass "unrelated-keeps-marker"; else fail_case "unrelated-keeps-marker" "marker removed"; fi

# Plan mode cannot write, so a plan whose path sits under $CODEX_HOME/plans/ is saved on approval
unsaved="$CODEX_HOME/plans/demo.md"
UNSAVED_FENCE="codex -m $RUN_CODEX_MODEL -c model_reasoning_effort=$RUN_CODEX_EFFORT \"Execute the plan at $unsaved\""
unsaved_plan=$(sed "s|/Users/e/.codex/plans/demo.md|$unsaved|" "$plans_dir/codex-form.md")
# transcript <final text>... -> a rollout with one assistant row per argument
transcript() {
  local t x
  t=$(mktemp "$tmp/rollout.XXXXXX")
  for x in "$@"; do
    jq -nc --arg x "$x" '{type:"response_item",payload:{type:"message",role:"assistant",
      content:[{type:"output_text",text:$x}],phase:"final_answer"}}' >> "$t"
  done
  printf '%s' "$t"
}
tp_of() { jq -nc --arg t "$1" '{transcript_path:$t}'; }

printf '%s\n' "$unsaved" > "$marker"
run_prompt "$APPROVAL" "$(tp_of "$(transcript "Draft:
<proposed_plan>
$(printf '%s\n' "$unsaved_plan" | sed 's/Do it/Old draft/')
</proposed_plan>" "<proposed_plan>
$unsaved_plan
</proposed_plan>")")"
expect_block "transcript-plan-saved-on-approval" "$UNSAVED_FENCE"
if [ "$(cat "$unsaved" 2>/dev/null)" = "$unsaved_plan" ]; then pass "saved-file-holds-latest-block"
else fail_case "saved-file-holds-latest-block" "file: $(cat "$unsaved" 2>/dev/null)"; fi

rm -rf "$CODEX_HOME"
printf '%s\n' "$unsaved" > "$marker"
run_prompt "$APPROVAL" "$(tp_of "$(transcript "<proposed_plan>
$(sed "s|/Users/e/.codex/plans/demo.md|$CODEX_HOME/plans/other.md|" "$plans_dir/codex-form.md")
</proposed_plan>")")"
expect_silent "transcript-other-path-silent"
if [ ! -e "$CODEX_HOME" ]; then pass "other-path-saves-nothing"; else fail_case "other-path-saves-nothing" "wrote under $CODEX_HOME"; fi

printf '%s\n' "$unsaved" > "$marker"
run_prompt "$APPROVAL" "$(tp_of "$tmp/missing.jsonl")"
expect_silent "unsaved-no-transcript-silent"

rm -rf "$CODEX_HOME"
run_prompt "$APPROVAL
<proposed_plan>
$unsaved_plan
</proposed_plan>"
expect_block "embedded-plan-saved-on-approval" "$UNSAVED_FENCE"
if [ "$(cat "$unsaved" 2>/dev/null)" = "$unsaved_plan" ]; then pass "embedded-saved-file"
else fail_case "embedded-saved-file" "file: $(cat "$unsaved" 2>/dev/null)"; fi

run_prompt "$APPROVAL" '{"agent_id":"child-1"}'
expect_silent "agent-id-silent"

run_prompt "<task-notification>$APPROVAL</task-notification>"
expect_silent "notification-silent"

HOOK_OUT=$(printf 'not json {' | bash "$hook" 2>/dev/null); HOOK_RC=$?
expect_silent "malformed-silent"

exit $overall
