#!/usr/bin/env bash
# UserPromptSubmit hook: a prompt asking for a merge routes to the pr-merge skill, which reads
# the workflow profile, gates the merge plus the tracker move, then executes. Advisory only —
# it emits additionalContext and never blocks.
#
# Fails open everywhere: bad/missing stdin, a subagent session, a missing guards library, or a
# prompt that is an agent/harness notification all just exit 0 with no output.
# codex: yes

input=$(jq -c 'select(type == "object")' 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0                        # empty stdin, null or a scalar: nothing to act on

HOOK_SESSION=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)

agent_id=$(printf '%s' "$input" | jq -r '.agent_id // empty' 2>/dev/null)
[ -z "$agent_id" ] || exit 0

prompt=$(printf '%s' "$input" | jq -r '.prompt // empty' 2>/dev/null)
[ -n "$prompt" ] || exit 0

hooks_lib="${AGENTS_HOOKS_LIB:-$(dirname "${BASH_SOURCE[0]}")/../../../hooks/lib}"
[ -f "$hooks_lib/prompt-guards.sh" ] || hooks_lib="$HOME/.claude/hooks/lib"
# shellcheck source=../../../hooks/lib/prompt-guards.sh
source "$hooks_lib/prompt-guards.sh" || exit 0

prompt_is_notification "$prompt" && exit 0

prompt_matches "$prompt" "$NUDGE_MERGE_RE" || exit 0

emit_context UserPromptSubmit "Merge request detected. Run the pr-merge skill now (the Skill tool where it exists, else its SKILL.md)."
exit 0
