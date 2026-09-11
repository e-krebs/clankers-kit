#!/usr/bin/env bash
# SessionStart hook: point this session's project-memory dir at the repo's canonical store.
#
# Claude Code keys the memory directory by session cwd (~/.claude/projects/<encoded-cwd>/memory),
# so a session opened in a sub-workspace (a monorepo's app/ subdir) or in a linked worktree gets an
# EMPTY store while the repo's memories sit under the main-worktree key. Fix: resolve the repo's
# main worktree via git, encode it the way Claude Code encodes a cwd (every non-alphanumeric
# byte -> '-'), and symlink this session's memory dir to the canonical one when it is missing.
# The symlink is relative, so the dotfiles repo that versions ~/.claude/projects carries it.
#
# Fails open everywhere: no cwd, not a git repo, canonical store absent, memory already present.
# codex: no

input=$(cat 2>/dev/null) || exit 0
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$cwd" ] || cwd=$PWD
[ -d "$cwd" ] || exit 0

common=$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || exit 0
[ -n "$common" ] || exit 0
main_wt=$(dirname "$common")   # <main worktree>/.git -> <main worktree>

encode() { printf '%s' "$1" | LC_ALL=C tr -c 'A-Za-z0-9' '-'; }
sess_key=$(encode "$cwd")
canon_key=$(encode "$main_wt")
[ "$sess_key" = "$canon_key" ] && exit 0

root="$HOME/.claude/projects"
canon_mem="$root/$canon_key/memory"
sess_mem="$root/$sess_key/memory"
[ -d "$canon_mem" ] || exit 0                      # nothing to share
if [ -e "$sess_mem" ] || [ -L "$sess_mem" ]; then  # already present (dir or link)
  exit 0
fi

mkdir -p "$root/$sess_key" 2>/dev/null || exit 0
ln -s "../$canon_key/memory" "$sess_mem" 2>/dev/null
exit 0
