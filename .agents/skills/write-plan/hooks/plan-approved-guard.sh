#!/usr/bin/env bash
# The approved-plan guard. plan-followthrough writes ${TMPDIR:-/tmp}/claude-plan-approved-<session>
# when ExitPlanMode is approved, holding the Run block. While that marker exists, PreToolUse denies
# every tool with the block in the reason, so the model's only move is to reply with the block and
# end the turn, and the plan runs in a fresh session as the skill intends. Stop checks that the
# reply holds the block's launch line: it blocks the stop with the block as the reason until it
# does, at most MAX_BLOCKS times per marker, then removes the marker. UserPromptSubmit removes the
# marker, so the next turn is free. Silent for subagents and whenever an input is missing.
# Wired: PreToolUse (every tool), Stop, UserPromptSubmit.
# codex: no

MAX_BLOCKS=2

input=$(jq -c 'select(type=="object")' 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0

session=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
[ -n "$session" ] || exit 0
marker="${TMPDIR:-/tmp}/claude-plan-approved-${session//[^A-Za-z0-9_-]/}"
[ -f "$marker" ] || exit 0

event=$(printf '%s' "$input" | jq -r '.hook_event_name // empty' 2>/dev/null)
case "$event" in
  UserPromptSubmit)
    rm -f "$marker" "$marker.blocks" 2>/dev/null
    exit 0
    ;;
  PreToolUse|Stop) ;;
  *) exit 0 ;;
esac

agent_id=$(printf '%s' "$input" | jq -r '.agent_id // empty' 2>/dev/null)
[ -z "$agent_id" ] || exit 0

hooks_lib="${AGENTS_HOOKS_LIB:-$(dirname "${BASH_SOURCE[0]}")/../../../hooks/lib}"
[ -f "$hooks_lib/hook-log.sh" ] || hooks_lib="$HOME/.claude/hooks/lib"
# shellcheck source=../../../hooks/lib/hook-log.sh
source "$hooks_lib/hook-log.sh" 2>/dev/null || true
HOOK_SESSION=$session
log() { command -v hook_log >/dev/null 2>&1 && hook_log "$@"; return 0; }

block=$(cat "$marker" 2>/dev/null)
reason="The plan is approved and this session ends here. Reply with the block below verbatim, then end the turn. A fresh session runs the plan.
$block"

if [ "$event" = Stop ]; then
  needle=$(printf '%s\n' "$block" | grep -m1 -E '^(claude --agent|codex -m) ')
  reply=$(printf '%s' "$input" | jq -r '.last_assistant_message // empty' 2>/dev/null)
  if [ -z "$needle" ] || printf '%s' "$reply" | grep -qF -- "$needle"; then
    rm -f "$marker" "$marker.blocks" 2>/dev/null
    exit 0
  fi
  d=0
  [ -f "$marker.blocks" ] && d=$(< "$marker.blocks")
  case "$d" in ''|*[!0-9]*) d=0 ;; esac
  if [ "$d" -ge "$MAX_BLOCKS" ]; then
    rm -f "$marker" "$marker.blocks" 2>/dev/null
    log advise budget:approved
    exit 0
  fi
  printf '%s' "$((d + 1))" > "$marker.blocks" 2>/dev/null || exit 0
  log block approved
  jq -nc --arg r "$reason" '{decision:"block",reason:$r}'
  exit 0
fi

log deny approved
jq -nc --arg r "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
