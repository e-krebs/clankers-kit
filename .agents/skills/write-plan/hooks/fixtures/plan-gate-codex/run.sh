#!/usr/bin/env bash
# Runs every plan-gate-codex case and asserts on its output; exits non-zero on any failure.
# Payloads carry the Codex Stop fields (session_id, turn_id, transcript_path, cwd,
# stop_hook_active, last_assistant_message, agent_id for a child), and each transcript is built
# at run time in the shape of real-shape.jsonl, the trimmed rows of a real 0.154 Plan-mode turn.
# Plans come from ../plan-gate/plans, copied so each Execute line names its own copy. TMPDIR
# points at the sandbox, so the plan marker and the stall counter land there too.

set -u

fixtures_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
hook="$fixtures_dir/../../plan-gate-codex.sh"
plans="$fixtures_dir/../plan-gate/plans"
export AGENTS_WORKFLOW_RESOLVER="$fixtures_dir/../../../../../skills/workflow-profile/scripts/resolve-profile.sh"
# the seed tier files, never the live ~/.agents/workflow-models
export AGENTS_WORKFLOW_MODELS="$fixtures_dir/../../../../../workflow-models"
. "$fixtures_dir/../tiers.sh"

overall=0
root=$(mktemp -d "${TMPDIR:-/tmp}/pgc.XXXXXX")
export TMPDIR="$root/tmp"
mkdir -p "$TMPDIR"
export AGENTS_HOOK_LOG="$root/hook-events.log"
# never the live ~/.codex; its plans/ dir stays missing, as on a fresh Codex install
export CODEX_HOME="$root/codex-home"
trap 'rm -rf "$root" 2>/dev/null' EXIT

pass() { printf 'PASS %s\n' "$1"; }
fail_case() { printf 'FAIL %s: %s\n' "$1" "$2"; overall=1; }
contains() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }

repo="$root/repo"
mkdir -p "$repo"
( cd "$repo" && git init -q && git remote add origin https://github.com/acme/widgets.git ) >/dev/null 2>&1
export AGENTS_WORKFLOW_PROFILES="$fixtures_dir/../plan-gate/profiles-resolved"

# plan_file <plan-text> -> path of a copy whose Execute line names that same path
plan_file() {
  local p
  p="$(mktemp -d "$root/plan.XXXXXX")/plan.md"
  printf '%s\n' "$1" | sed -e "s|Execute the plan at /[^\"]*\.md|Execute the plan at $p|" -e "s|/execute-plan /[^\"]*\.md|/execute-plan $p|" > "$p"
  printf '%s' "$p"
}

# transcript <turn id> <final text> -> a rollout file: the user prompt, a commentary preamble and
# the final message, all in that turn
transcript() {
  local t
  t=$(mktemp "$root/rollout.XXXXXX")
  jq -nc --arg t "$1" '{type:"response_item",payload:{type:"message",role:"user",content:[{type:"input_text",text:"Plan the widget fix"}],internal_chat_message_metadata_passthrough:{turn_id:$t}}}' > "$t"
  jq -nc --arg t "$1" '{type:"response_item",payload:{type:"message",role:"assistant",content:[{type:"output_text",text:"I will read the importer first."}],phase:"commentary",internal_chat_message_metadata_passthrough:{turn_id:$t}}}' >> "$t"
  jq -nc --arg t "$1" --arg x "$2" '{type:"response_item",payload:{type:"message",role:"assistant",content:[{type:"output_text",text:$x}],phase:"final_answer",internal_chat_message_metadata_passthrough:{turn_id:$t}}}' >> "$t"
  printf '%s' "$t"
}

proposed() { printf '<proposed_plan>\n%s\n</proposed_plan>' "$(cat "$1")"; }

# payload <session> <transcript> <turn> [jq object merged last]
payload() {
  local x="${4:-}"
  [ -n "$x" ] || x='{}'
  jq -nc --arg s "$1" --arg tp "$2" --arg t "$3" --arg cwd "$repo" --arg cm "$RUN_CODEX_MODEL" --argjson x "$x" \
    '{session_id:$s,turn_id:$t,transcript_path:$tp,cwd:$cwd,hook_event_name:"Stop",model:$cm,
      permission_mode:"default",stop_hook_active:false,last_assistant_message:null} + $x'
}

HOOK_OUT="" HOOK_RC=0
run_hook() { HOOK_OUT=$(printf '%s' "$1" | bash "$hook" 2>/dev/null); HOOK_RC=$?; }
marker_of() { printf '%s' "$TMPDIR/codex-plan-latest-$1"; }
seed_marker() { printf '/old/plan.md\n' > "$(marker_of "$1")"; }

# expect_silent <case> <session> [marker: absent|seeded|<path>]
expect_silent() {
  local name="$1" m err=""
  m=$(marker_of "$2")
  [ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
  [ -z "$HOOK_OUT" ] || err="${err:+$err; }expected no output, got: $HOOK_OUT"
  case "${3:-}" in
    '') ;;
    absent) [ ! -e "$m" ] || err="${err:+$err; }marker still there: $(cat "$m")" ;;
    seeded) [ "$(cat "$m" 2>/dev/null)" = "/old/plan.md" ] || err="${err:+$err; }marker changed: $(cat "$m" 2>/dev/null)" ;;
    *) [ "$(cat "$m" 2>/dev/null)" = "$3" ] || err="${err:+$err; }marker holds '$(cat "$m" 2>/dev/null)', want '$3'" ;;
  esac
  if [ -z "$err" ]; then pass "$name"; else fail_case "$name" "$err"; fi
}

# expect_block <case> <reason substring>...
expect_block() {
  local name="$1" decision reason err="" s
  shift
  decision=$(printf '%s' "$HOOK_OUT" | jq -r '.decision // empty' 2>/dev/null)
  reason=$(printf '%s' "$HOOK_OUT" | jq -r '.reason // empty' 2>/dev/null)
  [ "$HOOK_RC" -eq 0 ] || err="exit $HOOK_RC"
  [ "$decision" = "block" ] || err="${err:+$err; }expected decision block, got: $HOOK_OUT"
  for s in "$@"; do
    contains "$reason" "$s" || err="${err:+$err; }expected '$s' in: $reason"
  done
  if [ -z "$err" ]; then pass "$name"; else fail_case "$name" "$err"; fi
}

valid=$(fill_exec < "$plans/valid.md")
codex_valid=$(printf '%s\n' "$valid" | sed \
  -e "s|^claude --agent $RUN_TIER \"/execute-plan \(.*\)\"\$|codex -m $RUN_CODEX_MODEL -c model_reasoning_effort=$RUN_CODEX_EFFORT \"Execute the plan at \1\"|")
good=$(plan_file "$valid")
codex_good=$(plan_file "$codex_valid")
bad=$(plan_file "$(fill_exec < "$plans/tbd.md")")

# --- syntax --------------------------------------------------------------------------------------
if bash -n "$hook" 2>/dev/null; then pass "syntax:hook"; else fail_case "syntax:hook" "bash -n failed"; fi

# --- a valid plan passes silently and writes the marker -------------------------------------------
run_hook "$(payload s-valid "$(transcript t1 "$(proposed "$good")")" t1)"
expect_silent "valid-plan-writes-marker" s-valid "$good"

run_hook "$(payload s-codex "$(transcript t1 "$(proposed "$codex_good")")" t1)"
expect_silent "codex-fence-plan-writes-marker" s-codex "$codex_good"

# --- prose above ## Run quoting another Execute path never overrides the Run fence's path ---------
quoted() { printf '%s\n' "$(cat "$1")" | sed "/^## Summary$/a\\
Last time we ran: Execute the plan at $root/previous.md"; }
for form in good codex_good; do
  seed_marker "s-quoted-$form"
  run_hook "$(payload "s-quoted-$form" "$(transcript t1 "<proposed_plan>
$(quoted "${!form}")
</proposed_plan>")" t1)"
  expect_silent "prose-execute-quote-uses-run-fence:$form" "s-quoted-$form" "${!form}"
done
seed_marker s-quoted-bad
run_hook "$(payload s-quoted-bad "$(transcript t1 "<proposed_plan>
$(quoted "$bad")
</proposed_plan>")" t1)"
expect_block "prose-execute-quote-checks-run-fence" "placeholder" "Fix the plan file at $bad"

# --- a broken plan blocks with the rule's message and drops the old marker ------------------------
seed_marker s-bad
: > "$AGENTS_HOOK_LOG"
run_hook "$(payload s-bad "$(transcript t1 "$(proposed "$bad")")" t1)"
expect_block "broken-plan-blocks" "placeholder" "Fix the plan file at $bad, then present it again."
if grep -q ' plan-gate-codex deny run$' "$AGENTS_HOOK_LOG"; then pass "broken-plan-logs-deny"; else fail_case "broken-plan-logs-deny" "log: $(cat "$AGENTS_HOOK_LOG")"; fi
if [ ! -e "$(marker_of s-bad)" ]; then pass "broken-plan-drops-marker"; else fail_case "broken-plan-drops-marker" "marker still there"; fi

# --- an Execute line quoted outside a <proposed_plan> block is silent -----------------------------
seed_marker s-quote
run_hook "$(payload s-quote "$(transcript t1 "Run it with: Execute the plan at $bad")" t1)"
expect_silent "execute-outside-block-silent" s-quote seeded

# --- a <proposed_plan> with no Execute line (the real 0.154 rows) is silent, drops the marker -----
seed_marker s-plain
run_hook "$(payload s-plain "$fixtures_dir/real-shape.jsonl" 01a0d7b6-cbb0-7fe3-88db-8c473f061182)"
expect_silent "plain-proposed-plan-drops-marker" s-plain absent

# --- a later plain plan in the same turn wins over an earlier write-plan plan ---------------------
seed_marker s-later
run_hook "$(payload s-later "$(transcript t1 "$(proposed "$bad")
Then a revised plan:
<proposed_plan>
# Add hello.txt
</proposed_plan>")" t1)"
expect_silent "latest-block-wins" s-later absent

# --- a plan from an earlier turn is not this turn's --------------------------------------------------
run_hook "$(payload s-turn "$(transcript t-old "$(proposed "$bad")")" t-new)"
expect_silent "other-turn-plan-ignored" s-turn

# --- no transcript: last_assistant_message is the fallback ----------------------------------------
run_hook "$(payload s-lam "$root/missing.jsonl" t1 "$(jq -nc --arg m "$(proposed "$bad")" '{last_assistant_message:$m}')")"
expect_block "no-transcript-uses-last-message" "placeholder"

# --- the Execute path names no file: silent, drops the marker -------------------------------------
seed_marker s-nofile
run_hook "$(payload s-nofile "$(transcript t1 "<proposed_plan>
## Run
\`\`\`
codex -m $RUN_CODEX_MODEL -c model_reasoning_effort=$RUN_CODEX_EFFORT \"Execute the plan at $root/nope.md\"
\`\`\`
</proposed_plan>")" t1)"
expect_silent "missing-plan-file-silent" s-nofile absent

# --- an unresolved profile turns the deny into an advise: silent, marker written ------------------
HOOK_OUT=$(payload s-noprof "$(transcript t1 "$(proposed "$bad")")" t1 \
  | AGENTS_WORKFLOW_PROFILES="$fixtures_dir/../plan-gate/profiles-empty" bash "$hook" 2>/dev/null); HOOK_RC=$?
expect_silent "unresolved-profile-writes-marker" s-noprof "$bad"

# --- a continued turn blocks a still-broken plan again, and a fixed plan earns the marker -----------
seed_marker s-cont
run_hook "$(payload s-cont "$(transcript t1 "$(proposed "$bad")")" t1 '{"stop_hook_active":true}')"
expect_block "continued-broken-plan-blocks" "placeholder"
if [ ! -e "$(marker_of s-cont)" ]; then pass "continued-broken-plan-drops-marker"; else fail_case "continued-broken-plan-drops-marker" "marker still there"; fi
run_hook "$(payload s-cont2 "$(transcript t1 "$(proposed "$good")")" t1 '{"stop_hook_active":true}')"
expect_silent "continued-fixed-plan-writes-marker" s-cont2 "$good"

# --- a spawn_agent child is silent ----------------------------------------------------------------
run_hook "$(payload s-child "$(transcript t1 "$(proposed "$bad")")" t1 \
  '{"agent_id":"a1","agent_type":"default","agent_transcript_path":"/tmp/child.jsonl"}')"
expect_silent "child-payload-silent" s-child

# --- stall guard: the fourth block in a session allows ---------------------------------------------
tp=$(transcript t1 "$(proposed "$bad")")
got=""
for _ in 1 2 3 4; do
  run_hook "$(payload s-stall "$tp" t1)"
  d=$(printf '%s' "$HOOK_OUT" | jq -r '.decision // empty' 2>/dev/null)
  got="$got ${d:-none}"
done
if [ "$got" = " block block block none" ]; then pass "fourth-block-allows"; else fail_case "fourth-block-allows" "decisions:$got"; fi
expect_silent "fourth-block-writes-marker" s-stall "$bad"

# --- Plan mode cannot write: a missing path under $CODEX_HOME/plans/ is checked from the block ----
unsaved="$CODEX_HOME/plans/widget-import.md"
at_unsaved() { printf '%s\n' "$1" | sed -e "s|Execute the plan at /[^\"]*\.md|Execute the plan at $unsaved|" -e "s|/execute-plan /[^\"]*\.md|/execute-plan $unsaved|"; }
proposed_text() { printf '<proposed_plan>\n%s\n</proposed_plan>' "$1"; }
run_hook "$(payload s-unsaved "$(transcript t1 "$(proposed_text "$(at_unsaved "$codex_valid")")")" t1)"
expect_silent "unsaved-plan-passes-writes-marker" s-unsaved "$unsaved"
if [ ! -e "$CODEX_HOME/plans" ]; then pass "unsaved-plan-gate-writes-no-file"; else fail_case "unsaved-plan-gate-writes-no-file" "gate created $CODEX_HOME/plans"; fi

seed_marker s-unsaved-bad
run_hook "$(payload s-unsaved-bad "$(transcript t1 "$(proposed_text "$(at_unsaved "$(fill_exec < "$plans/tbd.md")")")")" t1)"
expect_block "unsaved-broken-plan-blocks" "placeholder" "present it again in a <proposed_plan> block" \
  "saves it to $unsaved on approval"
if [ ! -e "$(marker_of s-unsaved-bad)" ]; then pass "unsaved-broken-plan-drops-marker"; else fail_case "unsaved-broken-plan-drops-marker" "marker still there"; fi

seed_marker s-unsaved-dots
run_hook "$(payload s-unsaved-dots "$(transcript t1 "<proposed_plan>
## Run
\`\`\`
codex -m $RUN_CODEX_MODEL -c model_reasoning_effort=$RUN_CODEX_EFFORT \"Execute the plan at $CODEX_HOME/plans/../escape.md\"
\`\`\`
</proposed_plan>")" t1)"
expect_silent "unsaved-dotdot-path-silent" s-unsaved-dots absent

# --- the 0.154 smoke shape: a block continues the turn, so one turn_id holds the denied plan, the
# <hook_prompt> user row and the resent plan; only the resent (latest) plan is checked -------------
# retry_transcript <turn id> <first final text> <second final text>
retry_transcript() {
  local t
  t=$(transcript "$1" "$2")
  jq -nc --arg t "$1" '{type:"response_item",payload:{type:"message",role:"user",content:[{type:"input_text",
    text:"<hook_prompt hook_run_id=\"stop:17:/Users/e/.codex/hooks.json\">plan-gate: the Run section names no model from ~/.agents/workflow-models/codex.md.</hook_prompt>"}],
    internal_chat_message_metadata_passthrough:{turn_id:$t}}}' >> "$t"
  jq -nc --arg t "$1" --arg x "$3" '{type:"response_item",payload:{type:"message",role:"assistant",content:[{type:"output_text",text:$x}],phase:"final_answer",internal_chat_message_metadata_passthrough:{turn_id:$t}}}' >> "$t"
  printf '%s' "$t"
}
fake_model=$(printf '%s\n' "$codex_valid" | sed "s/$RUN_CODEX_MODEL/gpt-9-fake/g")
no_reviewer=$(printf '%s\n' "$codex_valid" | sed "s|^- claude, ${TIER_A} tier subagent:|- /root/plan_review:|")
first=$(proposed_text "$(at_unsaved "$fake_model")")

rm -f "$TMPDIR/codex-plan-gate-s-retry"
run_hook "$(payload s-retry "$(transcript t1 "$first")" t1)"
expect_block "retry-first-plan-blocks" "names no model"
run_hook "$(payload s-retry "$(retry_transcript t1 "$first" "$(proposed_text "$(at_unsaved "$codex_valid")")")" t1 \
  '{"stop_hook_active":true}')"
expect_silent "retry-fixed-plan-writes-marker" s-retry "$unsaved"

run_hook "$(payload s-retry2 "$(retry_transcript t1 "$first" "$(proposed_text "$(at_unsaved "$no_reviewer")")")" t1 \
  '{"stop_hook_active":true}')"
expect_block "retry-still-broken-plan-blocks" "names no reviewing agent"
if [ ! -e "$(marker_of s-retry2)" ]; then pass "retry-still-broken-plan-no-marker"; else fail_case "retry-still-broken-plan-no-marker" "marker: $(cat "$(marker_of s-retry2)")"; fi

# --- the Run fence's effort must equal the exec row of codex.md
wrong_effort=$(plan_file "$(printf '%s\n' "$codex_valid" | sed "s/effort=$RUN_CODEX_EFFORT/effort=$RUN_CODEX_OTHER_EFFORT/")")
run_hook "$(payload s-wrong-effort "$(transcript t1 "$(proposed "$wrong_effort")")" t1)"
expect_block "codex-wrong-effort-blocks" "must name the $RUN_TIER row of codex.md: $RUN_CODEX_MODEL at $RUN_CODEX_EFFORT effort"
upper_effort=$(plan_file "$(printf '%s\n' "$codex_valid" | sed "s/effort=$RUN_CODEX_EFFORT/effort=$(printf '%s' "$RUN_CODEX_EFFORT" | tr '[:lower:]' '[:upper:]')/")")
run_hook "$(payload s-upper-effort "$(transcript t1 "$(proposed "$upper_effort")")" t1)"
expect_silent "codex-right-pair-any-case-writes-marker" s-upper-effort "$upper_effort"

# --- Done when: a plain-text cell blocks, and the file layout's brief rules hold on the Codex path --
bad_done=$(plan_file "$(printf '%s\n' "$valid" | sed "s/| \`yarn test\` |/| yarn test |/")")
run_hook "$(payload s-done "$(transcript t1 "$(proposed "$bad_done")")" t1)"
expect_block "done-when-text-blocks" "Steps row S1 has a Done when that is not one backticked command" "Fix the plan file at $bad_done"

ptr=$(mktemp -d "$root/ptr.XXXXXX")
printf '%s\n' "$valid" | sed -e "s|/Users/example/.claude/plans/widget-import.md|$ptr/widget-import.md|g" -e '/^## Briefs$/,$d' > "$ptr/widget-import.md"
printf '## Briefs\n\nBriefs: %s/widget-import.briefs/, one file per delegated row.\n' "$ptr" >> "$ptr/widget-import.md"
mkdir "$ptr/widget-import.briefs"
printf 'Brief S0\n' > "$ptr/widget-import.briefs/S0.md"
printf 'Brief S1\n' > "$ptr/widget-import.briefs/S1.md"
seq 26 > "$ptr/widget-import.briefs/S3.md"
: > "$AGENTS_HOOK_LOG"
run_hook "$(payload s-ptr "$(transcript t1 "$(proposed "$ptr/widget-import.md")")" t1)"
expect_silent "pointer-brief-over-25-writes-marker" s-ptr "$ptr/widget-import.md"
if grep -q ' plan-gate-codex advise brief$' "$AGENTS_HOOK_LOG"; then pass "pointer-brief-over-25-logs-advise"; else fail_case "pointer-brief-over-25-logs-advise" "log: $(cat "$AGENTS_HOOK_LOG")"; fi

rm -f "$ptr/widget-import.briefs/S3.md"
run_hook "$(payload s-ptr2 "$(transcript t1 "$(proposed "$ptr/widget-import.md")")" t1)"
expect_block "pointer-brief-missing-blocks" "its brief file $ptr/widget-import.briefs/S3.md is missing or empty"

# --- malformed input is silent ---------------------------------------------------------------------
run_hook 'not json {'
expect_silent "malformed-silent" s-none
run_hook '[1,2]'
expect_silent "non-object-silent" s-none

exit $overall
