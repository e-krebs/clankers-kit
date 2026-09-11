#!/usr/bin/env bash
# Runs the compose-hooks fixture cases and exits non-zero on any failure. The synthetic fragment
# set under frags/ exercises the composer alone; the freshness and Codex-invariant cases read the
# real fragments and the committed wiring files of this checkout.

set -u

fixtures_dir=$(CDPATH='' cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)
hooks_dir=$(CDPATH='' cd -P "$fixtures_dir/../.." && pwd)
root=$(CDPATH='' cd -P "$hooks_dir/../.." && pwd)
composer="$hooks_dir/compose-hooks.sh"
frags="$fixtures_dir/frags"
work=$(mktemp -d "${TMPDIR:-/tmp}/compose-hooks.XXXXXX")
trap 'rm -rf "$work"' EXIT

overall=0
pass() { printf 'PASS %s\n' "$1"; }
fail_case() { printf 'FAIL %s: %s\n' "$1" "$2"; overall=1; }

compose() {  # compose <claude out> <codex out or ""> <own> <fragments...>
  local claude="$1" codex="$2" own="$3"; shift 3
  if [ -n "$codex" ]; then
    bash "$composer" --local "$frags" --root /R --own "$own" --claude "$claude" --codex "$codex" "$@"
  else
    bash "$composer" --local "$frags" --root /R --own "$own" --claude "$claude" "$@"
  fi
}
good_frags=("$frags/hooks/hooks.json" "$frags/skills/alpha/hooks/hooks.json" "$frags/skills/beta/hooks/hooks.json")

# --- syntax ------------------------------------------------------------------------------------
if bash -n "$composer" 2>/dev/null; then pass syntax; else fail_case syntax "bash -n failed"; fi

# --- the synthetic set composes to the expected wiring for both agents ------------------------
if compose "$work/c.json" "$work/x.json" all "${good_frags[@]}" >/dev/null 2>"$work/err"; then
  if [ "$(jq -S . "$fixtures_dir/expected-claude.json")" = "$(jq -S .hooks "$work/c.json")" ]; then pass claude-matches-expected
  else fail_case claude-matches-expected "$(diff <(jq -S . "$fixtures_dir/expected-claude.json") <(jq -S .hooks "$work/c.json") | head -10)"; fi
  if [ "$(jq -S . "$fixtures_dir/expected-codex.json")" = "$(jq -S .hooks "$work/x.json")" ]; then pass codex-matches-expected
  else fail_case codex-matches-expected "$(diff <(jq -S . "$fixtures_dir/expected-codex.json") <(jq -S .hooks "$work/x.json") | head -10)"; fi
else
  fail_case compose-runs "$(cat "$work/err")"
fi

# --- event order is fixed, entries keep fragment order ----------------------------------------
order=$(jq -r '.hooks | keys_unsorted | join(",")' "$work/c.json" 2>/dev/null)
if [ "$order" = "SessionStart,SessionEnd,Notification,Stop,PreToolUse,UserPromptSubmit,PostToolUse" ]; then pass event-order
else fail_case event-order "$order"; fi

# --- the Codex arg lands on the Codex command only ---------------------------------------------
c_cmd=$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$work/c.json" 2>/dev/null)
x_cmd=$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$work/x.json" 2>/dev/null)
case "$x_cmd" in *'shared-c.sh" codex') x_ok=1 ;; *) x_ok=0 ;; esac
case "$c_cmd" in *'shared-c.sh"') c_ok=1 ;; *) c_ok=0 ;; esac
if [ "$x_ok" = 1 ] && [ "$c_ok" = 1 ]; then pass codex-arg-asymmetry; else fail_case codex-arg-asymmetry "claude: $c_cmd / codex: $x_cmd"; fi

# --- a second run changes nothing and says so --------------------------------------------------
before=$(cat "$work/c.json" "$work/x.json")
out=$(compose "$work/c.json" "$work/x.json" all "${good_frags[@]}" 2>&1)
after=$(cat "$work/c.json" "$work/x.json")
if [ "$before" = "$after" ] && [ "$(printf '%s\n' "$out" | grep -c unchanged)" = 2 ]; then pass idempotent
else fail_case idempotent "$out"; fi

# --- --own skills keeps foreign entries and other keys, replaces the skills entries ------------
skill_frags=("$frags/skills/alpha/hooks/hooks.json" "$frags/skills/beta/hooks/hooks.json")
cp "$fixtures_dir/seed-foreign.json" "$work/seed.json"
if compose "$work/seed.json" "" skills "${skill_frags[@]}" >/dev/null 2>"$work/err"; then
  err=""
  [ "$(jq -r .model "$work/seed.json")" = "keep-me" ] || err="model key lost"
  grep -q 'foreign.sh' "$work/seed.json" || err="${err:+$err; }foreign hook dropped"
  grep -q 'old-nudge.sh' "$work/seed.json" && err="${err:+$err; }stale skills entry kept"
  grep -q 'alpha-nudge.sh' "$work/seed.json" || err="${err:+$err; }composed entry missing"
  grep -q '"prompt"' "$work/seed.json" || err="${err:+$err; }foreign prompt hook (no command) dropped"
  n=$(jq '.hooks.PreToolUse | length' "$work/seed.json")
  [ "$n" = 2 ] || err="${err:+$err; }PreToolUse holds $n groups, expected 2 (foreign + beta-gate)"
  if [ -z "$err" ]; then pass own-skills; else fail_case own-skills "$err"; fi
  before=$(cat "$work/seed.json")
  out=$(compose "$work/seed.json" "" skills "${skill_frags[@]}" 2>&1)
  if [ "$before" = "$(cat "$work/seed.json")" ] && printf '%s' "$out" | grep -q unchanged; then pass own-skills-idempotent
  else fail_case own-skills-idempotent "$out"; fi
else
  fail_case own-skills "$(cat "$work/err")"
fi
# a shared fragment or an inline entry under --own skills would re-append on every run, so the composer refuses both
if compose "$work/seed.json" "" skills "${good_frags[@]}" >/dev/null 2>"$work/err"; then fail_case own-skills-rejects-shared-fragment "exit 0"
elif grep -q 'fragments only' "$work/err"; then pass own-skills-rejects-shared-fragment
else fail_case own-skills-rejects-shared-fragment "stderr: $(cat "$work/err")"; fi
if compose "$work/seed.json" "" skills "$frags/skills/bad-inline/hooks/hooks.json" >/dev/null 2>"$work/err"; then fail_case own-skills-rejects-inline "exit 0"
elif grep -q 'script hooks only' "$work/err"; then pass own-skills-rejects-inline
else fail_case own-skills-rejects-inline "stderr: $(cat "$work/err")"; fi
# --own all still takes an inline entry from a skill fragment
if compose "$work/g.json" "" all "$frags/skills/bad-inline/hooks/hooks.json" >/dev/null 2>"$work/err" && grep -q 'inline in a skill' "$work/g.json"; then pass own-all-takes-inline
else fail_case own-all-takes-inline "$(cat "$work/err")"; fi

# --- --own root: replaces what a fragment declares or what it wrote and lost, keeps the rest ---
root_frags=("$frags/hooks/root-shared.json" "$frags/skills/alpha/hooks/hooks.json" "$frags/skills/beta/hooks/hooks.json")
cp "$fixtures_dir/seed-root.json" "$work/root.json"
if compose "$work/root.json" "" root "${root_frags[@]}" >/dev/null 2>"$work/err"; then
  err=""
  [ "$(jq -r .model "$work/root.json")" = "keep-me" ] || err="model key lost"
  grep -q 'elsewhere.sh' "$work/root.json" || err="${err:+$err; }entry outside root dropped"
  grep -q 'my-extras/foo.sh' "$work/root.json" || err="${err:+$err; }undeclared entry under root dropped"
  grep -q '"prompt"' "$work/root.json" || err="${err:+$err; }command-less entry dropped"
  grep -q 'bash /R/hooks/shared-c.sh' "$work/root.json" || err="${err:+$err; }unquoted entry dropped"
  grep -q 'gone.sh' "$work/root.json" && err="${err:+$err; }stale shared entry kept"
  grep -q 'old-nudge.sh' "$work/root.json" && err="${err:+$err; }stale skill entry kept"
  grep -q 'shared-b.sh" notify' "$work/root.json" && err="${err:+$err; }arg-carrying declared entry kept"
  [ "$(grep -c 'shared-a.sh' "$work/root.json")" = 1 ] || err="${err:+$err; }shared-a present $(grep -c 'shared-a.sh' "$work/root.json") times"
  grep -q 'alpha-nudge.sh' "$work/root.json" || err="${err:+$err; }composed entry missing"
  [ "$(grep -c 'kept an entry under /R' "$work/err")" = 1 ] || err="${err:+$err; }expected one kept warning, got: $(cat "$work/err")"
  grep -q 'my-extras/foo.sh' "$work/err" || err="${err:+$err; }warning does not name the kept entry"
  [ "$(grep -c 'dropped a stale entry under /R' "$work/err")" = 2 ] || err="${err:+$err; }expected two dropped lines, got: $(cat "$work/err")"
  grep -q 'gone.sh' "$work/err" && grep -q 'old-nudge.sh' "$work/err" || err="${err:+$err; }dropped lines do not name both stale entries"
  if [ -z "$err" ]; then pass own-root; else fail_case own-root "$err"; fi
  before=$(cat "$work/root.json")
  out=$(compose "$work/root.json" "" root "${root_frags[@]}" 2>&1)
  if [ "$before" = "$(cat "$work/root.json")" ] && printf '%s' "$out" | grep -q unchanged; then pass own-root-idempotent
  else fail_case own-root-idempotent "$out"; fi
else
  fail_case own-root "$(cat "$work/err")"
fi
# no fragment at all strips the owned set and leaves everything else in place
cp "$fixtures_dir/seed-root.json" "$work/root0.json"
if compose "$work/root0.json" "" root >/dev/null 2>"$work/err"; then
  err=""
  for gone in shared-a.sh shared-b.sh gone.sh old-nudge.sh; do grep -q "$gone" "$work/root0.json" && err="${err:+$err; }$gone kept"; done
  for kept in elsewhere.sh my-extras/foo.sh '"prompt"' 'bash /R/hooks/shared-c.sh'; do grep -q "$kept" "$work/root0.json" || err="${err:+$err; }$kept dropped"; done
  [ "$(jq -r .model "$work/root0.json")" = "keep-me" ] || err="${err:+$err; }model key lost"
  if [ -z "$err" ]; then pass own-root-zero-fragments; else fail_case own-root-zero-fragments "$err"; fi
else
  fail_case own-root-zero-fragments "$(cat "$work/err")"
fi
# an inline entry would re-append on every run, from a skill fragment or a shared one alike
if compose "$work/root.json" "" root "$frags/skills/bad-inline/hooks/hooks.json" >/dev/null 2>"$work/err"; then fail_case own-root-rejects-inline "exit 0"
elif grep -q 'script hooks only' "$work/err"; then pass own-root-rejects-inline
else fail_case own-root-rejects-inline "stderr: $(cat "$work/err")"; fi
if compose "$work/root.json" "" root "${good_frags[@]}" >/dev/null 2>"$work/err"; then fail_case own-root-rejects-shared-inline "exit 0"
elif grep -q 'script hooks only' "$work/err"; then pass own-root-rejects-shared-inline
else fail_case own-root-rejects-shared-inline "stderr: $(cat "$work/err")"; fi
# a prompt hook has no command at all, so neither narrow mode could own it; --own all still takes it
for mode in root skills; do
  if compose "$work/root.json" "" "$mode" "$frags/skills/bad-prompt/hooks/hooks.json" >/dev/null 2>"$work/err"; then fail_case "own-$mode-rejects-prompt-entry" "exit 0"
  elif grep -q 'without a command' "$work/err"; then pass "own-$mode-rejects-prompt-entry"
  else fail_case "own-$mode-rejects-prompt-entry" "stderr: $(cat "$work/err")"; fi
done
if compose "$work/p.json" "" all "$frags/skills/bad-prompt/hooks/hooks.json" >/dev/null 2>"$work/err" && grep -q '"prompt"' "$work/p.json"; then pass own-all-takes-prompt-entry
else fail_case own-all-takes-prompt-entry "$(cat "$work/err")"; fi
# --own all still needs a fragment
if bash "$composer" --local "$frags" --root /R --own all --claude "$work/f.json" >/dev/null 2>&1; then fail_case own-all-needs-a-fragment "exit 0"; else pass own-all-needs-a-fragment; fi

# --- a write lands on the symlink target -------------------------------------------------------
mkdir -p "$work/real" "$work/link"
printf '{"hooks":{}}\n' > "$work/real/settings.json"
ln -s "$work/real/settings.json" "$work/link/settings.json"
if compose "$work/link/settings.json" "" all "${good_frags[@]}" >/dev/null 2>&1 \
  && [ -L "$work/link/settings.json" ] && grep -q 'shared-a.sh' "$work/real/settings.json"; then pass writes-through-symlink
else fail_case writes-through-symlink "symlink replaced or target not written"; fi

# --- failures: missing header, missing script, arguments in the command, bad flags --------------
expect_fail() {  # <case> <needle in stderr> <fragments...>
  local case_name="$1" needle="$2"; shift 2
  if compose "$work/f.json" "" all "$@" >/dev/null 2>"$work/err"; then fail_case "$case_name" "exit 0"
  elif grep -q "$needle" "$work/err"; then pass "$case_name"
  else fail_case "$case_name" "stderr: $(cat "$work/err")"; fi
}
expect_fail rejects-missing-header "missing '# codex" "$frags/bad-nohdr/hooks/hooks.json"
expect_fail rejects-missing-script "script not found" "$frags/bad-missing/hooks/hooks.json"
expect_fail rejects-args-in-command "arguments go in the header" "$frags/bad-args/hooks/hooks.json"
if bash "$composer" --own all --claude "$work/f.json" "${good_frags[@]}" >/dev/null 2>&1; then fail_case rejects-missing-root "exit 0"; else pass rejects-missing-root; fi
if bash "$composer" --root /R --own some --claude "$work/f.json" "${good_frags[@]}" >/dev/null 2>&1; then fail_case rejects-bad-own "exit 0"; else pass rejects-bad-own; fi

# --- the real wiring: freshness and Codex invariants ---------------------------------------------
# Only a fully composed checkout has these: the shared fragment hooks.json marks one, and a copy of
# this suite in a repo that composes a per-user subset (no hooks.json) skips the block.
real_frags=("$hooks_dir/hooks.json")
skill_frags=()
while IFS= read -r f; do skill_frags+=("$f"); done < <(find "$root/.agents/skills" -mindepth 3 -maxdepth 3 -path '*/hooks/hooks.json' 2>/dev/null | sort)
real_frags+=(${skill_frags[@]+"${skill_frags[@]}"})
claude_json="$root/.claude/settings.json"
codex_json="$root/.codex/user-hooks.json"
# the wiring files spell the install root their own way ($HOME/<path>/.agents), so read it back from
# the first script command instead of assuming this checkout's path: a worktree elsewhere still passes
install_root=$(jq -r '[.hooks[][].hooks[].command // "" | select(startswith("bash \""))] | .[0] // "" | split("\"") | (.[1] // "") | sub("/\\.agents/.*$"; "/.agents")' "$claude_json" 2>/dev/null || true)
case "$install_root" in */.agents) ;; *) install_root="" ;; esac
# a fully composed checkout whose wiring yields no root is a stale or broken wiring, never a skip
if [ ${#skill_frags[@]} -gt 0 ] && [ -f "$hooks_dir/hooks.json" ] && [ -z "$install_root" ]; then
  fail_case install-root-readable "could not read the install root from $claude_json"
fi
if [ ${#skill_frags[@]} -gt 0 ] && [ -f "$hooks_dir/hooks.json" ] && [ -n "$install_root" ]; then
  cp "$claude_json" "$work/real-claude.json"; cp "$codex_json" "$work/real-codex.json"
  if bash "$composer" --root "$install_root" --own all --claude "$work/real-claude.json" --codex "$work/real-codex.json" "${real_frags[@]}" >/dev/null 2>"$work/err"; then
    if [ "$(jq -S .hooks "$claude_json")" = "$(jq -S .hooks "$work/real-claude.json")" ]; then pass fresh-claude
    else fail_case fresh-claude "$(diff <(jq -S .hooks "$claude_json") <(jq -S .hooks "$work/real-claude.json") | head -20)"; fi
    if [ "$(jq -S .hooks "$codex_json")" = "$(jq -S .hooks "$work/real-codex.json")" ]; then pass fresh-codex
    else fail_case fresh-codex "$(diff <(jq -S .hooks "$codex_json") <(jq -S .hooks "$work/real-codex.json") | head -20)"; fi
  else
    fail_case fresh-compose-runs "$(cat "$work/err")"
  fi

  prefix="bash \"$install_root/"
  script_paths() {  # $1 = json file -> sorted unique script paths, arguments stripped
    jq -r --arg p "$prefix" '.hooks[][].hooks[].command | select(startswith($p)) | split("\"")[1]' "$1" | sort -u
  }
  script_hooks() { jq -r --arg p "$prefix" '[.hooks[][].hooks[].command | select(startswith($p))] | unique | length' "$1"; }
  # the selector matches every script hook: a widened path form must fail here, not pass vacuously
  n_codex=$(script_paths "$codex_json" | wc -l | tr -d ' ')
  if [ "$n_codex" -gt 0 ] && [ "$n_codex" = "$(script_hooks "$codex_json")" ]; then pass selector-covers-scripts
  else fail_case selector-covers-scripts "matched $n_codex of $(script_hooks "$codex_json")"; fi
  missing=$(comm -23 <(script_paths "$codex_json") <(script_paths "$claude_json"))
  if [ -z "$missing" ]; then pass scripts-subset-of-claude; else fail_case scripts-subset-of-claude "$missing"; fi

  # every script Codex runs says so in its header; every Claude-only one stays out
  leaked=""
  while IFS= read -r p; do
    local_path="$root/.agents/${p#"$install_root"/}"
    grep -qE '^# codex: yes' "$local_path" || leaked="$leaked $p"
  done < <(script_paths "$codex_json")
  if [ -z "$leaked" ]; then pass no-claude-only-scripts; else fail_case no-claude-only-scripts "$leaked"; fi

  codex_events='PreToolUse PostToolUse PermissionRequest UserPromptSubmit SessionStart SessionEnd Stop PreCompact PostCompact SubagentStart SubagentStop Interrupt'
  bad_events=$(jq -r --arg ok "$codex_events" '.hooks | keys[] as $e | select(($ok | split(" ") | index($e)) == null) | $e' "$codex_json")
  if [ -z "$bad_events" ]; then pass known-events; else fail_case known-events "$bad_events"; fi
  if jq -r --arg ok "$codex_events" '.hooks | keys[] as $e | select(($ok | split(" ") | index($e)) == null) | $e' <<< '{"hooks":{"Bogus":[]}}' | grep -q Bogus; then pass known-events-flags-unknown; else fail_case known-events-flags-unknown "Bogus was not flagged"; fi
  stray=$(jq -r '.hooks | to_entries[] | select(.key == "UserPromptSubmit" or .key == "Stop" or .key == "Interrupt" or .key == "PermissionRequest") | .value[] | select(has("matcher")) | .matcher' "$codex_json")
  if [ -z "$stray" ]; then pass no-matcher-on-prompt-and-stop; else fail_case no-matcher-on-prompt-and-stop "$stray"; fi

  # Codex compiles a tool matcher as a regex, probed 2026-09-11 with a throwaway config override:
  # an anchored "^(Bash|nonesuch)$" fired on a shell call, a literal "nonesuch-literal" did not,
  # and a matcher-less group saw every tool. So a Codex tool matcher is either the recorded shell
  # tool name or an anchored MCP tool-name pattern; any other name is a Claude-only tool leaking.
  shell_tool=$(jq -r '.tool_name' "$root/.agents/skills/pr-followup/hooks/fixtures/push-nudge/sample-pretooluse-shell.json" 2>/dev/null || echo Bash)
  tool_script_paths() {  # $1 = json file -> script paths inside Pre/PostToolUse groups
    jq -r --arg p "$prefix" '(.hooks.PreToolUse[]?, .hooks.PostToolUse[]?) | .hooks[].command | select(startswith($p)) | split("\"")[1]' "$1" | sort -u
  }
  stray_matchers=""
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    [ "$m" = "$shell_tool" ] && continue
    case "$m" in '^mcp__'*) continue ;; esac
    stray_matchers="$stray_matchers $m"
  done < <(jq -r '.hooks.PreToolUse[]?, .hooks.PostToolUse[]? | .matcher // empty' "$codex_json" | sort -u)
  if [ -z "$stray_matchers" ]; then pass codex-tool-matchers
  else fail_case codex-tool-matchers "neither the shell tool name nor an anchored mcp pattern:$stray_matchers"; fi

  # a matcher-less Codex tool group sees every tool, which no fragment here asks for
  bare=$(jq -r '.hooks.PreToolUse[]?, .hooks.PostToolUse[]? | select((.matcher // "") == "") | .hooks[].command' "$codex_json")
  if [ -z "$bare" ]; then pass codex-tool-groups-carry-a-matcher; else fail_case codex-tool-groups-carry-a-matcher "$bare"; fi

  # reverse parity: every script Codex runs under a tool matcher still carries one on the Claude
  # side. Without this, a composer bug that dropped a matcher from both outputs would pass every
  # assertion above while quietly turning a narrow hook into an every-tool hook.
  unmatched=""
  while IFS= read -r p; do
    [ -n "$p" ] || continue
    n_bare=$(jq -r --arg s "$p" '[(.hooks.PreToolUse[]?, .hooks.PostToolUse[]?) | select(any(.hooks[]; (.command // "") | contains($s))) | (.matcher // "")] | map(select(. == "")) | length' "$claude_json")
    [ "${n_bare:-0}" = "0" ] || unmatched="$unmatched $p"
  done < <(tool_script_paths "$codex_json")
  if [ -z "$unmatched" ]; then pass claude-tool-groups-keep-their-matcher; else fail_case claude-tool-groups-keep-their-matcher "$unmatched"; fi

  end_to=$(jq -r '[.hooks.SessionEnd[].hooks[].timeout] | max' "$codex_json")
  if [ "$end_to" -le 3 ] 2>/dev/null; then pass sessionend-timeout-le-3; else fail_case sessionend-timeout-le-3 "max timeout $end_to"; fi

  fbp=$(jq -r '.hooks.PreToolUse[].hooks[].command | select(test("forbid-bash-patterns"))' "$codex_json")
  case "$fbp" in *'forbid-bash-patterns.sh" codex') pass codex-arg-on-forbid-bash-patterns ;; *) fail_case codex-arg-on-forbid-bash-patterns "$fbp" ;; esac

  # every referenced script exists and parses in this checkout
  syntax_ok=1
  while IFS= read -r p; do
    local_path="$root/.agents/${p#"$install_root"/}"
    if ! { [ -f "$local_path" ] && bash -n "$local_path" 2>/dev/null; }; then
      syntax_ok=0; fail_case "exists+parses $p" "missing or bash -n failed"
    fi
  done < <(script_paths "$claude_json")
  [ "$syntax_ok" = 1 ] && pass scripts-exist-and-parse

  # a moved nudge finds the shared library on its own, from a bare checkout, with the env unset
  nudge="$root/.agents/skills/pr-merge/hooks/merge-nudge.sh"
  if [ -f "$nudge" ]; then
    out=$(env -u AGENTS_HOOKS_LIB HOME="$work/nohome" bash "$nudge" <<< '{"session_id":"s","prompt":"merge the PR","hook_event_name":"UserPromptSubmit"}' 2>/dev/null)
    if printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext | test("pr-merge")' >/dev/null 2>&1; then pass lib-found-from-bare-checkout
    else fail_case lib-found-from-bare-checkout "output: $out"; fi
  fi
fi

exit $overall
