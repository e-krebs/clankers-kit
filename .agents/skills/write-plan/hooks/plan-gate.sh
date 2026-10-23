#!/usr/bin/env bash
# PreToolUse gate on ExitPlanMode, the Claude adapter over lib/plan-check.sh: the checker owns the
# plan contract and the profile policy, this script owns the payload, the subagent silence, the
# hook log, the stall guard and the JSON. A checker deny blocks the plan, an unresolved profile
# turns it into context, and a pass carries the link and style advisories as context. A stall
# guard stops denying after 3 denials per session.
#
# The run-print transcript check came out on 2026-09-28: the VSCode extension writes no assistant
# text row for a message that also calls ExitPlanMode or AskUserQuestion, so the check never
# matched, burnt its two denials and passed on budget every time, and the user saw no print
# either. The launch line lives in the plan's Run section (checker rule "fence"), and
# plan-followthrough plus plan-approved-guard make the model print it as its reply on approval.
# Outside plan mode the gate denies first: an ExitPlanMode there approves nothing, and the agent
# went on to run the plan in the same session (twice on 2026-10-22).
# Wired: PreToolUse, matcher ExitPlanMode.
# codex: no

MAX_DENIALS=3

input=$(jq -c 'select(type=="object")' 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0

hooks_lib="${AGENTS_HOOKS_LIB:-$(dirname "${BASH_SOURCE[0]}")/../../../hooks/lib}"
[ -f "$hooks_lib/hook-log.sh" ] || hooks_lib="$HOME/.claude/hooks/lib"
# shellcheck source=../../../hooks/lib/hook-log.sh
source "$hooks_lib/hook-log.sh"
HOOK_SESSION=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)

agent_id=$(printf '%s' "$input" | jq -r '.agent_id // empty' 2>/dev/null)
[ -z "$agent_id" ] || exit 0

permission_mode=$(printf '%s' "$input" | jq -r '.permission_mode // empty' 2>/dev/null)
if [ -n "$permission_mode" ] && [ "$permission_mode" != "plan" ]; then
  hook_log deny not-in-plan-mode
  jq -nc '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"The session is not in plan mode, so ExitPlanMode approves nothing. Do not run the plan. Load the tools with ToolSearch select:EnterPlanMode,ExitPlanMode, call EnterPlanMode, then call ExitPlanMode again. A fresh session runs the plan."}}'
  exit 0
fi

plan_text=$(printf '%s' "$input" | jq -r '.tool_input.plan // empty' 2>/dev/null)
plan_file=$(printf '%s' "$input" | jq -r '.tool_input.planFilePath // empty' 2>/dev/null)
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$cwd" ] || cwd=$PWD

# an inline plan goes to a temp file, because the checker reads a path
tmp=""
if [ -n "$plan_text" ]; then
  tmp=$(mktemp "${TMPDIR:-/tmp}/claude-plangate-XXXXXX" 2>/dev/null) || exit 0
  printf '%s' "$plan_text" > "$tmp" 2>/dev/null
  plan_path=$tmp
else
  [ -n "$plan_file" ] && [ -f "$plan_file" ] || exit 0
  plan_path=$plan_file
fi
out=$(bash "$(dirname "${BASH_SOURCE[0]}")/lib/plan-check.sh" --plan "$plan_path" --plan-file-path "$plan_file" --cwd "$cwd" 2>/dev/null)
[ -z "$tmp" ] || rm -f "$tmp" 2>/dev/null

verdict="" rule="" fail="" links="" style="" briefs=""
while IFS=$'\t' read -r kind tag text; do
  case "$kind:$tag" in
    deny:*) verdict=deny rule=$tag fail=$text ;;
    advise:unresolved-profile:*) verdict=advise rule=${tag#unresolved-profile:} fail=$text ;;
    advise:link) links="${links:+$links
}$text" ;;
    advise:brief) briefs="${briefs:+$briefs
}$text" ;;
    advise:style) style=$text ;;
  esac
done <<< "$out"

if [ "$verdict" = "deny" ]; then
  session=$(printf '%s' "$input" | jq -r '.session_id // "unknown"' 2>/dev/null)
  counter="${TMPDIR:-/tmp}/claude-plan-gate-${session//[^A-Za-z0-9_-]/}"
  d=0
  [ -f "$counter" ] && d=$(< "$counter")
  case "$d" in ''|*[!0-9]*) d=0 ;; esac
  if [ "$d" -ge "$MAX_DENIALS" ]; then
    hook_log advise "budget:${rule:--}"
    exit 0
  fi
  printf '%s' "$((d + 1))" > "$counter" 2>/dev/null || exit 0   # no counter, no escape hatch: allow
  hook_log deny "$rule"
  jq -nc --arg r "$fail" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
fi

if [ "$verdict" = "advise" ]; then
  hook_log advise "no-profile:${rule:--}"
  jq -nc --arg ctx "$fail" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$ctx}}'
  exit 0
fi

ctx=$links
[ -z "$links" ] || hook_log advise link
if [ -n "$briefs" ]; then
  hook_log advise brief
  ctx="${ctx:+$ctx
}$briefs"
fi
if [ -n "$style" ]; then
  hook_log advise style
  ctx="${ctx:+$ctx
}$style"
fi
[ -z "$ctx" ] || jq -nc --arg ctx "$ctx" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$ctx}}'
exit 0
