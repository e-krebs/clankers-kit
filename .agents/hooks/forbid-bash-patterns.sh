#!/usr/bin/env bash
# PreToolUse(Bash) gate: deny forbidden command patterns.
# Wired via ~/.claude/settings.json -> PreToolUse[matcher=Bash] (the "enforcement" preset).
#
# Matching is TEXTUAL (line-oriented grep), not a shell parse: a forbidden token
# in a quoted string / commit message / heredoc body can still trip a rule. That's
# an accepted limitation — the goal is catching habitual real invocations, not
# defeating evasion.
#
# To forbid more, add a command to the deny_tools list or add a new rule below. Plain
# alphanumeric words only: list entries are interpolated raw into an ERE, so regex
# metacharacters (. + * [ etc.) are NOT escaped and would mis-match.
#
# This is a STARTER example — adapt the rules to your own stack (e.g. a yarn project
# might forbid bare npm/npx; a Python project might steer awk toward the Read tool).

cmd=$(jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0   # fail open
[ -z "$cmd" ] && exit 0

deny() {  # $1 = reason shown back to Claude
  jq -nc --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

deny_tools() {       # $1 = space-separated commands (command position), $2 = reason
  local list="$1" msg="$2" t
  for t in $list; do
    printf '%s' "$cmd" | grep -qE "(^|[;&|(])[[:space:]]*${t}([[:space:]]|\$)" && deny "$msg"
  done
}

# 1. cd in command position (start, or after ; & | or a subshell paren)
if printf '%s' "$cmd" | grep -qE '(^|[;&|(])[[:space:]]*cd([[:space:]]|$)'; then
  deny "Don't use cd — the Bash tool already runs in the working directory. Pass an absolute path to the command, or add the directory to your allowed working directories, instead of cd-ing."
fi

# 2. git/gh -C/-c global flag in command position (-C <path> dir redirect, -c <k>=<v> inline config)
#    right after the binary — NOT 'git log -C' / 'git show -c' (those follow a subcommand), and NOT
#    a mention inside a quoted string.
if printf '%s' "$cmd" | grep -qE '(^|[;&|(])[[:space:]]*(git|gh)[[:space:]]+-[Cc]([[:space:]]|$)'; then
  deny "Don't pass a git/gh global flag before the subcommand: no -C <path> (cwd is already in the repo) and no -c <key>=<val> inline config override. Run plain git/gh."
fi

# 3. tools whose job the Read/Grep/Glob/Edit tools do better (clickable refs, cleaner diffs, no cwd churn)
deny_tools "sed cat awk tree" "Use the Read tool (offset/limit for line ranges), Grep for searching, and Glob for listing — not sed/cat/awk/tree. For in-place edits use the Edit tool."

# 4. echo must be a literal string. 'echo:*' is commonly allowlisted, so this is the safety net: deny any
#    echo that expands a variable/substitution ($VAR / ${V} / $(...) / `...`) — echo "$TOKEN" leaks secrets.
#    Exception: the canonical $? sentinels (echo "$?" / echo $? / "exit=$?" / "exit: $?").
if printf '%s' "$cmd" | grep -qE '(^|[;&|(])[[:space:]]*echo[[:space:]][^;|&]*(\$|`)' \
   && ! printf '%s' "$cmd" | grep -qE 'echo[[:space:]]+("\$\?"|\$\?|"exit=\$\?"|"exit: \$\?")'; then
  deny "echo must be a literal string here — don't expand variables or substitutions (echo \"\$VAR\" / \$(...) can leak secrets). The Bash tool already reports exit status; for an exit sentinel use the allowlisted echo \"\$?\" verbatim."
fi

# 5. xargs runs an arbitrary command and bypasses the separator-anchored rules above (the inner
#    command sits after a space, not a separator), so deny it unless that command is known-safe.
XARGS_OK='grep'   # allowed inner commands (read-only); extend as an alternation, e.g. 'grep|wc'
if printf '%s' "$cmd" | grep -qE '(^|[;&|(])[[:space:]]*xargs([[:space:]]|$)' \
   && ! printf '%s' "$cmd" | grep -qE "xargs[[:space:]]+(-[^[:space:]]+[[:space:]]+)*(${XARGS_OK})([[:space:]]|\$)"; then
  deny "xargs runs an arbitrary command and bypasses these guards — only 'xargs grep' is allowed. For batch work, search with the Grep tool or run an explicit per-target command."
fi

# 6. find is read-only EXCEPT its action primaries: -exec/-execdir/-ok/-okdir run an arbitrary
#    command, -delete removes files, -fprint/-fprintf/-fls write files. 'find:*' is commonly
#    allowlisted, so deny those forms here. NOT the read-only -print/-printf/-print0/-ls.
if printf '%s' "$cmd" | grep -qE '(^|[;&|(])[[:space:]]*find([[:space:]]|$)' \
   && printf '%s' "$cmd" | grep -qE '[[:space:]]-(exec|execdir|ok|okdir|delete|fprint|fprintf|fprint0|fls)([[:space:]]|$)'; then
  deny "find here must be read-only — no -exec/-execdir/-ok/-okdir (runs a command), -delete (removes files), or -fprint/-fprintf/-fls (writes files). Use find for traversal only, or run the action as a separate explicit command."
fi

# 7. sort is read-only EXCEPT -o/--output, which writes (and can clobber) a file. 'sort:*' is commonly
#    allowlisted, so deny the output-writing forms here. Pure read-only sort (pipes) stays allowed.
if printf '%s' "$cmd" | grep -qE '(^|[;&|(])[[:space:]]*sort([[:space:]]|$)' \
   && printf '%s' "$cmd" | grep -qE '[[:space:]](-[a-zA-Z]*o|--output)([[:space:]]|=|$)'; then
  deny "sort here must be read-only — no -o/--output (writes/overwrites a file). Pipe sort's output instead (... | sort ...), or write the file as a separate explicit step."
fi

exit 0
