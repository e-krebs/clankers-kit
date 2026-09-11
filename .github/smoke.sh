#!/usr/bin/env bash
# The CI smoke run: setup.sh and uninstall.sh against throwaway HOMEs and repo copies, on the
# checkout it runs from. Every case asserts the state it leaves behind. Exit 1 on the first miss.
# Run locally with: bash .github/smoke.sh   (it never touches your real ~/.claude)
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
tmp="$(cd "$(mktemp -d)" && pwd -P)"   # canonical: setup.sh resolves symlinks (/var -> /private/var on macOS)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "smoke: FAIL — $*" >&2; exit 1; }
pass() { echo "smoke: ok — $*"; }

copy_repo() {                       # $1 = destination; a copy without .git, like --sandbox makes
  cp -R "$repo" "$1"
  rm -rf "$1/.git" "$1/.claude/worktrees"
}

links_of() {                        # $1 = home -> "link -> target" lines for the three homes, sorted
  local l
  while IFS= read -r l; do printf '%s -> %s\n' "${l#"$1"/}" "$(readlink "$l")"; done \
    < <(find "$1/.claude" "$1/.agents" "$1/.codex" -type l 2>/dev/null | sort)
}

# --- 1. default install for both agents --------------------------------------------------
K="$tmp/kit"; H="$tmp/home"
copy_repo "$K"; mkdir -p "$H/.claude/hooks"
# a real ~/.claude/hooks with one colliding file and one of the user's own: merged, then linked
printf '#!/usr/bin/env bash\necho a different play-sound\n' > "$H/.claude/hooks/play-sound.sh"
printf '#!/usr/bin/env bash\necho mine\n' > "$H/.claude/hooks/mine.sh"
HOME="$H" bash "$K/setup.sh" --yes --no-private --name CI --role Tester --agents claude,codex > "$tmp/install.log" 2>&1 || { cat "$tmp/install.log"; fail "default install exited non-zero"; }
cat "$tmp/install.log"
grep -q 'play-sound.sh is shadowed' "$tmp/install.log" || fail "the colliding hook was not reported as shadowed"
[ -f "$K/.agents/hooks/mine.sh" ] || fail "the user's own hook was not merged into the repo"
grep -q 'a different play-sound' "$K/.agents/hooks/play-sound.sh" && fail "the kit's play-sound.sh was overwritten"
for l in .claude/settings.json .claude/CLAUDE.md .claude/hooks .claude/projects .agents/workflow-profiles .codex/AGENTS.md .codex/hooks.json; do
  [ -L "$H/$l" ] || fail "$l is not a symlink"
done
[ "$(readlink "$H/.claude/hooks")" = "$K/.agents/hooks" ] || fail ".claude/hooks points at $(readlink "$H/.claude/hooks")"
[ "$(readlink "$H/.claude/CLAUDE.md")" = "$K/.agents/AGENTS.md" ] || fail ".claude/CLAUDE.md points at $(readlink "$H/.claude/CLAUDE.md")"
[ "$(readlink "$H/.codex/AGENTS.md")" = "$K/.agents/AGENTS.md" ] || fail ".codex/AGENTS.md points at $(readlink "$H/.codex/AGENTS.md")"
for s in changes-to-pr pr-followup rebase-branch ticket-kickoff typescript-tips; do
  [ -L "$H/.claude/skills/$s" ] || fail ".claude/skills/$s missing"
  [ -L "$H/.agents/skills/$s" ] || fail ".agents/skills/$s missing"
done
[ -f "$K/.agents/AGENTS.md" ] || fail ".agents/AGENTS.md was not generated"
grep -q 'About CI' "$K/.agents/AGENTS.md" || fail "AGENTS.md does not carry the name"
jq -e . "$H/.claude/settings.json" >/dev/null || fail "settings.json is not valid JSON"
jq -e . "$H/.codex/hooks.json" >/dev/null || fail ".codex/hooks.json is not valid JSON"
jq -e '.permissions.allow | index("Bash(git status:*)")' "$H/.claude/settings.json" >/dev/null || fail "allowlist preset not applied"
jq -e '[.hooks.PreToolUse[].hooks[].command] | index("bash \"$HOME/.claude/hooks/forbid-bash-patterns.sh\"")' "$H/.claude/settings.json" >/dev/null || fail "enforcement hooks not composed into settings.json"
jq -e '[.hooks.PreToolUse[].hooks[].command] | index("bash \"$HOME/.claude/hooks/forbid-bash-patterns.sh\" codex")' "$H/.codex/hooks.json" >/dev/null || fail "the Codex wiring lacks forbid-bash-patterns with its codex arg"
jq -e '[.hooks[][].hooks[].command] | any(contains("forbid-verbose-comments"))' "$H/.codex/hooks.json" >/dev/null && fail "a Claude-only hook leaked into the Codex wiring"
jq -e '.hooks.Notification[0].matcher == "permission_prompt"' "$H/.claude/settings.json" >/dev/null || fail "Notification group missing from settings.json"
jq -e '.hooks.PermissionRequest[0] | has("matcher") | not' "$H/.codex/hooks.json" >/dev/null || fail "Codex PermissionRequest group missing or still carries a matcher"
jq -e '[.hooks[][].hooks[].command] | any(contains("skills/"))' "$H/.claude/settings.json" >/dev/null && fail "a skill hook was wired with the toggle off"
pass "default install for claude,codex"

# --- 2. an identical re-run changes nothing --------------------------------------------------
before_settings="$(jq -S . "$H/.claude/settings.json")"
before_links="$(links_of "$H")"
HOME="$H" bash "$K/setup.sh" --yes --no-private --agents claude,codex > "$tmp/rerun.log"
[ "$(jq -S . "$H/.claude/settings.json")" = "$before_settings" ] || fail "re-run changed settings.json"
[ "$(links_of "$H")" = "$before_links" ] || { diff <(printf '%s\n' "$before_links") <(links_of "$H") >&2 || true; cat "$tmp/rerun.log" >&2; fail "re-run changed the links"; }
grep -q 'settings    unchanged' "$tmp/rerun.log" || { cat "$tmp/rerun.log" >&2; fail "re-run rewrote settings.json"; }
pass "identical re-run"

# --- 3. --without drops a row and deactivates its skill ------------------------------------------
HOME="$H" bash "$K/setup.sh" --yes --no-private --agents claude,codex --without typescript-tips > /dev/null
[ ! -e "$H/.claude/skills/typescript-tips" ] || fail "--without left ~/.claude/skills/typescript-tips"
[ ! -e "$H/.agents/skills/typescript-tips" ] || fail "--without left ~/.agents/skills/typescript-tips"
[ -L "$H/.claude/skills/rebase-branch" ] || fail "--without dropped an unrelated skill"
pass "--without deactivates a skill"

# --- 3b. --without on a link row restores a real copy ----------------------------------------
# canonical-memory requires memories, so dropping memories alone re-checks it: both go
HOME="$H" bash "$K/setup.sh" --yes --no-private --agents claude,codex --without memories > "$tmp/without-mem.log" 2>&1
grep -q 'kept on.*memories (required by canonical-memory)' "$tmp/without-mem.log" || fail "--without memories alone should be re-checked by canonical-memory"
[ -L "$H/.claude/projects" ] || fail "--without memories alone unlinked a required row"
HOME="$H" bash "$K/setup.sh" --yes --no-private --agents claude,codex --without memories,canonical-memory > /dev/null 2>&1
jq -e '[.hooks[][].hooks[].command] | any(contains("canonical-memory"))' "$H/.claude/settings.json" >/dev/null && fail "--without canonical-memory left its hook wired"
{ [ ! -L "$H/.claude/projects" ] && [ -d "$H/.claude/projects" ]; } || fail "--without memories left the link"
[ -f "$H/.claude/projects/README.md" ] || fail "--without memories lost the content"
[ -L "$H/.claude/hooks" ] || fail "--without memories touched the core links"
# a re-run seeds from disk, so the unlinked row stays off until named again
HOME="$H" bash "$K/setup.sh" --yes --no-private --agents claude,codex \
  --components memories,workflow-profiles,instructions,allowlist,enforcement,notification,session-cleanup,canonical-memory,changes-to-pr,pr-followup,rebase-branch,ticket-kickoff,typescript-tips > /dev/null
[ -L "$H/.claude/projects" ] || fail "re-selecting memories did not relink (a real dir now merges into the repo first)"
pass "--without unlinks a link row"

# --- 3c. --without on a hooks row drops its entries from both wiring files ---------------------
HOME="$H" bash "$K/setup.sh" --yes --no-private --agents claude,codex --without notification > /dev/null
jq -e '[.hooks[][].hooks[].command] | any(contains("play-sound"))' "$H/.claude/settings.json" >/dev/null && fail "--without notification left play-sound in settings.json"
jq -e '[.hooks[][].hooks[].command] | any(contains("play-sound"))' "$H/.codex/hooks.json" >/dev/null && fail "--without notification left play-sound in the Codex wiring"
jq -e '[.hooks[][].hooks[].command] | any(contains("forbid-bash-patterns"))' "$H/.claude/settings.json" >/dev/null || fail "--without notification dropped an unrelated hook"
HOME="$H" bash "$K/setup.sh" --yes --no-private --agents claude,codex \
  --components memories,workflow-profiles,instructions,allowlist,enforcement,notification,session-cleanup,canonical-memory,changes-to-pr,pr-followup,rebase-branch,ticket-kickoff,typescript-tips > /dev/null
jq -e '[.hooks[][].hooks[].command | select(contains("play-sound"))] | length == 2' "$H/.claude/settings.json" >/dev/null || fail "re-selecting notification did not wire play-sound twice (Notification + Stop)"
pass "--without drops a hooks row"

# --- 4. uninstall: no link resolves into the repo, real files remain ---------------------------
HOME="$H" bash "$K/uninstall.sh" --yes
while IFS= read -r l; do
  case "$(readlink "$l")" in "$K"*) fail "$l still points into the repo" ;; esac
done < <(find "$H" -type l)
{ [ ! -L "$H/.claude/settings.json" ] && [ -f "$H/.claude/settings.json" ]; } || fail "settings.json not restored as a file"
{ [ ! -L "$H/.claude/hooks" ] && [ -d "$H/.claude/hooks" ]; } || fail "hooks not restored as a dir"
[ -f "$H/.claude/hooks/forbid-bash-patterns.sh" ] || fail "hooks content not restored"
{ [ ! -L "$H/.claude/CLAUDE.md" ] && [ -f "$H/.claude/CLAUDE.md" ]; } || fail "CLAUDE.md not restored as a file"
{ [ ! -L "$H/.codex/AGENTS.md" ] && [ -f "$H/.codex/AGENTS.md" ]; } || fail ".codex/AGENTS.md not restored as a file"
[ ! -e "$H/.claude/skills/rebase-branch" ] || fail "a kit skill link survived uninstall"
jq -e . "$H/.claude/settings.json" >/dev/null || fail "restored settings.json is not valid JSON"
jq -e '[.hooks[][].hooks[].command] | any(contains("skills/"))' "$H/.claude/settings.json" >/dev/null && fail "uninstall left a per-skill hook entry"
jq -e '[.hooks[][].hooks[].command] | any(contains("forbid-bash-patterns"))' "$H/.claude/settings.json" >/dev/null || fail "uninstall dropped the shared hooks from the restored settings.json"
pass "uninstall"

# --- 5. migration from the pre-.agents layout ------------------------------------------------------
M="$tmp/mig"; MH="$tmp/mig-home"
copy_repo "$M"; mkdir -p "$MH/.claude/skills" "$M/.claude/hooks" "$M/.claude/skills/my-skill"
printf '# About Old\n\n## Role\n\n- Migrated\n' > "$M/.claude/CLAUDE.md"
printf '#!/usr/bin/env bash\necho mine\n' > "$M/.claude/hooks/mine.sh"
printf '#!/usr/bin/env bash\necho a different play-sound\n' > "$M/.claude/hooks/play-sound.sh"
cp "$M/.agents/hooks/forbid-bash-patterns.sh" "$M/.claude/hooks/forbid-bash-patterns.sh"   # identical: no backup
printf -- '---\nname: my-skill\ndescription: mine\n---\n' > "$M/.claude/skills/my-skill/SKILL.md"
cat > "$M/.claude/settings.json" <<EOF
{
  "permissions": { "allow": ["Bash(git status:*)", "Bash(my-tool:*)"] },
  "model": "opus",
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [ { "type": "command", "command": "bash \"\$HOME/.claude/hooks/forbid-bash-patterns.sh\"" } ] },
      { "matcher": "Write|Edit", "hooks": [ { "type": "command", "command": "bash \"\$HOME/.claude/hooks/forbid-verbose-comments.sh\"" } ] },
      { "matcher": "Bash", "hooks": [ { "type": "command", "command": "bash \"\$HOME/my-extras/foo.sh\"" } ] }
    ],
    "Notification": [
      { "matcher": "permission_prompt", "hooks": [ { "type": "command", "command": "bash \"\$HOME/.claude/hooks/play-sound.sh\" notify" } ] }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": "bash \"\$HOME/.claude/hooks/play-sound.sh\" stop" } ] }
    ]
  }
}
EOF
ln -s "$M/.claude/settings.json" "$MH/.claude/settings.json"
ln -s "$M/.claude/CLAUDE.md" "$MH/.claude/CLAUDE.md"
ln -s "$M/.claude/hooks" "$MH/.claude/hooks"
ln -s "$M/.claude/skills/typescript-tips" "$MH/.claude/skills/typescript-tips"   # dangling: the dir moved with the pull
ln -s "$M/.claude/skills/my-skill" "$MH/.claude/skills/my-skill"
HOME="$MH" bash "$M/setup.sh" --yes --no-private --agents claude > "$tmp/mig.log"
[ "$(readlink "$MH/.claude/hooks")" = "$M/.agents/hooks" ] || fail "migration: ~/.claude/hooks points at $(readlink "$MH/.claude/hooks")"
[ "$(readlink "$MH/.claude/CLAUDE.md")" = "$M/.agents/AGENTS.md" ] || fail "migration: ~/.claude/CLAUDE.md points at $(readlink "$MH/.claude/CLAUDE.md")"
[ "$(readlink "$MH/.claude/skills/typescript-tips")" = "$M/.agents/skills/typescript-tips" ] || fail "migration: the dangling skill link was not retargeted"
{ [ -f "$M/.agents/AGENTS.md" ] && grep -q 'About Old' "$M/.agents/AGENTS.md"; } || fail "migration: CLAUDE.md did not move to AGENTS.md"
[ ! -e "$M/.claude/CLAUDE.md" ] || fail "migration: .claude/CLAUDE.md is still there"
[ -f "$M/.agents/hooks/mine.sh" ] || fail "migration: mine.sh was not carried over"
[ -f "$M/.agents/hooks/play-sound.sh.clankers-bak" ] || fail "migration: the differing play-sound.sh was not backed up"
grep -q 'a different play-sound' "$M/.agents/hooks/play-sound.sh.clankers-bak" || fail "migration: the backup holds the wrong content"
[ ! -e "$M/.agents/hooks/forbid-bash-patterns.sh.clankers-bak" ] || fail "migration: an identical file was backed up"
[ ! -d "$M/.claude/hooks" ] || fail "migration: .claude/hooks was not removed"
[ -f "$M/.agents/skills/my-skill/SKILL.md" ] || fail "migration: my-skill was not carried over"
[ ! -d "$M/.claude/skills" ] || fail "migration: .claude/skills was not removed"
[ "$(readlink "$MH/.claude/skills/my-skill")" = "$M/.agents/skills/my-skill" ] || fail "migration: my-skill link points at $(readlink "$MH/.claude/skills/my-skill")"
jq -e '.permissions.allow | index("Bash(my-tool:*)")' "$M/.claude/settings.json" >/dev/null || fail "migration: a foreign allow entry was dropped"
jq -e '.model == "opus"' "$M/.claude/settings.json" >/dev/null || fail "migration: a foreign scalar was dropped"
jq -e '[.hooks.PreToolUse[].hooks[].command] | any(contains("my-extras/foo.sh"))' "$M/.claude/settings.json" >/dev/null || fail "migration: a foreign hook entry was dropped"
n="$(jq '[.hooks[][].hooks[].command | select(contains("forbid-bash-patterns"))] | length' "$M/.claude/settings.json")"
[ "$n" = 1 ] || fail "migration: forbid-bash-patterns is wired $n times"
jq -e '[.hooks[][].hooks[].command] | any(endswith("play-sound.sh\" notify") or endswith("play-sound.sh\" stop"))' "$M/.claude/settings.json" >/dev/null && fail "migration: a pre-port play-sound entry with an argument survived"
n="$(jq '[.hooks[][].hooks[].command | select(contains("play-sound"))] | length' "$M/.claude/settings.json")"
[ "$n" = 2 ] || fail "migration: play-sound is wired $n times, expected 2"
jq -e '.hooks.PreToolUse[] | select(any(.hooks[]; .command | contains("forbid-verbose-comments"))) | .matcher == "Write|Edit|MultiEdit"' "$M/.claude/settings.json" >/dev/null || fail "migration: the pre-port Write|Edit entry was not replaced by the fragment's"
grep -q 'compose: enforcement,notification' "$tmp/mig.log" || fail "migration: the pre-port presets did not seed their hooks rows on"
HOME="$MH" bash "$M/setup.sh" --yes --no-private --agents claude > "$tmp/mig2.log"
grep -q 'migrat' "$tmp/mig2.log" && fail "migration: a second run migrated again"
pass "migration from the pre-.agents layout"

# --- 6. codex-only run: ~/.claude still gets the core links --------------------------------
C="$tmp/codex"; CH="$tmp/codex-home"
copy_repo "$C"; mkdir -p "$CH"
HOME="$CH" bash "$C/setup.sh" --yes --no-private --name CI --role Tester --agents codex > /dev/null
[ -L "$CH/.claude/settings.json" ] || fail "codex-only: ~/.claude/settings.json missing"
[ -L "$CH/.claude/hooks" ] || fail "codex-only: ~/.claude/hooks missing"
[ -L "$CH/.codex/AGENTS.md" ] || fail "codex-only: ~/.codex/AGENTS.md missing"
[ ! -e "$CH/.claude/CLAUDE.md" ] || fail "codex-only: ~/.claude/CLAUDE.md was linked"
[ ! -e "$CH/.claude/projects" ] || fail "codex-only: memories were linked"
[ -L "$CH/.agents/skills/typescript-tips" ] || fail "codex-only: skills missing from ~/.agents/skills"
# every script the Codex wiring names resolves through ~/.claude/hooks into the repo
n=0
while IFS= read -r p; do
  [ -n "$p" ] || continue
  [ -f "${p/#\$HOME/$CH}" ] || fail "codex-only: $p does not resolve to a file"
  n=$((n + 1))
done < <(jq -r '.hooks[][].hooks[].command | select(startswith("bash \"")) | split("\"")[1]' "$CH/.codex/hooks.json")
[ "$n" -gt 0 ] || fail "codex-only: the Codex wiring names no script"
pass "codex-only run"

echo "smoke: all cases passed"
