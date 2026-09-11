#!/usr/bin/env bash
# Unit cases for lib/prompt-guards.sh: prompt_is_notification, prompt_matches (including its
# same-clause negation guard), and emit_context. Locates the lib relative to this file's own
# path so it still works once these fixtures are copied into the real repo.

set -u

fixtures_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
libfile="$fixtures_dir/../../lib/prompt-guards.sh"

overall=0
log_dir=$(mktemp -d "${TMPDIR:-/tmp}/hooklog.XXXXXX")
export AGENTS_HOOK_LOG="$log_dir/hook-events.log"
trap 'rm -rf "$log_dir" 2>/dev/null' EXIT

pass() { printf 'PASS %s\n' "$1"; }
fail_case() { printf 'FAIL %s: %s\n' "$1" "$2"; overall=1; }

if bash -n "$libfile" 2>/tmp/lpg-syn.$$; then
  pass "syntax:lib"
else
  fail_case "syntax:lib" "bash -n failed: $(head -1 /tmp/lpg-syn.$$ 2>/dev/null)"
fi
rm -f /tmp/lpg-syn.$$ 2>/dev/null

# shellcheck disable=SC1090  # the lib path is computed above
source "$libfile" || { fail_case "source" "could not source $libfile"; exit 1; }

# --- negation within two words skips ------------------------------------------
case_name="negation-immediate-skips"
if prompt_matches "please don't plan this out today" "plan (this|it|out)"; then
  fail_case "$case_name" "matched despite an immediate negation"
else
  pass "$case_name"
fi

case_name="negation-do-not-skips"
if prompt_matches "do not make a plan yet" "make a plan"; then
  fail_case "$case_name" "matched despite 'do not'"
else
  pass "$case_name"
fi

case_name="negation-two-words-away-skips"
if prompt_matches "never really wanted plan this out" "plan (this|it|out)"; then
  fail_case "$case_name" "matched despite a negation two words earlier"
else
  pass "$case_name"
fi

# --- a match after unrelated words (negation too far back) fires --------------
case_name="match-after-unrelated-words-fires"
if prompt_matches "the roadmap review runs monday, let's plan out the migration" "let's plan|plan (this|it|out)"; then
  pass "$case_name"
else
  fail_case "$case_name" "expected a match past unrelated words"
fi

case_name="negation-far-away-still-fires"
if prompt_matches "I don't like Mondays much but let's plan out the launch" "let's plan|plan (this|it|out)"; then
  pass "$case_name"
else
  fail_case "$case_name" "expected the negation guard to only cover the next two words"
fi

# --- notification strings detected --------------------------------------------
case_name="notification-task"
if prompt_is_notification "<task-notification>pick up the next ticket</task-notification>"; then
  pass "$case_name"
else
  fail_case "$case_name" "expected true for <task-notification>"
fi

case_name="notification-system"
if prompt_is_notification "[SYSTEM NOTIFICATION] something happened"; then
  pass "$case_name"
else
  fail_case "$case_name" "expected true for [SYSTEM NOTIFICATION"
fi

case_name="notification-command-name"
if prompt_is_notification "<command-name>/ticket-kickoff</command-name>"; then
  pass "$case_name"
else
  fail_case "$case_name" "expected true for <command-name>"
fi

case_name="notification-plain-prompt-false"
if prompt_is_notification "just a normal prompt"; then
  fail_case "$case_name" "expected false for a plain prompt"
else
  pass "$case_name"
fi

# --- emit_context output parses -------------------------------------------------
case_name="emit-context-parses"
out=$(emit_context "UserPromptSubmit" "hello world")
err=""
printf '%s' "$out" | jq -e . >/dev/null 2>&1 || err="output is not valid JSON: $out"
if [ -z "$err" ]; then
  [ "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName')" = "UserPromptSubmit" ] || err="wrong hookEventName"
fi
if [ -z "$err" ]; then
  [ "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext')" = "hello world" ] || err="${err:+$err; }wrong additionalContext"
fi
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- sibling-nudge regexes and helper -------------------------------------------
case_name="nudge-merge-re-matches"
if prompt_matches "please merge the PR now" "$NUDGE_MERGE_RE"; then
  pass "$case_name"
else
  fail_case "$case_name" "expected NUDGE_MERGE_RE to match 'please merge the PR now'"
fi

case_name="nudge-pickup-re-matches"
if prompt_matches "pick up my next ticket" "$NUDGE_PICKUP_RE"; then
  pass "$case_name"
else
  fail_case "$case_name" "expected NUDGE_PICKUP_RE to match 'pick up my next ticket'"
fi

case_name="sibling-nudge-helper-matches-merge"
if prompt_matches_sibling_nudge "merge this pull request"; then
  pass "$case_name"
else
  fail_case "$case_name" "expected true for 'merge this pull request'"
fi

case_name="sibling-nudge-helper-false-on-create-ticket"
if prompt_matches_sibling_nudge "create a jira ticket for this"; then
  fail_case "$case_name" "expected false for 'create a jira ticket for this'"
else
  pass "$case_name"
fi

exit $overall
