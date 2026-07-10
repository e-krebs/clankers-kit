#!/usr/bin/env bash
# clankers-kit setup — wire ~/.claude to this repo via symlinks, compose settings.json from the
# presets you pick, generate your CLAUDE.md, and (re-runnably) activate skills.
#
# How it works: it GATHERS every choice (asking nothing destructive), shows a RECAP of exactly
# what it will do — including any existing ~/.claude content it will merge — asks for one final
# confirmation, and only then APPLIES the changes.
#
# Runs from wherever you cloned it (no fixed path). macOS and Linux only — it uses bash and
# POSIX symlinks (WSL is fine; native Windows is not supported).
#
# Re-run any time: already-linked paths are left alone, and you can activate more skills.
#
# Try it safely first:  ./setup.sh --sandbox   (runs against a throwaway HOME + repo copy)
#
# Non-interactive (CI / scripted):
#   ./setup.sh --yes --name "Ada" --role "Staff engineer" --presets allowlist,enforcement
# Flags: --yes/-y, --sandbox, --name, --role, --presets <csv>, --skills <csv>,
#        --no-private (skip the make-your-repo-private step), -h/--help.
set -euo pipefail

# ---------------------------------------------------------------------------
# locate the repo (resolve this script's real path, following symlinks)
# ---------------------------------------------------------------------------
resolve_path() {                    # canonical absolute path; bash 3.2 / macOS, no python
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
CLAUDE_SRC="${REPO_ROOT}/.claude"
CLAUDE_HOME="${HOME}/.claude"

# ---------------------------------------------------------------------------
# args
# ---------------------------------------------------------------------------
AUTO_YES=false
DO_PRIVATE=true
SANDBOX=false
OPT_NAME=""; OPT_ROLE=""
OPT_PRESETS=""; OPT_SKILLS=""; PRESETS_SET=false; SKILLS_SET=false
PASS=()   # non-sandbox args, forwarded verbatim when --sandbox re-execs

usage() {
  cat <<EOF
Usage: ./setup.sh [options]

Wire ~/.claude to this clankers-kit clone.

  -y, --yes            Assume yes for the final confirmation (still prints the recap)
      --sandbox        Run against a throwaway HOME + repo copy — never touches your real ~/.claude
      --name <v>       Your name (fills CLAUDE.md; skips the prompt)
      --role <v>       One-line role (fills CLAUDE.md; skips the prompt)
      --presets <csv>  Settings presets to enable: allowlist,enforcement,notification,mcp
      --skills <csv>   Skills to activate (by directory name)
      --no-private     Skip offering to make your repo private
  -h, --help           Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes) AUTO_YES=true; PASS+=("$1"); shift ;;
    --sandbox) SANDBOX=true; shift ;;
    --name) OPT_NAME="${2:-}"; PASS+=("$1" "${2:-}"); shift 2 ;;
    --role) OPT_ROLE="${2:-}"; PASS+=("$1" "${2:-}"); shift 2 ;;
    --presets) OPT_PRESETS="${2:-}"; PRESETS_SET=true; PASS+=("$1" "${2:-}"); shift 2 ;;
    --skills) OPT_SKILLS="${2:-}"; SKILLS_SET=true; PASS+=("$1" "${2:-}"); shift 2 ;;
    --no-private) DO_PRIVATE=false; PASS+=("$1"); shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

# A prompt is only shown when we have a TTY and the value wasn't provided by a flag.
INTERACTIVE=false; [[ -t 0 ]] && INTERACTIVE=true
# Set when re-executed by --sandbox: a throwaway HOME can't be logged into Claude, so skip the interview.
SANDBOXED=false; [[ -n "${CLANKER_SANDBOX:-}" ]] && SANDBOXED=true

# ---------------------------------------------------------------------------
# colors — on only for an interactive terminal, and honour NO_COLOR (https://no-color.org)
# ---------------------------------------------------------------------------
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_CYAN=$'\033[36m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
else
  C_RESET=; C_BOLD=; C_DIM=; C_CYAN=; C_GREEN=; C_YELLOW=
fi

# --sandbox: copy the repo + point HOME at throwaway dirs, run there, then show where to look.
# Guarantees the run never touches your real ~/.claude — the safe way to try it first.
if $SANDBOX; then
  sb="$(mktemp -d)"
  cp -R "$REPO_ROOT" "$sb/clankers-kit"
  rm -rf "$sb/clankers-kit/.git"
  mkdir -p "$sb/home"
  printf '\n%sSandbox mode%s — your real ~/.claude is untouched. Running in %s\n' "${C_BOLD}${C_CYAN}" "$C_RESET" "$sb"
  # CLANKER_SANDBOX tells the inner run to skip the Claude interview: a throwaway HOME can't be
  # logged in (the login is tied to your real HOME), so the interview only works in a real run.
  rc=0
  if [[ ${#PASS[@]} -gt 0 ]]; then
    CLANKER_SANDBOX=1 HOME="$sb/home" bash "$sb/clankers-kit/setup.sh" "${PASS[@]}" || rc=$?
  else
    CLANKER_SANDBOX=1 HOME="$sb/home" bash "$sb/clankers-kit/setup.sh" || rc=$?
  fi
  printf '\n%sSandbox result%s — nothing on your real machine changed. Inspect it with:\n' "${C_BOLD}${C_CYAN}" "$C_RESET"
  printf '  %sls -la %s/home/.claude%s   # the wired-up ~/.claude (symlinks)\n' "$C_DIM" "$sb" "$C_RESET"
  printf '  %scat    %s/clankers-kit/.claude/CLAUDE.md%s   # the generated CLAUDE.md\n' "$C_DIM" "$sb" "$C_RESET"
  printf '  %srm -rf %s%s   # delete the sandbox when done\n' "$C_DIM" "$sb" "$C_RESET"
  exit "$rc"
fi

# ---------------------------------------------------------------------------
# small helpers
# ---------------------------------------------------------------------------
say()  { printf '%s\n' "$*"; }
info() { printf '%s%s%s\n' "$C_DIM" "$*" "$C_RESET"; }
step() { printf '\n%s%s%s\n' "${C_BOLD}${C_CYAN}" "$*" "$C_RESET"; }
ok()   { printf '%s%s%s\n' "$C_GREEN" "$*" "$C_RESET"; }
warn() { printf '%s%s%s\n' "$C_YELLOW" "$*" "$C_RESET" >&2; }

confirm() {                         # $1 = prompt; honours --yes (for merge/replace/privacy)
  local ans
  $AUTO_YES && return 0
  $INTERACTIVE || return 1
  read -r -p "${C_BOLD}$1${C_RESET} [y/N] " ans || return 1
  [[ "$ans" =~ ^[Yy]$ ]]
}

confirm_opt() {                     # opt-in feature prompt; NEVER auto-yes (interview offer)
  local ans
  $INTERACTIVE || return 1
  read -r -p "$1 [y/N] " ans || return 1
  [[ "$ans" =~ ^[Yy]$ ]]
}

confirm_go() {                      # final "proceed?" — defaults YES; --yes auto-proceeds
  local ans
  $AUTO_YES && return 0
  $INTERACTIVE || return 1
  read -r -p "${C_BOLD}$1${C_RESET} [Y/n] " ans || return 1
  [[ ! "$ans" =~ ^[Nn]$ ]]
}

ask() {                             # $1 = prompt, $2 = default; echoes the answer
  local ans
  if $INTERACTIVE; then
    if [[ -n "$2" ]]; then read -r -p "$1 [${2}] " ans || ans=""
    else read -r -p "$1 " ans || ans=""; fi
    printf '%s' "${ans:-$2}"
  else
    printf '%s' "$2"
  fi
}

# multiselect — arrow-key checklist with a live detail pane. Pure bash; needs a TTY.
#   in:  MS_OPT=(labels)  MS_DESC=(details)  MS_ON=(1 or "")   (three parallel arrays)
#   out: MS_ON updated in place. returns 0 on confirm, 1 on cancel.
multiselect() {
  [[ -t 1 ]] || return 0            # no TTY on stdout -> leave defaults untouched, caller proceeds
  local title="$1" n=${#MS_OPT[@]} idx=0 key rest i cols sepw bar line dl drawn=0
  local detail_h=3
  cols="${COLUMNS:-}"; [[ -z "$cols" ]] && cols="$(tput cols 2>/dev/null || echo 80)"
  [[ "$cols" -lt 40 ]] && cols=80
  local wrapw=$((cols - 4))
  sepw=$(( cols < 56 ? cols : 56 ))
  bar="$(printf '%*s' "$sepw" '')"; bar="${bar// /─}"
  printf '\033[?25l'                                        # hide cursor
  while true; do
    [[ $drawn -gt 0 ]] && printf '\033[%dA\033[0J' "$drawn" # rewind over the last frame
    printf '%s%s%s\n' "${C_BOLD}${C_CYAN}" "$title" "$C_RESET"
    printf '%s↑/↓ move · space select · enter confirm%s\n\n' "$C_DIM" "$C_RESET"
    for ((i = 0; i < n; i++)); do
      local mark
      if [[ ${MS_ON[i]:-} == 1 ]]; then mark="${C_GREEN}◉${C_RESET}"; else mark="○"; fi
      if [[ $i -eq $idx ]]; then printf '%s ❯ %b %s%s\n' "$C_BOLD" "$mark" "${MS_OPT[i]}" "$C_RESET"
      else                       printf '   %b %s\n' "$mark" "${MS_OPT[i]}"; fi
    done
    printf '%s%s%s\n' "$C_DIM" "$bar" "$C_RESET"
    dl=0
    while IFS= read -r line; do
      [[ $dl -lt $detail_h ]] && { printf '%s%s%s\n' "$C_DIM" "$line" "$C_RESET"; dl=$((dl + 1)); }
    done < <(printf '%s\n' "${MS_DESC[idx]}" | fold -s -w "$wrapw")
    while [[ $dl -lt $detail_h ]]; do printf '\n'; dl=$((dl + 1)); done
    drawn=$(( 3 + n + 1 + detail_h ))

    IFS= read -rsn1 key || key=""
    if [[ $key == $'\033' ]]; then read -rsn2 -t 1 rest 2>/dev/null || rest=""; key+="$rest"; fi
    case "$key" in
      $'\033[A'|k) idx=$(( idx > 0 ? idx - 1 : n - 1 )) ;;
      $'\033[B'|j) idx=$(( idx < n - 1 ? idx + 1 : 0 )) ;;
      ' ') if [[ ${MS_ON[idx]:-} == 1 ]]; then MS_ON[idx]=""; else MS_ON[idx]=1; fi ;;
      a) for ((i = 0; i < n; i++)); do MS_ON[i]=1; done ;;
      ""|$'\n'|$'\r') break ;;
      q) printf '\033[?25h'; return 1 ;;
    esac
  done
  printf '\033[?25h'                                        # restore cursor
  return 0
}

symlink_ok() {                      # $1 = link, $2 = repo target
  [[ -L "$1" ]] || return 1
  [[ "$(resolve_path "$1")" == "$(resolve_path "$2")" ]]
}

replace_with_symlink() {            # atomically point $1 at $2
  local link="$1" target="$2" tmp="${1}.clanker-tmp"
  rm -rf "$tmp"
  ln -sfn "$target" "$tmp"
  mv -f "$tmp" "$link"
}

# On any unexpected failure DURING APPLY, exit with a clear, reassuring message. Nothing is ever
# lost: your existing config is copied into the repo BEFORE any change. STARTED flips true only
# once we begin applying, so a gather-phase abort prints nothing scary.
STARTED=false
on_exit() {
  local rc=$?
  [[ -t 1 ]] && printf '\033[?25h'               # make sure the cursor is never left hidden (TTY only)
  [[ $rc -eq 0 ]] && return
  $STARTED || return
  warn ""
  warn "setup stopped early (exit ${rc}). Nothing was lost — your existing config was copied into"
  warn "  ${REPO_ROOT}"
  warn "before any change. Fix the issue and re-run ./setup.sh to finish, or run ./uninstall.sh to revert."
}
trap on_exit EXIT

# ---------------------------------------------------------------------------
# preflight
# ---------------------------------------------------------------------------
step "clankers-kit setup"
info "repo ${REPO_ROOT}"

# Required — setup cannot proceed without these.
command -v git >/dev/null 2>&1 || { echo "Error: git is required." >&2; exit 1; }
command -v jq  >/dev/null 2>&1 || { echo "Error: jq is required (brew install jq / apt install jq)." >&2; exit 1; }
HAVE_GH=false;  command -v gh  >/dev/null 2>&1 && HAVE_GH=true
HAVE_CLAUDE=false; command -v claude >/dev/null 2>&1 && HAVE_CLAUDE=true
HAVE_NPX=false; command -v npx >/dev/null 2>&1 && HAVE_NPX=true

# Recommended — each unlocks a feature; offer to install any that are missing.
# Detect a package manager: brew (macOS or Linuxbrew), then the common Linux ones.
INSTALLER=""; PM=""
if   command -v brew    >/dev/null 2>&1; then INSTALLER="brew install";              PM="brew"
elif command -v apt-get >/dev/null 2>&1; then INSTALLER="sudo apt-get install -y";   PM="apt"
elif command -v dnf     >/dev/null 2>&1; then INSTALLER="sudo dnf install -y";        PM="dnf"
elif command -v pacman  >/dev/null 2>&1; then INSTALLER="sudo pacman -S --noconfirm"; PM="pacman"
fi

pkg_for() {                         # $1 = tool; echo the package for the detected PM, or "" if not cleanly installable
  case "${1}:${PM}" in
    node:brew) echo node ;;  node:apt) echo "nodejs npm" ;;  node:dnf) echo nodejs ;;  node:pacman) echo "nodejs npm" ;;
    gh:brew)   echo gh ;;    gh:dnf)   echo gh ;;             gh:pacman) echo github-cli ;;
    *) echo "" ;;                   # e.g. gh on apt needs GitHub's own apt repo — point to the docs instead
  esac
}

offer_install() {                   # $1 = tool, $2 = what it unlocks, $3 = manual-install URL
  say "  - ${1}: ${2}"
  local pkg; pkg="$(pkg_for "$1")"
  if [[ -n "$INSTALLER" && -n "$pkg" ]] && confirm_opt "    install now: ${INSTALLER} ${pkg}?"; then
    # shellcheck disable=SC2086  # INSTALLER and pkg are controlled literals meant to word-split
    $INSTALLER $pkg || warn "    install failed — install it manually: ${3}"
  else
    say "    install it with: ${3}"
  fi
}

if ! $HAVE_GH || ! $HAVE_CLAUDE || ! $HAVE_NPX; then
  step "Recommended tools (optional, but you'll want them)"
  $HAVE_CLAUDE || say "  - claude: the Claude Code CLI you're configuring — https://docs.anthropic.com/en/docs/claude-code"
  $HAVE_GH  || offer_install "gh"   "lets setup keep your fork private"                    "https://github.com/cli/cli#installation"
  $HAVE_NPX || offer_install "node" "provides npx, used by the chrome-devtools MCP preset" "https://nodejs.org/en/download"
  command -v gh     >/dev/null 2>&1 && HAVE_GH=true
  command -v claude >/dev/null 2>&1 && HAVE_CLAUDE=true
  command -v npx    >/dev/null 2>&1 && HAVE_NPX=true
fi

mkdir -p "$CLAUDE_HOME"

# ===========================================================================
# GATHER — collect every decision. NOTHING on disk changes in this section.
# ===========================================================================

# --- CLAUDE.md ---------------------------------------------------------------
# keep = repo already has one; adopt = copy your existing ~/.claude one in; generate = make a new one.
CLAUDE_ACTION=""
CM_NAME=""; CM_ROLE=""; CM_LANG=""; CM_COMMS=""; CM_WORKFLOW=""
CM_INTERVIEW=false
if [[ -e "${CLAUDE_SRC}/CLAUDE.md" ]]; then
  CLAUDE_ACTION="keep"
elif [[ -f "${CLAUDE_HOME}/CLAUDE.md" && ! -L "${CLAUDE_HOME}/CLAUDE.md" ]]; then
  CLAUDE_ACTION="adopt"
else
  CLAUDE_ACTION="generate"
  step "CLAUDE.md"
  info "  A few quick questions — you can edit the file afterwards."
  say ""
  CM_NAME="${OPT_NAME:-$(ask "  name?" "you")}"
  CM_ROLE="${OPT_ROLE:-$(ask "  role (one line)?" "Engineer")}"
  if $HAVE_CLAUDE && $INTERACTIVE && ! $SANDBOXED; then
    if confirm_opt "  let Claude interview you and draft the whole file (runs at the end)?"; then CM_INTERVIEW=true; fi
  elif $HAVE_CLAUDE && $SANDBOXED; then
    info "  (the Claude interview is skipped in --sandbox — it needs your real, logged-in Claude)"
  fi
  if ! $CM_INTERVIEW; then
    # Defaults are illustrative placeholders: press enter to accept a reasonable starting line,
    # then edit it. They keep the generated CLAUDE.md useful instead of leaving empty sections.
    CM_LANG="$(ask "  language(s) / how to read your typos?" "English — interpret my typos generously")"
    CM_COMMS="$(ask "  how should Claude present work?" "propose an approach before big changes; ask when a request is ambiguous")"
    CM_WORKFLOW="$(ask "  workflow habits?" "plan-first; one concern per PR; conventional commits")"
  fi
fi

# --- settings.json presets ---------------------------------------------------
# keep = repo already has one; adopt = copy your existing ~/.claude one in; compose = build from presets.
FRAGMENT_PRESETS=(allowlist enforcement notification)   # mcp is CLI-installed, not a fragment
SETTINGS_ACTION=""
declare -a CHOSEN=()
MCP_CHOSEN=false

preset_desc() {
  case "$1" in
    allowlist)    echo "Safe-command allowlist: git status/diff/log, gh pr view, grep/ls/find and friends stop prompting for approval." ;;
    enforcement)  echo "Enforcement hooks: block cd, git -C, sed/cat/awk, secret-leaking echo, destructive find/sort, and verbose TS comments." ;;
    notification) echo "Notification sounds: one when a permission prompt is waiting, one when Claude finishes a turn." ;;
    mcp)          echo "chrome-devtools MCP server: let Claude drive and inspect a real browser. Installed via 'claude mcp add'." ;;
  esac
}

if [[ -e "${CLAUDE_SRC}/settings.json" ]]; then
  SETTINGS_ACTION="keep"
elif [[ -f "${CLAUDE_HOME}/settings.json" && ! -L "${CLAUDE_HOME}/settings.json" ]]; then
  SETTINGS_ACTION="adopt"
else
  SETTINGS_ACTION="compose"
  if $PRESETS_SET; then
    IFS=',' read -r -a want <<< "$OPT_PRESETS"
    for t in "${want[@]:-}"; do
      t="$(printf '%s' "$t" | tr -d '[:space:]')"; [[ -z "$t" ]] && continue
      [[ "$t" == "mcp" ]] && { MCP_CHOSEN=true; continue; }
      CHOSEN+=("$t")
    done
  elif $INTERACTIVE; then
    MS_OPT=(); MS_DESC=(); MS_ON=()
    for t in "${FRAGMENT_PRESETS[@]}"; do MS_OPT+=("$t"); MS_DESC+=("$(preset_desc "$t")"); MS_ON+=(""); done
    if $HAVE_CLAUDE && $HAVE_NPX; then MS_OPT+=("mcp"); MS_DESC+=("$(preset_desc mcp)"); MS_ON+=(""); fi
    say ""
    multiselect "Settings presets — all off by default" || true
    for ((i = 0; i < ${#MS_OPT[@]}; i++)); do
      [[ ${MS_ON[i]:-} == 1 ]] || continue
      if [[ "${MS_OPT[i]}" == "mcp" ]]; then MCP_CHOSEN=true; else CHOSEN+=("${MS_OPT[i]}"); fi
    done
  fi
fi

# --- link plan (read-only classification of the 4 paths we wire) -------------
LINK_SPECS=( "settings.json:file" "CLAUDE.md:file" "hooks:dir" "projects:dir" )
declare -a LINK_MERGE=()   # existing real content -> merged into repo, then linked
declare -a LINK_FOREIGN=() # a symlink pointing elsewhere -> we'll ask before replacing
declare -a LINK_NEW=()     # nothing there yet -> fresh link
declare -a LINK_DONE=()    # already correctly linked
for spec in "${LINK_SPECS[@]}"; do
  rel="${spec%%:*}"; home="${CLAUDE_HOME}/${rel}"; repo="${CLAUDE_SRC}/${rel}"
  if symlink_ok "$home" "$repo"; then LINK_DONE+=("$rel")
  elif [[ -L "$home" ]]; then LINK_FOREIGN+=("$rel")
  elif [[ -e "$home" ]]; then LINK_MERGE+=("$rel")
  else LINK_NEW+=("$rel"); fi
done

# --- skills ------------------------------------------------------------------
AVAILABLE=()
while IFS= read -r d; do
  [[ -f "${d}/SKILL.md" ]] && AVAILABLE+=("$(basename "$d")")
done < <(find "${CLAUDE_SRC}/skills" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)

declare -a SKILLS_WANT=()
if [[ ${#AVAILABLE[@]} -gt 0 ]]; then
  if $SKILLS_SET; then
    IFS=',' read -r -a want <<< "$OPT_SKILLS"
    for s in "${want[@]:-}"; do s="$(printf '%s' "$s" | tr -d '[:space:]')"; [[ -n "$s" ]] && SKILLS_WANT+=("$s"); done
  elif $INTERACTIVE; then
    MS_OPT=(); MS_DESC=(); MS_ON=()
    for s in "${AVAILABLE[@]}"; do MS_OPT+=("$s"); MS_DESC+=("Activate the '${s}' skill (symlinked into ~/.claude/skills)."); MS_ON+=(""); done
    say ""
    multiselect "Skills — pick which to activate" || true
    for ((i = 0; i < ${#MS_OPT[@]}; i++)); do [[ ${MS_ON[i]:-} == 1 ]] && SKILLS_WANT+=("${MS_OPT[i]}"); done
  fi
fi

# --- repo privacy (detect only; the change happens in APPLY) -----------------
PRIV_STATE="off"       # off | none | public | private | unknown
PRIV_REMOTE=""
if $DO_PRIVATE; then
  if $HAVE_GH && git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    PRIV_REMOTE="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true)"
  fi
  if [[ -n "$PRIV_REMOTE" ]]; then
    case "$(gh repo view "$PRIV_REMOTE" --json visibility --jq .visibility 2>/dev/null || echo unknown)" in
      PUBLIC)  PRIV_STATE="public" ;;
      PRIVATE) PRIV_STATE="private" ;;
      *)       PRIV_STATE="unknown" ;;
    esac
  else
    PRIV_STATE="none"
  fi
fi

# ===========================================================================
# RECAP — a compact summary of what APPLY will do. Your chance to bail.
# ===========================================================================
step "Recap"
rc() { printf '  %s%-9s%s %s\n' "$C_BOLD" "$1" "$C_RESET" "$2"; }

case "$CLAUDE_ACTION" in
  keep)   rc "CLAUDE.md" "keep the repo's existing file (unchanged)" ;;
  adopt)  rc "CLAUDE.md" "adopt your ~/.claude/CLAUDE.md (unchanged)" ;;
  generate)
    if $CM_INTERVIEW; then rc "CLAUDE.md" "template now → Claude interview at the end (${CM_NAME})"
    else                   rc "CLAUDE.md" "generate — ${CM_NAME}, ${CM_ROLE}"; fi ;;
esac

case "$SETTINGS_ACTION" in
  keep)  rc "settings" "keep the repo's existing file (unchanged)" ;;
  adopt) rc "settings" "adopt your ~/.claude/settings.json (presets not applied)" ;;
  compose)
    plist="none"; [[ ${#CHOSEN[@]} -gt 0 ]] && plist="$(IFS=,; printf '%s' "${CHOSEN[*]}")"
    rc "settings" "presets: ${plist}" ;;
esac
$MCP_CHOSEN && rc "mcp" "install the chrome-devtools MCP server"

if [[ ${#LINK_DONE[@]} -eq ${#LINK_SPECS[@]} ]]; then
  rc "linking" "already wired"
else
  rc "linking" "settings.json, CLAUDE.md, hooks/, projects/ → ~/.claude"
fi

if [[ ${#AVAILABLE[@]} -eq 0 ]]; then rc "skills" "none in the catalog yet"
else rc "skills" "${SKILLS_WANT[*]:-none}"; fi

case "$PRIV_STATE" in
  public)  rc "privacy" "repo is PUBLIC — will offer to make it private" ;;
  private) rc "privacy" "repo is private — good" ;;
  none)    rc "privacy" "no gh remote — memories are tracked, keep any fork private" ;;
  unknown) rc "privacy" "visibility unknown — memories are tracked, keep the fork private" ;;
esac

if [[ ${#LINK_MERGE[@]} -gt 0 ]]; then
  warn "  ⚠ existing ~/.claude/{$(IFS=,; printf '%s' "${LINK_MERGE[*]}")} will be merged into the repo first (nothing overwritten)"
fi
if [[ ${#LINK_FOREIGN[@]} -gt 0 ]]; then
  warn "  ⚠ foreign symlinks ($(IFS=,; printf '%s' "${LINK_FOREIGN[*]}")) — you'll be asked before replacing each"
fi

# ===========================================================================
# CONFIRM
# ===========================================================================
say ""
if $AUTO_YES; then
  info "(--yes) proceeding."
elif ! $INTERACTIVE; then
  echo "Error: non-interactive run without --yes — re-run with --yes to apply." >&2
  exit 1
elif ! confirm_go "Proceed?"; then
  say "Aborted — nothing was changed."
  exit 0
fi

# ===========================================================================
# APPLY — from here, changes touch the filesystem.
# ===========================================================================
STARTED=true

# --- 1. CLAUDE.md ------------------------------------------------------------
generate_claude_md() {              # fill the template from the gathered answers
  local content langline="" commsline="" wfline=""
  content="$(cat "${CLAUDE_SRC}/CLAUDE.template.md")"
  content="${content//\{\{NAME\}\}/$CM_NAME}"
  content="${content//\{\{ROLE\}\}/$CM_ROLE}"
  [[ -n "$CM_LANG" ]]     && langline="- ${CM_LANG}"
  [[ -n "$CM_COMMS" ]]    && commsline="- ${CM_COMMS}"
  [[ -n "$CM_WORKFLOW" ]] && wfline="- ${CM_WORKFLOW}"
  content="${content//\{\{LANGUAGE\}\}/$langline}"
  content="${content//\{\{COMMS\}\}/$commsline}"
  content="${content//\{\{WORKFLOW\}\}/$wfline}"
  printf '%s\n' "$content" > "${CLAUDE_SRC}/CLAUDE.md"
}
step "Applying"
case "$CLAUDE_ACTION" in
  keep)
    ok "  CLAUDE.md   kept the repo's existing file" ;;
  adopt)
    cp "${CLAUDE_HOME}/CLAUDE.md" "${CLAUDE_SRC}/CLAUDE.md"
    ok "  CLAUDE.md   adopted your existing file" ;;
  generate)
    generate_claude_md   # always write the template first; the interview (if chosen) refines it at the end
    if $CM_INTERVIEW; then ok "  CLAUDE.md   template written — Claude will refine it via the interview at the end"
    else                   ok "  CLAUDE.md   generated from template — flesh out the sections"; fi ;;
esac

# --- 2. settings.json --------------------------------------------------------
case "$SETTINGS_ACTION" in
  keep)
    ok "  settings    kept the repo's existing file" ;;
  adopt)
    cp "${CLAUDE_HOME}/settings.json" "${CLAUDE_SRC}/settings.json"
    ok "  settings    adopted your existing file (presets not applied)" ;;
  compose)
    frags=("${CLAUDE_SRC}/settings/base.json")
    for t in "${CHOSEN[@]:-}"; do
      [[ -z "$t" ]] && continue
      [[ -f "${CLAUDE_SRC}/settings/${t}.json" ]] || { warn "  unknown preset '$t' — skipping"; continue; }
      frags+=("${CLAUDE_SRC}/settings/${t}.json")
    done
    # Compose atomically: a failed jq (e.g. an edited preset with invalid JSON) must NOT leave a
    # truncated settings.json behind — otherwise the recommended re-run would adopt the empty file.
    if jq -s -f "${CLAUDE_SRC}/settings/merge.jq" "${frags[@]}" > "${CLAUDE_SRC}/settings.json.tmp"; then
      mv -f "${CLAUDE_SRC}/settings.json.tmp" "${CLAUDE_SRC}/settings.json"
    else
      rm -f "${CLAUDE_SRC}/settings.json.tmp"
      warn "  failed to compose settings.json — is a preset fragment valid JSON? Nothing was written."
      exit 1
    fi
    plist="none"; [[ ${#CHOSEN[@]} -gt 0 ]] && plist="$(IFS=,; printf '%s' "${CHOSEN[*]}")"
    ok "  settings    composed (presets: ${plist})" ;;
esac

# --- 3. link config into ~/.claude ------------------------------------------
#     Preserves any existing real content by merging it into the repo first (no overwrite).
link_one() {
  local rel="$1" kind="$2"
  local home="${CLAUDE_HOME}/${rel}" repo="${CLAUDE_SRC}/${rel}"

  [[ "$kind" == "dir" ]] && mkdir -p "$repo"

  if symlink_ok "$home" "$repo"; then
    ok "  linked      ~/.claude/${rel} (already)"
    return 0
  fi

  if [[ -L "$home" ]]; then                       # wrong symlink -> always confirm, never with --yes alone
    warn "  ~/.claude/${rel} -> $(readlink "$home") (expected ${repo})"
    if ! $INTERACTIVE; then echo "Error: refusing to replace a foreign symlink non-interactively: ~/.claude/${rel}" >&2; exit 1; fi
    read -r -p "  Replace this symlink? [y/N] " a || a=""
    [[ "$a" =~ ^[Yy]$ ]] || { say "  skip  ~/.claude/${rel}"; return 0; }
    rm -f "$home"
  elif [[ -e "$home" ]]; then                     # real file/dir -> merge into repo (preserve), then link
    if [[ "$kind" == "dir" ]]; then
      while IFS= read -r hf; do                   # warn on name collisions (the kit's version wins)
        [[ -e "${repo}/${hf#"$home"/}" ]] && warn "  note: ~/.claude/${rel}/${hf#"$home"/} is shadowed by the kit's version (yours is not copied)"
      done < <(find "$home" -type f 2>/dev/null)
      # Only remove the original AFTER the copy succeeds, so a failed merge never loses your data.
      if ! cp -Rn "$home"/. "$repo"/; then
        warn "  could not merge ~/.claude/${rel} into the repo — leaving it in place, not linking"
        return 0
      fi
    else
      [[ -e "$repo" ]] || cp "$home" "$repo"
    fi
    rm -rf "$home"
  fi

  mkdir -p "$(dirname "$home")"
  replace_with_symlink "$home" "$repo"
  ok "  linked      ~/.claude/${rel}"
}

for spec in "${LINK_SPECS[@]}"; do link_one "${spec%%:*}" "${spec##*:}"; done

# --- 4. chrome-devtools MCP (only if opted in and installable) ---------------
if $MCP_CHOSEN; then
  if $HAVE_CLAUDE && $HAVE_NPX; then
    if claude mcp add --scope user chrome-devtools -- npx -y chrome-devtools-mcp@latest >/dev/null 2>&1; then
      ok "  mcp         installed chrome-devtools (user scope)"
    else
      warn "  'claude mcp add' failed — add it later with:"
      warn "    claude mcp add --scope user chrome-devtools -- npx -y chrome-devtools-mcp@latest"
    fi
  else
    warn "  need 'claude' and 'npx' on PATH to install the MCP — skipping."
  fi
fi

# --- 5. skills — activate by per-skill symlink (re-runnable) -----------------
mkdir -p "${CLAUDE_HOME}/skills"
activate_skill() {
  local name="$1"
  local repo="${CLAUDE_SRC}/skills/${name}"
  local home="${CLAUDE_HOME}/skills/${name}"
  [[ -d "$repo" ]] || { warn "  no such skill: ${name}"; return 0; }
  symlink_ok "$home" "$repo" && { ok "  skill       ${name} (already active)"; return 0; }
  [[ -e "$home" && ! -L "$home" ]] && { warn "  skip skill ${name}: ~/.claude/skills/${name} already exists"; return 0; }
  replace_with_symlink "$home" "$repo"
  ok "  skill       ${name} activated"
}
if [[ ${#SKILLS_WANT[@]} -gt 0 ]]; then
  for s in "${SKILLS_WANT[@]}"; do activate_skill "$s"; done
fi

# --- 6. repo privacy — memories are tracked; a public fork can leak them ------
if [[ "$PRIV_STATE" == "public" ]]; then
  warn "  this repo is PUBLIC and memories (.claude/projects/*/memory) are tracked — keep the fork PRIVATE."
  if confirm "  Set ${PRIV_REMOTE} private now?"; then
    if gh repo edit "$PRIV_REMOTE" --visibility private; then ok "  privacy     set to private"
    else warn "  could not change visibility — do it manually."; fi
  fi
fi

# --- 7. done -----------------------------------------------------------------
ACTIVE=()
while IFS= read -r l; do ACTIVE+=("$(basename "$l")"); done < <(find "${CLAUDE_HOME}/skills" -mindepth 1 -maxdepth 1 -type l 2>/dev/null | sort)
step "Done"
ok "  ~/.claude → repo: settings.json, CLAUDE.md, hooks/, projects/ (memories tracked — keep the repo private)"
say "  active skills: ${ACTIVE[*]:-none}"
info "  edit .claude/CLAUDE.md, then restart Claude Code · undo any time with ./uninstall.sh"

# --- 8. Claude interview — deferred to the very end, once all wiring is done -------------------
# Runs in your real shell/HOME (where you're logged in) and hands off to Claude, which drafts your
# CLAUDE.md over the template we just wrote. Never reached in --sandbox (offer was skipped there).
if $CM_INTERVIEW && $HAVE_CLAUDE; then
  step "Claude interview"
  info "  Setup is done. Handing off to Claude — answer its questions and it writes your CLAUDE.md."
  interview_prompt="Help me set up my personal CLAUDE.md for Claude Code. Interview me with a few concise questions about my role, the languages I work in and how to read my typos, how I want you to present work (proposals, code citations, comment style), my tool/command habits, and my workflow habits (planning, PR hygiene, commit conventions, how I verify changes). Then write a terse, high-signal CLAUDE.md to ${CLAUDE_SRC}/CLAUDE.md following the section structure in ${CLAUDE_SRC}/CLAUDE.template.md (Role, Language, Communication style, Tool & command preferences, Workflow habits). Use the name '${CM_NAME}' and role '${CM_ROLE}'. Every line is re-read each turn, so keep it lean. Do not put these instructions in the file."
  exec claude "$interview_prompt"
elif $SANDBOXED && $HAVE_CLAUDE; then
  step "Claude interview"
  info "  ↑ In a real run, Claude would start here to interview you and draft your CLAUDE.md."
  info "  Skipped in --sandbox — a throwaway HOME isn't logged in."
fi
