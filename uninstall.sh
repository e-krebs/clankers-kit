#!/usr/bin/env bash
# clankers-kit uninstall — unwire ~/.claude from this repo.
#
# For each ~/.claude entry that setup.sh symlinked INTO this repo, this removes the symlink and
# restores a real copy of the content in its place, so your ~/.claude keeps working standalone.
# Skills that were symlinked from this repo's catalog are deactivated. Foreign symlinks and your
# own files are never touched.
#
# The repo copy itself is left intact (your CLAUDE.md, settings, and memories still live here) —
# delete it separately if you no longer want it. Optionally removes the chrome-devtools MCP that
# setup can add. Your GitHub repo's visibility is NOT changed.
#
# macOS and Linux. Flags: -y/--yes (assume yes), -h/--help.
set -euo pipefail

resolve_path() {                    # canonical absolute path (bash 3.2 / macOS)
  local path="$1" dir link depth=0
  [[ "$path" != /* ]] && path="$(pwd)/${path}"
  while [[ -L "$path" ]]; do
    depth=$((depth + 1)); [[ $depth -gt 40 ]] && { echo "symlink cycle at $1" >&2; return 1; }
    link="$(readlink "$path")"
    if [[ "$link" == /* ]]; then path="$link"
    else dir="$(cd "$(dirname "$path")" && pwd)"; path="${dir}/${link}"; fi
  done
  if [[ -d "$path" ]]; then (cd "$path" && pwd -P)
  else echo "$(cd "$(dirname "$path")" && pwd -P)/$(basename "$path")"; fi
}

SCRIPT_PATH="$(resolve_path "${BASH_SOURCE[0]}")"
REPO_ROOT="$(dirname "$SCRIPT_PATH")"
CLAUDE_SRC="$(resolve_path "${REPO_ROOT}/.claude")"
CLAUDE_HOME="${HOME}/.claude"

AUTO_YES=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes) AUTO_YES=true; shift ;;
    -h|--help) printf 'Usage: ./uninstall.sh [-y|--yes]\n\nUnwire ~/.claude from this clankers-kit clone (restores real files, keeps your content).\n'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done
INTERACTIVE=false; [[ -t 0 ]] && INTERACTIVE=true

say()  { printf '%s\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*" >&2; }
confirm() { local a; $AUTO_YES && return 0; $INTERACTIVE || return 1; read -r -p "$1 [y/N] " a || return 1; [[ "$a" =~ ^[Yy]$ ]]; }

points_into_repo() {                # $1 is a symlink whose target resolves inside this repo's .claude
  [[ -L "$1" ]] || return 1
  local t; t="$(resolve_path "$1")" || return 1
  [[ "$t" == "$CLAUDE_SRC" || "$t" == "$CLAUDE_SRC"/* ]]
}

# On any unexpected failure, exit with a clear message. Restores are content-preserving (your
# data still lives in the repo), so a re-run finishes the job. No message on a clean exit.
STARTED=false
on_exit() {
  local rc=$?
  [[ $rc -eq 0 ]] && return
  $STARTED || return
  warn ""
  warn "uninstall stopped early (exit ${rc}). Your content is intact (still in ${REPO_ROOT})."
  warn "Re-run ./uninstall.sh to finish unwiring ~/.claude."
}
trap on_exit EXIT

step "clankers-kit uninstall"
say "repo:  ${REPO_ROOT}"
say "home:  ${CLAUDE_HOME}"
say ""
say "Replaces ~/.claude symlinks that point into this repo with real copies of their content,"
say "and deactivates skills linked from here. Your content is preserved; the repo is left as-is."
confirm "Proceed?" || { echo "Aborted."; exit 1; }
STARTED=true   # past the confirm — from here a failure gets the recovery message

restore_one() {                     # $1 = path under .claude (file or dir)
  local rel="$1"
  local home="${CLAUDE_HOME}/$1"
  local repo="${CLAUDE_SRC}/$1"
  if points_into_repo "$home"; then
    rm -f "$home"
    if [[ -e "$repo" ]]; then
      cp -R "$repo" "$home"
      say "  restored ~/.claude/${rel} (real copy — your content is kept)"
    else
      warn "  removed dangling ~/.claude/${rel} (nothing in the repo to restore)"
    fi
  elif [[ -L "$home" ]]; then
    say "  skip ~/.claude/${rel} (symlink points elsewhere — not ours)"
  elif [[ -e "$home" ]]; then
    say "  skip ~/.claude/${rel} (already a real file — not linked)"
  else
    say "  skip ~/.claude/${rel} (absent)"
  fi
}

step "Restoring config"
for rel in settings.json CLAUDE.md hooks projects; do restore_one "$rel"; done

step "Deactivating skills linked from this repo"
found=false
if [[ -d "${CLAUDE_HOME}/skills" ]]; then
  while IFS= read -r link; do
    if points_into_repo "$link"; then rm -f "$link"; say "  deactivated skill '$(basename "$link")'"; found=true; fi
  done < <(find "${CLAUDE_HOME}/skills" -mindepth 1 -maxdepth 1 -type l 2>/dev/null)
fi
$found || say "  none linked from this repo"

step "chrome-devtools MCP"
if command -v claude >/dev/null 2>&1 && claude mcp list 2>/dev/null | grep -q '^chrome-devtools'; then
  if confirm "  Remove the chrome-devtools MCP server (the one setup can add)?"; then
    if claude mcp remove chrome-devtools >/dev/null 2>&1; then
      say "  removed chrome-devtools MCP"
    else
      warn "  could not remove automatically — do it manually: claude mcp remove chrome-devtools"
    fi
  fi
else
  say "  not present — nothing to do"
fi

step "Done — ~/.claude is standalone again"
say "  No links into this repo remain; your config and memories are real files under ~/.claude."
say "  The repo copy at ${REPO_ROOT} is untouched — delete it if you no longer need it."
say "  If setup made your GitHub repo private, that was intentionally left unchanged."
