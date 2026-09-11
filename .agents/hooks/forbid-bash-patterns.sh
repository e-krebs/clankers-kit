#!/usr/bin/env bash
# PreToolUse(Bash) gate: deny forbidden command patterns.
# Wired via ~/.claude/settings.json -> PreToolUse[matcher=Bash] and, with a "codex" mode arg,
# via ~/.codex/hooks.json. Every rule runs in both modes for now: the arg only reserves the
# seam for relaxing Codex later. The npx/npm/yarn bin/script and yarn --cwd rules fire only
# when the repo root of the payload's cwd holds a yarn.lock.
#
# Matching is TEXTUAL (line-oriented grep), not a shell parse: a forbidden token
# in a quoted string / commit message / heredoc body can still trip a rule. That's
# an accepted limitation — the goal is catching habitual real invocations, not
# defeating evasion.
#
# Forbidden commands are grouped so each sublist keeps a targeted message — see the
# deny_tools / deny_yarn_bins helpers below. To forbid more, add a command to a group's
# list or add a new helper call with its own message. Plain alphanumeric words only:
# list entries are interpolated raw into an ERE, so regex metacharacters (. + * [ etc.)
# are NOT escaped and would mis-match.
# codex: yes args=codex

mode="${1:-claude}"
case "$mode" in
  claude|codex) ;;
  *) mode=claude ;;
esac

input=$(cat)

# shellcheck source=lib/hook-log.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-log.sh"
HOOK_SESSION=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0   # fail open
[ -z "$cmd" ] && exit 0

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$cwd" ] || cwd=$PWD
repo_root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$cwd")
yarn_repo=0; [ -f "$repo_root/yarn.lock" ] && yarn_repo=1

deny() {  # $1 = reason shown back to Claude, $2 = rule id
  hook_log deny "$2"
  jq -nc --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

deny_tools() {       # $1 = space-separated commands (command position), $2 = reason, $3 = rule id
  local list="$1" msg="$2" rule="$3" t
  for t in $list; do
    printf '%s' "$cmd" | grep -qE "(^|[;&|(])[[:space:]]*${t}([[:space:]]|\$)" && deny "$msg" "$rule"
  done
}

deny_yarn_bins() {   # bare 'yarn <bin>' (NOT 'yarn run <bin>'); $1 = bins, $2 = reason, $3 = rule id
  local list="$1" msg="$2" rule="$3" b
  for b in $list; do
    printf '%s' "$cmd" | grep -qE "(^|[;&|(])[[:space:]]*yarn[[:space:]]+${b}([[:space:]]|\$)" && deny "$msg" "$rule"
  done
}

deny_yarn_scripts() { # 'yarn run <script>' (use bare 'yarn <script>'); $1 = scripts, $2 = reason, $3 = rule id
  local list="$1" msg="$2" rule="$3" s
  for s in $list; do
    printf '%s' "$cmd" | grep -qE "(^|[;&|(])[[:space:]]*yarn[[:space:]]+run[[:space:]]+${s}([[:space:]]|\$)" && deny "$msg" "$rule"
  done
}

# 1. cd in command position (start, or after ; & | or a subshell paren)
if printf '%s' "$cmd" | grep -qE '(^|[;&|(])[[:space:]]*cd([[:space:]]|$)'; then
  deny "Don't use cd. git/gh/yarn and repo scripts already run in the working tree; /tmp is an additionalDirectory. Run the command without a cd prefix." "cd"
fi

# 2. git/gh -C/-c global flag in command position (-C <path> dir redirect, -c <k>=<v> inline config)
#    right after the binary — NOT 'git log -C' / 'git show -c' (those follow a subcommand), and NOT
#    a mention inside a quoted string.
if printf '%s' "$cmd" | grep -qE '(^|[;&|(])[[:space:]]*(git|gh)[[:space:]]+-[Cc]([[:space:]]|$)'; then
  deny "Don't pass a git/gh global flag before the subcommand: no -C <path> (cwd is already in the repo) and no -c <key>=<val> inline config override. Run plain git/gh." "git-flag"
fi

# 3. forbidden CLI tools, grouped so each sublist keeps a targeted message
deny_tools "awk" "\`awk\` is forbidden here — use the Read/Grep/Glob tools (or another allowed command) instead." "awk"
deny_tools "sed cat"  "Use the Read tool (offset/limit for line ranges) or Grep for searching — not sed/cat. For in-place edits use the Edit tool." "sed-cat"
# npx/npm only make sense as a rule in a yarn repo (they're the point of comparison with yarn).
if [ "$yarn_repo" -eq 1 ]; then
  deny_tools "npx"      "Don't use npx — run 'yarn <script>' or 'yarn run <bin>' instead." "npx"
  deny_tools "npm"      "Don't use npm — this is a yarn project. Use yarn (e.g. 'yarn list', 'yarn add <pkg>', 'yarn install')." "npm"
fi

# 4. echo must be a literal string. 'echo:*' is allowlisted, so this is the safety net: deny any echo
#    that expands a variable/substitution ($VAR / ${V} / $(...) / `...`) — echo "$TOKEN" leaks secrets.
#    Exception: the canonical $? sentinels (echo "$?" / echo $? / "exit=$?" / "exit: $?").
if printf '%s' "$cmd" | grep -qE '(^|[;&|(])[[:space:]]*echo[[:space:]][^;|&]*(\$|`)' \
   && ! printf '%s' "$cmd" | grep -qE 'echo[[:space:]]+("\$\?"|\$\?|"exit=\$\?"|"exit: \$\?")'; then
  deny "echo must be a literal string here — don't expand variables or substitutions (echo \"\$VAR\" / \$(...) can leak secrets). The Bash tool already reports exit status; for an exit sentinel use the allowlisted echo \"\$?\" verbatim." "echo"
fi

# 5. bare 'yarn <bin>' for bins that must use 'yarn run <bin>' (allowed: 'yarn run jest' /
#    'yarn run eslint', and the scripts 'yarn test' / 'yarn lint'). Per-bin message.
# These rules only make sense in a repo whose root holds a yarn.lock.
if [ "$yarn_repo" -eq 1 ]; then
  deny_yarn_bins "jest"   "Don't run bare 'yarn jest' — use 'yarn test' (script) or 'yarn run jest <paths>' (bin, for scoping)." "yarn-bin"
  deny_yarn_bins "eslint" "Don't run bare 'yarn eslint' — use 'yarn lint' (script) or 'yarn run eslint <paths>' (bin, for scoping)." "yarn-bin"
  deny_yarn_scripts "type-check test lint" "Don't run 'yarn run <script>' for a package.json script — use the bare form: 'yarn type-check' / 'yarn test' / 'yarn lint'." "yarn-script"
fi

# 6. shell loops (for/while/until) can't be allowlisted, so they always prompt. Command-position only,
#    so 'git for-each-ref' / a quoted "for ..." / a path are not matched.
if printf '%s' "$cmd" | grep -qE '(^|[;&|(])[[:space:]]*(for|while|until)([[:space:]]|\()'; then
  deny "Don't use for/while/until loops — they can't be allowlisted (so they always prompt). Run the command as separate Bash calls (issue it N times); label the runs in your message, not with echo." "loop"
fi

# 7. xargs runs an arbitrary command and bypasses the separator-anchored rules above (the inner
#    command sits after a space, not a separator), so deny it unless that command is known-safe.
XARGS_OK='grep|wc|ls'   # allowed inner commands (read-only); extend as an alternation, e.g. 'grep|wc|ls'
if printf '%s' "$cmd" | grep -qE '(^|[;&|(])[[:space:]]*xargs([[:space:]]|$)' \
   && ! printf '%s' "$cmd" | grep -qE "xargs[[:space:]]+(-[^[:space:]]+[[:space:]]+)*(${XARGS_OK})([[:space:]]|\$)"; then
  deny "xargs runs an arbitrary command and bypasses these guards — only 'xargs grep', 'xargs wc' and 'xargs ls' are allowed. For batch work, search with the Grep tool or run an explicit per-target command." "xargs"
fi

# 8. find is read-only EXCEPT its action primaries: -exec/-execdir/-ok/-okdir run an arbitrary
#    command, -delete removes files, -fprint/-fprintf/-fls write files. 'find:*' is allowlisted, so
#    deny those forms here. Command-position find only; the alternation also covers -execdir (via
#    -exec? no — listed), -fprintf/-fprint0. NOT the read-only -print/-printf/-print0/-ls.
if printf '%s' "$cmd" | grep -qE '(^|[;&|(])[[:space:]]*find([[:space:]]|$)' \
   && printf '%s' "$cmd" | grep -qE '[[:space:]]-(exec|execdir|ok|okdir|delete|fprint|fprintf|fprint0|fls)([[:space:]]|$)'; then
  deny "find here must be read-only — no -exec/-execdir/-ok/-okdir (runs a command), -delete (removes files), or -fprint/-fprintf/-fls (writes files). Use find for traversal only, or run the action as a separate explicit command." "find"
fi

# 9. yarn --cwd runs yarn in another directory — same cwd-redirect concern as rule 1 (cd) and
#    rule 2 (git -C). Command-position yarn carrying a --cwd flag (--cwd <dir> or --cwd=<dir>).
# Only relevant in a repo whose root holds a yarn.lock.
if [ "$yarn_repo" -eq 1 ]; then
  if printf '%s' "$cmd" | grep -qE '(^|[;&|(])[[:space:]]*yarn([[:space:]]|$)' \
     && printf '%s' "$cmd" | grep -qE '[[:space:]]--cwd([[:space:]]|=|$)'; then
    deny "Don't use 'yarn --cwd <dir>' to run yarn elsewhere — yarn already runs in the working tree. Run plain yarn from the directory you need (/tmp is an additionalDirectory)." "yarn-cwd"
  fi
fi

# 9.5. python is forbidden EXCEPT to run a committed repo script. Inline code (-c), module runs
#      (-m), stdin (-) and bare REPLs are denied; the carve-out requires every python invocation's
#      first argument to be an existing, git-tracked *.py file (checked in that file's own repo,
#      so scripts in other repos — e.g. internal-skills' gen-showcase.py — stay runnable).
#      Not a deny_tools call: the carve-out needs the filesystem + git checks below, which the
#      grep-only helpers can't express.
if printf '%s' "$cmd" | grep -qE '(^|[;&|(])[[:space:]]*python[23]?([[:space:]]|$)'; then
  n_inv=$(printf '%s' "$cmd" | grep -oE '(^|[;&|(])[[:space:]]*python[23]?([[:space:]]|$)' | grep -c '')
  n_ok=0
  while IFS= read -r m; do
    first=${m##*[[:space:]]}
    first=${first%\"}; first=${first#\"}; first=${first%\'}; first=${first#\'}
    case "$first" in
      *.py)
        if [ -f "$first" ] && git -C "$(dirname "$first")" ls-files --error-unmatch "$(basename "$first")" >/dev/null 2>&1; then
          n_ok=$((n_ok+1))
        fi
        ;;
    esac
  done < <(printf '%s' "$cmd" | grep -oE '(^|[;&|(])[[:space:]]*python[23]?[[:space:]]+[^[:space:]]+')
  if [ "$n_inv" -gt "$n_ok" ]; then
    deny "python is forbidden here — no inline -c one-liners, -m module runs, or ad-hoc scripts. The only allowed form is 'python3 <path>.py' where the script is committed in its repo. Use jq/node or the dedicated tools instead." "python"
  fi
fi

# 10. sort is read-only EXCEPT -o/--output, which writes (and can clobber) a file. 'sort:*' is
#     allowlisted, so deny the output-writing forms here. The -o hunt is confined to the sort
#     segment itself (up to the next ; | &), so a '-o' elsewhere in the pipeline (grep -o | sort)
#     doesn't false-positive. Covers a short-flag cluster ending in -o (e.g. -uo).
if printf '%s' "$cmd" | grep -oE '(^|[;&|(])[[:space:]]*sort[^;|&]*' \
   | grep -qE '[[:space:]](-[a-zA-Z]*o|--output)([[:space:]]|=|$)'; then
  deny "sort here must be read-only — no -o/--output (writes/overwrites a file). Pipe sort's output instead (... | sort ...), or write the file as a separate explicit step." "sort"
fi

exit 0
