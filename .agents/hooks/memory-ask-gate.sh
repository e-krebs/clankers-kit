#!/usr/bin/env bash
# PreToolUse(Write) gate: block the first write that would CREATE a memory file, so a new memory
# is the user's decision rather than a side effect. The deny records the path for this session, so
# the same write passes on the retry that follows the user's yes — the nudge-once shape, since a
# hook cannot see whether the question was asked.
#
# Only a creation is gated: an existing file (an update), MEMORY.md (the index), and anything
# outside a memory store all pass. A memory store is a path holding /.claude/projects/<key>/memory/,
# which covers both the live store and the copy the memories row versions in this repo.
#
# Fails open everywhere: bad/missing stdin, another tool, no file_path, a path outside a store, an
# existing file, or an unwritable marker dir all just exit 0, no output.
# codex: no

input=$(jq -c 'select(type=="object")' 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0

source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-log.sh"
HOOK_SESSION=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)

tool=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)
[ "$tool" = "Write" ] || exit 0

path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -n "$path" ] || exit 0

case "$path" in
  */.claude/projects/*/memory/*) ;;
  *) exit 0 ;;
esac
case "${path##*/}" in
  MEMORY.md) exit 0 ;;
esac
[ -e "$path" ] && exit 0

marker_dir="${AGENTS_MEMORY_ASKED:-${TMPDIR:-/tmp}/memory-ask-gate}"
key=$(printf '%s\n' "${HOOK_SESSION:-unknown}$path" | LC_ALL=C tr -c 'A-Za-z0-9' '-')
marker="$marker_dir/$key"
[ -e "$marker" ] && exit 0

mkdir -p "$marker_dir" 2>/dev/null || exit 0
: > "$marker" 2>/dev/null || exit 0

reason="A new memory is the user's decision, so ask before writing one: name the fact and where it \
would live, through the harness's question tool where it has one, else as one numbered question. A \
rule that belongs in a skill, a hook or AGENTS.md goes there instead, because those enforce it \
while a memory only reminds, and every memory spends context in every later session. On a yes, run \
this same write again and it will pass. Updating or deleting an existing memory needs no ask."

hook_log deny memory-ask
jq -nc --arg r "$reason" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
exit 0
