#!/usr/bin/env bash
# Stop gate for a Codex Plan-mode turn, the Codex adapter over lib/plan-check.sh. Codex has no
# approval tool, so the gate fires only when this turn's assistant text holds a <proposed_plan>
# block whose Run fence holds an Execute line; the text comes from transcript_path, because Stop's
# last_assistant_message misses the <proposed_plan> item. A checker deny blocks the stop with the
# fix as the next prompt, and a pass or advise-only result writes the plan marker that
# plan-followthrough-codex reads. Plan mode forbids writes, so an Execute path under
# ${CODEX_HOME:-~/.codex}/plans/ may not exist yet: the gate then checks the block text, and the
# followthrough saves it on approval. A <proposed_plan> with no such line removes the marker.
# A block continues the same turn, so the fixed plan is checked on that turn's next Stop
# (stop_hook_active true) and blocks again if it still fails, or the model never hears the next
# rule; a stall guard stops blocking after 3 blocks per session. Wired: Stop.
# codex: only

MAX_BLOCKS=3

input=$(jq -c 'select(type=="object")' 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0

hooks_lib="${AGENTS_HOOKS_LIB:-$(dirname "${BASH_SOURCE[0]}")/../../../hooks/lib}"
[ -f "$hooks_lib/hook-log.sh" ] || hooks_lib="$HOME/.claude/hooks/lib"
# shellcheck source=../../../hooks/lib/hook-log.sh
source "$hooks_lib/hook-log.sh"
# shellcheck source=lib/plan-run-fence.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/plan-run-fence.sh" || exit 0
HOOK_SESSION=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)

agent_id=$(printf '%s' "$input" | jq -r '.agent_id // empty' 2>/dev/null)
[ -z "$agent_id" ] || exit 0

transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)
turn=$(printf '%s' "$input" | jq -r '.turn_id // empty' 2>/dev/null)
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$cwd" ] || cwd=$PWD

text=""
if [ -n "$turn" ] && [ -f "$transcript" ]; then
  text=$(jq -r --arg t "$turn" 'select(.type == "response_item" and .payload.role == "assistant"
      and .payload.internal_chat_message_metadata_passthrough.turn_id == $t)
    | .payload.content[]? | select(.type == "output_text") | .text // empty' "$transcript" 2>/dev/null)
fi
[ -n "$text" ] || text=$(printf '%s' "$input" | jq -r '.last_assistant_message // empty' 2>/dev/null)

# the latest <proposed_plan> block, an unclosed one included: a continued turn holds every plan
# the model sent in it, the denied ones first
block=$(printf '%s\n' "$text" | awk '
  index($0, "<proposed_plan>") { found = 1; buf = ""; sub(/.*<proposed_plan>/, ""); open = 1 }
  open && index($0, "</proposed_plan>") { sub(/<\/proposed_plan>.*/, ""); buf = buf $0 "\n"; open = 0; next }
  open { buf = buf $0 "\n" }
  END { if (found) printf "found\n%s", buf }')
[ -n "$block" ] || exit 0

sid=${HOOK_SESSION//[^A-Za-z0-9_-]/}
marker=""
[ -z "$sid" ] || marker="${TMPDIR:-/tmp}/codex-plan-latest-$sid"
mark() { [ -z "$marker" ] || printf '%s\n' "$1" > "$marker" 2>/dev/null; }
unmark() { [ -z "$marker" ] || rm -f "$marker" 2>/dev/null; }

# the Run fence's path only, so prose quoting another Execute line cannot override it
path=$(printf '%s\n' "${block#found}" | plan_run_fence | sed -n \
  -e 's/^claude --agent .*"\/execute-plan \(\/[^"]*\)".*$/\1/p' \
  -e 's/^codex -m .*"Execute the plan at \(\/[^"]*\)".*$/\1/p' | head -n 1)
if [ -z "$path" ]; then
  unmark
  exit 0
fi

plans_dir="${CODEX_HOME:-$HOME/.codex}/plans"
check=$path text_file=""
case "$path" in
  */../*|*/./*) ;;
  "$plans_dir"/*.md)
    text_file=$(mktemp "${TMPDIR:-/tmp}/codex-plan-text-XXXXXX" 2>/dev/null) || exit 0
    printf '%s\n' "${block#found}" > "$text_file" 2>/dev/null
    check=$text_file
    ;;
esac

out=$(bash "$(dirname "${BASH_SOURCE[0]}")/lib/plan-check.sh" --plan "$check" --plan-file-path "$path" --cwd "$cwd" 2>/dev/null)
rc=$?
[ -z "$text_file" ] || rm -f "$text_file" 2>/dev/null
if [ "$rc" -eq 2 ]; then
  unmark
  exit 0
fi

verdict="" rule="" fail=""
while IFS=$'\t' read -r kind tag msg; do
  case "$kind:$tag" in
    deny:*) verdict=deny rule=$tag fail=$msg ;;
    advise:unresolved-profile:*) hook_log advise "no-profile:${tag#unresolved-profile:}" ;;
    advise:link|advise:style|advise:brief) hook_log advise "$tag" ;;
  esac
done <<< "$out"

if [ "$verdict" != "deny" ]; then
  mark "$path"
  exit 0
fi

counter="${TMPDIR:-/tmp}/codex-plan-gate-${sid:-unknown}"
d=0
[ -f "$counter" ] && d=$(< "$counter")
case "$d" in ''|*[!0-9]*) d=0 ;; esac
if [ "$d" -ge "$MAX_BLOCKS" ]; then
  hook_log advise "budget:${rule:--}"
  mark "$path"   # let through, as on Claude, so the followthrough still sees it
  exit 0
fi
printf '%s' "$((d + 1))" > "$counter" 2>/dev/null || exit 0   # no counter, no escape hatch: allow
unmark
hook_log deny "$rule"
fix="Fix the plan file at $path, then present it again."
[ -z "$text_file" ] || fix="Fix the plan, then present it again in a <proposed_plan> block; the hook saves it to $path on approval."
jq -nc --arg r "$fail $fix" '{decision:"block",reason:$r}'
exit 0
