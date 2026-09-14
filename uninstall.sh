#!/usr/bin/env bash
# clankers-kit uninstall — unwire ~/.claude, ~/.agents and ~/.codex from this repo.
#
# For each home entry that setup.sh symlinked INTO this repo (every link kit.json declares, for
# both agents), this removes the symlink and restores a real copy of the content in its place, so
# your config keeps working standalone. Skills that were symlinked from this repo's catalog are
# deactivated in both skill dirs. Foreign symlinks and your own files are never touched.
#
# The repo copy itself is left intact (your AGENTS.md, settings, and memories still live here) —
# delete it separately if you no longer want it. Optionally removes what a `command` row installed
# (the chrome-devtools MCP). Your GitHub repo's visibility is NOT changed.
#
# macOS and Linux. Flags: -y/--yes (assume yes), -h/--help.
set -euo pipefail

resolve_path() {                    # canonical absolute path (bash 3.2 / macOS)
  local path="$1" dir link name depth=0
  [[ "$path" != /* ]] && path="$(pwd)/${path}"
  while [[ -L "$path" ]]; do
    depth=$((depth + 1)); [[ $depth -gt 40 ]] && { echo "symlink cycle at $1" >&2; return 1; }
    link="$(readlink "$path")"
    if [[ "$link" == /* ]]; then path="$link"
    else dir="$(cd "$(dirname "$path")" && pwd)"; path="${dir}/${link}"; fi
  done
  if [[ -d "$path" ]]; then (cd "$path" && pwd -P)
  elif [[ -e "$path" ]]; then echo "$(cd "$(dirname "$path")" && pwd -P)/$(basename "$path")"
  else
    dir="${path%/*}"; name="${path##*/}"
    if [[ -d "$dir" ]]; then echo "$(cd "$dir" && pwd -P)/${name}"; else echo "$path"; fi
  fi
}

SCRIPT_PATH="$(resolve_path "${BASH_SOURCE[0]}")"
REPO_ROOT="$(dirname "$SCRIPT_PATH")"
MANIFEST="${REPO_ROOT}/kit.json"

AUTO_YES=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes) AUTO_YES=true; shift ;;
    -h|--help) printf 'Usage: ./uninstall.sh [-y|--yes]\n\nUnwire ~/.claude, ~/.agents and ~/.codex from this clankers-kit clone (restores real files, keeps your content).\n'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done
INTERACTIVE=false; [[ -t 0 ]] && INTERACTIVE=true

command -v jq >/dev/null 2>&1 || { echo "Error: jq is required (brew install jq / apt install jq)." >&2; exit 1; }
[[ -f "$MANIFEST" ]] || { echo "Error: kit.json is missing from ${REPO_ROOT}." >&2; exit 1; }

say()  { printf '%s\n' "$*"; }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*" >&2; }
confirm() { local a; $AUTO_YES && return 0; $INTERACTIVE || return 1; read -r -p "$1 [y/N] " a || return 1; [[ "$a" =~ ^[Yy]$ ]]; }

points_into_repo() {                # $1 is a symlink whose target lies anywhere inside this repo (dangling or not)
  [[ -L "$1" ]] || return 1
  local t; t="$(readlink "$1")"
  [[ "$t" == "$REPO_ROOT" || "$t" == "$REPO_ROOT"/* ]] && return 0
  t="$(resolve_path "$1" 2>/dev/null)" || return 1
  [[ "$t" == "$REPO_ROOT" || "$t" == "$REPO_ROOT"/* ]]
}

run_argv() {                        # $1 = JSON argv
  local -a argv=()
  while IFS= read -r a; do argv+=("$a"); done < <(jq -r '.[]' <<< "$1")
  [[ ${#argv[@]} -gt 0 ]] || return 1
  "${argv[@]}"
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
  warn "Re-run ./uninstall.sh to finish unwiring."
}
trap on_exit EXIT

step "clankers-kit uninstall"
say "repo:  ${REPO_ROOT}"
say "home:  ${HOME}"
say ""
say "Replaces the ~/.claude, ~/.agents and ~/.codex symlinks that point into this repo with real"
say "copies of their content, and deactivates skills linked from here. Your content is preserved;"
say "the repo is left as-is."
confirm "Proceed?" || { echo "Aborted."; exit 1; }
STARTED=true   # past the confirm — from here a failure gets the recovery message

restore_one() {                     # $1 = home-relative path, $2 = repo-relative path
  local rel="$1" home="${HOME}/$1" repo="${REPO_ROOT}/$2"
  if points_into_repo "$home"; then
    rm -f "$home"
    if [[ -e "$repo" ]]; then
      cp -R "$repo" "$home"
      say "  restored ~/${rel} (real copy — your content is kept)"
    else
      warn "  removed dangling ~/${rel} (nothing in the repo to restore)"
    fi
  elif [[ -L "$home" ]]; then
    say "  skip ~/${rel} (symlink points elsewhere — not ours)"
  elif [[ -e "$home" ]]; then
    say "  skip ~/${rel} (already a real file — not linked)"
  else
    say "  skip ~/${rel} (absent)"
  fi
}

step "Restoring config"
# every link the manifest declares, for both agents; the same home path is restored once
seen=""
while IFS=$'\t' read -r home_rel repo_rel; do
  [[ ",${seen}," == *",${home_rel},"* ]] && continue
  seen="${seen},${home_rel}"
  restore_one "$home_rel" "$repo_rel"
done < <(jq -r '.components[] | (.links // [])[] | [.home, .repo] | @tsv' "$MANIFEST")
# the pre-.agents layout linked ~/.claude/CLAUDE.md straight at the repo's .claude/CLAUDE.md
points_into_repo "${HOME}/.claude/CLAUDE.md" && restore_one ".claude/CLAUDE.md" ".agents/AGENTS.md"

step "Deactivating skills linked from this repo"
found=false
for d in "${HOME}/.claude/skills" "${HOME}/.agents/skills"; do
  [[ -d "$d" ]] || continue
  while IFS= read -r link; do
    if points_into_repo "$link"; then rm -f "$link"; say "  deactivated skill '$(basename "$link")' (${d/#$HOME/~})"; found=true; fi
  done < <(find "$d" -mindepth 1 -maxdepth 1 -type l 2>/dev/null)
done
$found || say "  none linked from this repo"

# `command` rows: offer to undo what setup installed (the chrome-devtools MCP). Fields joined on
# the unit separator: @tsv would escape the backslashes inside the JSON argv strings.
while IFS=$'\037' read -r id label installed remove; do
  step "$label"
  if [[ "$installed" != "[]" ]] && ! run_argv "$installed" >/dev/null 2>&1; then
    say "  not present — nothing to do"; continue
  fi
  if confirm "  Remove ${label} (the one setup can add)?"; then
    if run_argv "$remove" >/dev/null 2>&1; then say "  removed ${id}"
    else warn "  could not remove automatically — do it manually: $(jq -r 'join(" ")' <<< "$remove")"; fi
  fi
done < <(jq -r '.components[] | select(.kind == "command") | [.id, .label, ((.installed // []) | @json), ((.remove // []) | @json)] | join("")' "$MANIFEST")

step "Done — your config is standalone again"
say "  No links into this repo remain; your config and memories are real files under ~/.claude, ~/.agents and ~/.codex."
say "  The repo copy at ${REPO_ROOT} is untouched — delete it if you no longer need it."
say "  If setup made your GitHub repo private, that was intentionally left unchanged."
