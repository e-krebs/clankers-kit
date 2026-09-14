#!/usr/bin/env bash
# PreToolUse(Write|Edit|MultiEdit) gate: deny "big" comments — JSDoc /** */ and multi-line
# /* */ — added to TypeScript and JavaScript files (.ts/.tsx/.js/.jsx/.mjs/.cjs). Terse
# single-line // is always allowed.
# Wired via ~/.claude/settings.json -> PreToolUse[matcher=Write|Edit|MultiEdit].
#
# Matching is TEXTUAL (line-oriented grep), not a TS parse: a /* or /** inside a string or
# regex literal can still trip a rule. Accepted limitation (same as forbid-bash-patterns.sh)
# — the goal is catching the habitual verbose-comment reflex, not defeating evasion. If a
# block is genuinely load-bearing, the deny message tells Claude to surface it to the user.
#
# Existing-style exemption: if the target file ALREADY uses a style, new uses of that same
# style pass (mirrors the CLAUDE.md rule "no JSDoc / multi-line blocks unless the file
# already uses them"). Fresh files (no file on disk yet) get the strict rule.
#
# Per-repo JSDoc opt-out: a repo that documents exports with JSDoc can allow /** */ blocks by
# committing a .claude/allow-jsdoc marker at its root. Multi-line /* */ blocks stay blocked.
# codex: no

input=$(cat)

# shellcheck source=lib/hook-log.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-log.sh"
HOOK_SESSION=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)

agent_id=$(printf '%s' "$input" | jq -r '.agent_id // empty' 2>/dev/null)
[ -z "$agent_id" ] || exit 0

file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0  # fail open
case "$file" in
  *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs) ;;
  *) exit 0 ;;
esac

repo_root=$(git -C "$(dirname "$file")" rev-parse --show-toplevel 2>/dev/null || true)
allow_jsdoc=false
[ -n "$repo_root" ] && [ -f "$repo_root/.claude/allow-jsdoc" ] && allow_jsdoc=true

tool_name=$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null)
if [ "$tool_name" = "MultiEdit" ]; then
  # every edit's new_string, concatenated — only the added text matters, same as Write/Edit
  added=$(printf '%s' "$input" | jq -r '[.tool_input.edits[]?.new_string // empty] | join("\n")' 2>/dev/null) || exit 0
else
  # Write provides .content; Edit provides .new_string — only the added text matters.
  added=$(printf '%s' "$input" | jq -r '.tool_input.content // .tool_input.new_string // empty' 2>/dev/null) || exit 0
fi
[ -z "$added" ] && exit 0

deny() {  # $1 = reason shown back to Claude, $2 = rule id
  hook_log deny "$2"
  jq -nc --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

# /** anywhere
has_jsdoc()  { printf '%s' "$1" | grep -qE '/\*\*'; }
# a /* opener (NOT the /** JSDoc form) on a line with no closing */ — i.e. a multi-line block
has_block()  { printf '%s\n' "$1" | grep -E '/\*([^*]|$)' | grep -vqE '\*/'; }

added_jsdoc=false; has_jsdoc "$added" && added_jsdoc=true
added_block=false; has_block "$added" && added_block=true

# only terse // (or no comments at all) — allow
[ "$added_jsdoc" = false ] && [ "$added_block" = false ] && exit 0

file_jsdoc=false; [ -f "$file" ] && grep -qE '/\*\*' "$file" && file_jsdoc=true
file_block=false; [ -f "$file" ] && grep -E '/\*([^*]|$)' "$file" | grep -vqE '\*/' && file_block=true

if [ "$added_jsdoc" = true ] && [ "$file_jsdoc" = false ] && [ "$allow_jsdoc" = false ]; then
  deny "Big comment blocked: that's a JSDoc /** */ block, which $file doesn't use. Use a terse single-line // or omit it (a comment that restates a well-named symbol is noise). If it's genuinely load-bearing, tell me and I'll keep it." "jsdoc"
fi
if [ "$added_block" = true ] && [ "$file_block" = false ]; then
  deny "Big comment blocked: that's a multi-line /* */ block, which $file doesn't use. Use a terse single-line // or omit it (a comment that restates a well-named symbol is noise). If it's genuinely load-bearing, tell me and I'll keep it." "block"
fi

exit 0
