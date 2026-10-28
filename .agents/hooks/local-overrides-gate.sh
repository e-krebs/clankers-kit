#!/usr/bin/env bash
# PreToolUse(Bash) gate: deny a "git commit" while the tracked local overrides are wrong. Runs only in
# a repo that carries this hook. The hidden check compares settings.local.json with
# .claude/settings/base.json, the preset setup.sh seeds the user settings from.
#
# Fails open everywhere: bad/missing stdin, a subagent session, no "git commit" in the command, or a
# repo without this hook just exits 0, no output.
# codex: no

if [ "${1:-}" = "--check" ]; then
  root="${2:?usage: local-overrides-gate.sh --check <repo root>}"
fi

local_overrides_failure() {  # $1 = repo root -> the first failed check on stdout, exit 1
  local root="$1" allow=() out key val
  git -C "$root" cat-file -e HEAD:.claude/settings.local.json 2>/dev/null || allow=(--allow-missing)
  if ! out=$(bash "$root/.agents/check-local-overrides.sh" ${allow[@]+"${allow[@]}"} "$root" 2>&1); then
    printf '%s' "$(printf '%s' "$out" | tr '\n' ' ')"
    return 1
  fi

  local local_file="$root/.claude/settings.local.json" user_file="$root/.claude/settings/base.json"
  [ -f "$local_file" ] || return 0
  while IFS= read -r key; do
    val=$(jq -r --arg k "$key" '.skillOverrides[$k] // empty' "$user_file" 2>/dev/null)
    case "$val" in
      user-invocable-only|name-only|off) ;;
      *)
        printf 'skill "%s" is on in settings.local.json but base.json does not hide it (%s), so the override does nothing' "$key" "${val:-unset}"
        return 1 ;;
    esac
  done < <(jq -r '(.skillOverrides // {}) | keys[]' "$local_file" 2>/dev/null)
}

if [ -n "${root:-}" ]; then
  if reason=$(local_overrides_failure "$root"); then exit 0; fi
  printf '%s\n' "$reason" >&2
  exit 1
fi

input=$(jq -c 'select(type=="object")' 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0

hooks_dir=$(CDPATH='' cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$hooks_dir/lib/hook-log.sh"
HOOK_SESSION=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)

agent_id=$(printf '%s' "$input" | jq -r '.agent_id // empty' 2>/dev/null)
[ -z "$agent_id" ] || exit 0

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -n "$cmd" ] || exit 0
case "$cmd" in
  *"git commit"*) ;;
  *) exit 0 ;;
esac

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$cwd" ] || cwd=$PWD
root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -f "$root/.agents/hooks/local-overrides-gate.sh" ] || exit 0

if reason=$(local_overrides_failure "$root"); then exit 0; fi

hook_log deny "local-overrides"
jq -nc --arg r "Commit blocked: $reason. Fix .claude/settings.local.json or base.json before committing." '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
