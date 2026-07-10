#!/usr/bin/env bash
# PreToolUse(Write|Edit) gate: deny "big" comments — JSDoc /** */ and multi-line /* */ —
# added to .ts/.tsx files. Terse single-line // is always allowed.
# Wired via ~/.claude/settings.json -> PreToolUse[matcher=Write|Edit] (the "enforcement" preset).
#
# Matching is TEXTUAL (line-oriented grep), not a TS parse: a /* or /** inside a string or
# regex literal can still trip a rule. Accepted limitation (same as forbid-bash-patterns.sh)
# — the goal is catching the habitual verbose-comment reflex, not defeating evasion. If a
# block is genuinely load-bearing, the deny message tells Claude to surface it to the user.
#
# Existing-style exemption: if the target file ALREADY uses a style, new uses of that same
# style pass (mirrors the CLAUDE.md rule "no JSDoc / multi-line blocks unless the file
# already uses them"). Fresh files (no file on disk yet) get the strict rule.

input=$(cat)

file=$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0  # fail open
case "$file" in
  *.ts|*.tsx) ;;
  *) exit 0 ;;
esac

# Write provides .content; Edit provides .new_string — only the added text matters.
added=$(printf '%s' "$input" | jq -r '.tool_input.content // .tool_input.new_string // empty' 2>/dev/null) || exit 0
[ -z "$added" ] && exit 0

deny() {  # $1 = reason shown back to Claude
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

if [ "$added_jsdoc" = true ] && [ "$file_jsdoc" = false ]; then
  deny "Big comment blocked: that's a JSDoc /** */ block, which $file doesn't use. Use a terse single-line // or omit it (a comment that restates a well-named symbol is noise). If it's genuinely load-bearing, tell me and I'll keep it."
fi
if [ "$added_block" = true ] && [ "$file_block" = false ]; then
  deny "Big comment blocked: that's a multi-line /* */ block, which $file doesn't use. Use a terse single-line // or omit it (a comment that restates a well-named symbol is noise). If it's genuinely load-bearing, tell me and I'll keep it."
fi

exit 0
