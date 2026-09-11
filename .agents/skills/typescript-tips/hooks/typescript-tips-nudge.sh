#!/usr/bin/env bash
# UserPromptSubmit hook, advisory: replaces the inline settings.json entry that fired the
# typescript-tips reminder on a /review-shaped prompt. Same regex and additionalContext text as
# that inline hook; the only behavior change is skipping notifications and negated phrasing.
# Wired: UserPromptSubmit.
# codex: yes

input=$(jq -c 'select(type=="object")' 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0

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

if prompt_matches "$prompt" '/(review|code-review|security-review)([[:space:]]|$)'; then
  emit_context "UserPromptSubmit" "Review command detected. MANDATORY: if the changes under review include any TypeScript files (.ts/.tsx), you MUST run the typescript-tips skill (the Skill tool where it exists, else its SKILL.md) and apply its conventions to the TypeScript-quality portion of the review before finalizing. Do not skip this."
fi

exit 0
