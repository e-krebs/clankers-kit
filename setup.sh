#!/usr/bin/env bash
# clankers-kit setup — wire ~/.claude, ~/.agents and ~/.codex to this repo via symlinks, apply the
# settings presets you keep, generate your AGENTS.md, and (re-runnably) activate skills.
#
# How it works: it GATHERS every choice (asking nothing destructive), shows a RECAP of exactly
# what it will do — including any existing ~/.claude content it will merge — asks for one final
# confirmation, and only then APPLIES the changes.
#
# What ships, and what depends on what, is declared in kit.json (the manifest). Every row is on by
# default; you uncheck what you do not want in one grouped picker.
#
# Runs from wherever you cloned it (no fixed path). macOS and Linux only — it uses bash 3.2+ and
# POSIX symlinks (WSL is fine; native Windows is not supported).
#
# Re-run any time: linked paths are left alone, defaults come from what is already installed, and an
# older fork's .claude/ layout migrates in place.
#
# Try it safely first:  ./setup.sh --sandbox   (runs against a throwaway HOME + repo copy)
#
# Non-interactive (CI / scripted):
#   ./setup.sh --yes --name "Ada" --role "Staff engineer" --agents claude,codex --without mcp
# Flags: --yes/-y, --sandbox, --name, --role, --agents <csv>, --components <csv>, --without <csv>,
#        --presets <csv>, --skills <csv>, --no-private (skip the make-your-repo-private step), -h/--help.
set -euo pipefail

# ---------------------------------------------------------------------------
# locate the repo (resolve this script's real path, following symlinks)
# ---------------------------------------------------------------------------
resolve_path() {                    # canonical absolute path; bash 3.2 / macOS, no python
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
  else                                            # a dangling target: canonicalise what exists of it
    dir="${path%/*}"; name="${path##*/}"
    if [[ -d "$dir" ]]; then echo "$(cd "$dir" && pwd -P)/${name}"; else echo "$path"; fi
  fi
}

SCRIPT_PATH="$(resolve_path "${BASH_SOURCE[0]}")"
REPO_ROOT="$(dirname "$SCRIPT_PATH")"
MANIFEST="${REPO_ROOT}/kit.json"
AGENTS_SRC="${REPO_ROOT}/.agents"
CLAUDE_SRC="${REPO_ROOT}/.claude"
CLAUDE_HOME="${HOME}/.claude"

# ---------------------------------------------------------------------------
# args
# ---------------------------------------------------------------------------
AUTO_YES=false
DO_PRIVATE=true
SANDBOX=false
OPT_NAME=""; OPT_ROLE=""; OPT_AGENTS=""
OPT_COMPONENTS=""; OPT_WITHOUT=""; OPT_PRESETS=""; OPT_SKILLS=""
COMPONENTS_SET=false; PRESETS_SET=false; SKILLS_SET=false
PASS=()   # non-sandbox args, forwarded verbatim when --sandbox re-execs

usage() {
  cat <<EOF
Usage: ./setup.sh [options]

Wire ~/.claude, ~/.agents and ~/.codex to this clankers-kit clone.

  -y, --yes               Assume yes for the final confirmation (still prints the recap)
      --sandbox           Run against a throwaway HOME + repo copy — never touches your real config
      --name <v>          Your name (fills AGENTS.md; skips the prompt)
      --role <v>          One-line role (fills AGENTS.md; skips the prompt)
      --agents <csv>      Agents to wire: claude,codex (default: the ones found on PATH)
      --components <csv>  Exactly these kit.json rows (locked and required rows are added)
      --without <csv>     The defaults minus these rows
      --presets <csv>     Only these settings presets / commands (a filter over their kinds)
      --skills <csv>      Only these skills (a filter over the skill rows)
      --no-private        Skip offering to make your repo private
  -h, --help              Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes) AUTO_YES=true; PASS+=("$1"); shift ;;
    --sandbox) SANDBOX=true; shift ;;
    --name) OPT_NAME="${2:-}"; PASS+=("$1" "${2:-}"); shift 2 ;;
    --role) OPT_ROLE="${2:-}"; PASS+=("$1" "${2:-}"); shift 2 ;;
    --agents) OPT_AGENTS="${2:-}"; PASS+=("$1" "${2:-}"); shift 2 ;;
    --components) OPT_COMPONENTS="${2:-}"; COMPONENTS_SET=true; PASS+=("$1" "${2:-}"); shift 2 ;;
    --without) OPT_WITHOUT="${2:-}"; PASS+=("$1" "${2:-}"); shift 2 ;;
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
# Guarantees the run never touches your real config — the safe way to try it first.
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
  printf '  %sls -la %s/home/.claude %s/home/.agents %s/home/.codex%s   # the wired-up homes (symlinks)\n' "$C_DIM" "$sb" "$sb" "$sb" "$C_RESET"
  printf '  %scat    %s/clankers-kit/.agents/AGENTS.md%s   # the generated AGENTS.md\n' "$C_DIM" "$sb" "$C_RESET"
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

csv_has() {                         # $1 = csv, $2 = item
  [[ ",${1}," == *",${2},"* ]]
}

trim() { printf '%s' "$1" | tr -d '[:space:]'; }

symlink_ok() {                      # $1 = link, $2 = repo target
  [[ -L "$1" ]] || return 1
  [[ "$(resolve_path "$1")" == "$(resolve_path "$2")" ]]
}

ours_link() {                       # $1 = a symlink that points anywhere into this repo (dangling or not)
  [[ -L "$1" ]] || return 1
  local t; t="$(readlink "$1")"
  [[ "$t" == "$REPO_ROOT" || "$t" == "$REPO_ROOT"/* ]] && return 0
  t="$(resolve_path "$1" 2>/dev/null)" || return 1
  [[ "$t" == "$REPO_ROOT" || "$t" == "$REPO_ROOT"/* ]]
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
[[ -f "$MANIFEST" ]] || { echo "Error: kit.json is missing from ${REPO_ROOT}." >&2; exit 1; }
jq -e '.components | type == "array"' "$MANIFEST" >/dev/null 2>&1 || { echo "Error: kit.json is not a valid manifest (run bash .agents/lint-manifest.sh)." >&2; exit 1; }
HAVE_GH=false;     command -v gh     >/dev/null 2>&1 && HAVE_GH=true
HAVE_CLAUDE=false; command -v claude >/dev/null 2>&1 && HAVE_CLAUDE=true
HAVE_CODEX=false;  command -v codex  >/dev/null 2>&1 && HAVE_CODEX=true
HAVE_NPX=false;    command -v npx    >/dev/null 2>&1 && HAVE_NPX=true

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
  $HAVE_CLAUDE || say "  - claude: the Claude Code CLI — https://docs.anthropic.com/en/docs/claude-code"
  $HAVE_GH  || offer_install "gh"   "lets setup keep your fork private"                    "https://github.com/cli/cli#installation"
  $HAVE_NPX || offer_install "node" "provides npx, used by the chrome-devtools MCP preset" "https://nodejs.org/en/download"
  command -v gh     >/dev/null 2>&1 && HAVE_GH=true
  command -v claude >/dev/null 2>&1 && HAVE_CLAUDE=true
  command -v npx    >/dev/null 2>&1 && HAVE_NPX=true
fi

have_tool() {                       # $1 = tool name from a manifest `needs` list
  case "$1" in
    claude) $HAVE_CLAUDE ;;  codex) $HAVE_CODEX ;;  npx) $HAVE_NPX ;;  gh) $HAVE_GH ;;
    *) command -v "$1" >/dev/null 2>&1 ;;
  esac
}

mkdir -p "$CLAUDE_HOME"

# ===========================================================================
# GATHER — collect every decision. NOTHING on disk changes in this section.
# ===========================================================================

# --- agents ------------------------------------------------------------------
# multiselect — arrow-key checklist with a live detail pane. Pure bash; needs a TTY.
#   in:  MS_OPT=(labels)  MS_DESC=(details)  MS_ON=(1 or "")  MS_REF=(manifest index, "" for a plain
#        row, -1 for a section header)  MS_LOCK=(1 or "")   (five parallel arrays)
#   out: MS_ON updated in place. returns 0 on confirm, 1 on cancel.
MS_OPT=(); MS_DESC=(); MS_ON=(); MS_REF=(); MS_LOCK=(); MS_NOTE=""
multiselect() {
  [[ -t 1 ]] || return 0            # no TTY on stdout -> leave defaults untouched, caller proceeds
  local title="$1" n=${#MS_OPT[@]} idx=0 key rest i cols sepw bar line dl drawn=0 mark
  local detail_h=3
  cols="${COLUMNS:-}"; [[ -z "$cols" ]] && cols="$(tput cols 2>/dev/null || echo 80)"
  [[ "$cols" -lt 40 ]] && cols=80
  local wrapw=$((cols - 4))
  local dh                                                 # size the detail pane to the tallest entry
  for ((i = 0; i < n; i++)); do
    dh="$(printf '%s\n' "${MS_DESC[i]}" | fold -s -w "$wrapw" | grep -c '')"
    [[ "$dh" -gt "$detail_h" ]] && detail_h="$dh"
  done
  detail_h=$((detail_h + 1))                               # one line for the dependency note
  [[ "$detail_h" -gt 8 ]] && detail_h=8
  sepw=$(( cols < 56 ? cols : 56 ))
  bar="$(printf '%*s' "$sepw" '')"; bar="${bar// /─}"
  while [[ "${MS_REF[idx]:-}" == "-1" ]]; do idx=$((idx + 1)); done   # start on the first real row
  printf '\033[?25l'                                        # hide cursor
  while true; do
    [[ $drawn -gt 0 ]] && printf '\033[%dA\033[0J' "$drawn" # rewind over the last frame
    printf '%s%s%s\n' "${C_BOLD}${C_CYAN}" "$title" "$C_RESET"
    printf '%s↑/↓ move · space toggle · a all · enter confirm · q cancel%s\n\n' "$C_DIM" "$C_RESET"
    for ((i = 0; i < n; i++)); do
      if [[ "${MS_REF[i]:-}" == "-1" ]]; then printf ' %s%s%s\n' "$C_BOLD" "${MS_OPT[i]}" "$C_RESET"; continue; fi
      if [[ ${MS_ON[i]:-} == 1 ]]; then mark="${C_GREEN}◉${C_RESET}"; else mark="○"; fi
      [[ -n "${MS_LOCK[i]:-}" ]] && mark="${C_DIM}◉${C_RESET}"
      if [[ $i -eq $idx ]]; then printf '%s ❯ %b %s%s\n' "$C_BOLD" "$mark" "${MS_OPT[i]}" "$C_RESET"
      else                       printf '   %b %s\n' "$mark" "${MS_OPT[i]}"; fi
    done
    printf '%s%s%s\n' "$C_DIM" "$bar" "$C_RESET"
    dl=0
    while IFS= read -r line; do
      [[ $dl -lt $((detail_h - 1)) ]] && { printf '%s%s%s\n' "$C_DIM" "$line" "$C_RESET"; dl=$((dl + 1)); }
    done < <(printf '%s\n' "${MS_DESC[idx]}" | fold -s -w "$wrapw")
    while [[ $dl -lt $((detail_h - 1)) ]]; do printf '\n'; dl=$((dl + 1)); done
    printf '%s%s%s\n' "$C_YELLOW" "$MS_NOTE" "$C_RESET"
    drawn=$(( 3 + n + 1 + detail_h ))

    IFS= read -rsn1 key || key=""
    if [[ $key == $'\033' ]]; then read -rsn2 -t 1 rest 2>/dev/null || rest=""; key+="$rest"; fi
    case "$key" in
      $'\033[A'|k) MS_NOTE=""; idx=$(( idx > 0 ? idx - 1 : n - 1 ))
                   while [[ "${MS_REF[idx]:-}" == "-1" ]]; do idx=$(( idx > 0 ? idx - 1 : n - 1 )); done ;;
      $'\033[B'|j) MS_NOTE=""; idx=$(( idx < n - 1 ? idx + 1 : 0 ))
                   while [[ "${MS_REF[idx]:-}" == "-1" ]]; do idx=$(( idx < n - 1 ? idx + 1 : 0 )); done ;;
      ' ') toggle_row "$idx" ;;
      a) MS_NOTE=""; for ((i = 0; i < n; i++)); do [[ "${MS_REF[i]:-}" == "-1" ]] || MS_ON[i]=1; done ;;
      ""|$'\n'|$'\r') break ;;
      q) printf '\033[?25h'; return 1 ;;
    esac
  done
  printf '\033[?25h'                                        # restore cursor
  return 0
}

# toggle_row — space on a row. A plain row (MS_REF "") flips; a manifest row honours the lock,
# re-checks itself when a checked row requires it, and checks its `requires` closure when turned
# on. Reads the C_* manifest arrays and MS_ROW, which exist by the time a manifest picker runs.
MS_ROW=()
toggle_row() {                      # $1 = row index
  local r="$1" ci="${MS_REF[$1]}" j k id row
  [[ "$ci" == "-1" ]] && return 0
  if [[ -z "$ci" ]]; then                                   # a plain row (the agents question)
    if [[ ${MS_ON[r]:-} == 1 ]]; then MS_ON[r]=""; else MS_ON[r]=1; fi; return 0
  fi
  [[ -n "${MS_LOCK[r]:-}" ]] && { MS_NOTE="${MS_OPT[r]} is the core layout — it stays on"; return 0; }
  if [[ ${MS_ON[r]:-} == 1 ]]; then
    MS_ON[r]=""; MS_NOTE=""
    for ((j = 0; j < N; j++)); do                           # a checked dependant re-checks it
      row="${MS_ROW[j]:-}"; [[ -n "$row" && ${MS_ON[row]:-} == 1 ]] || continue
      if csv_has "${C_REQ[j]}" "${C_ID[ci]}"; then MS_ON[r]=1; MS_NOTE="kept: ${C_LABEL[j]} requires ${C_LABEL[ci]}"; return 0; fi
    done
  else
    MS_ON[r]=1; MS_NOTE=""
    local -a queue=("$ci") added=()
    local qi=0
    while [[ $qi -lt ${#queue[@]} ]]; do                    # check the closure of `requires`
      k="${queue[qi]}"; qi=$((qi + 1))
      [[ -n "${C_REQ[k]}" ]] || continue
      IFS=',' read -r -a want <<< "${C_REQ[k]}"
      for id in "${want[@]}"; do
        j="$(cidx "$id")" || continue
        row="${MS_ROW[j]:-}"; [[ -n "$row" && ${MS_ON[row]:-} != 1 ]] || continue
        MS_ON[row]=1; added+=("${C_LABEL[j]}"); queue+=("$j")
      done
    done
    [[ ${#added[@]} -gt 0 ]] && MS_NOTE="also checked: $(IFS=,; printf '%s' "${added[*]}")"
  fi
  return 0
}

# Which agents to wire. Detected from PATH, overridden by --agents; asked only when nothing is found.
AGENTS=()
has_agent() { local a; for a in "${AGENTS[@]:-}"; do [[ "$a" == "$1" ]] && return 0; done; return 1; }
if [[ -n "$OPT_AGENTS" ]]; then
  IFS=',' read -r -a want <<< "$OPT_AGENTS"
  for a in "${want[@]:-}"; do
    a="$(trim "$a")"; [[ -z "$a" ]] && continue
    case "$a" in
      claude|codex) has_agent "$a" || AGENTS+=("$a") ;;
      *) echo "Error: --agents takes claude and/or codex, not '${a}'." >&2; exit 1 ;;
    esac
  done
  [[ ${#AGENTS[@]} -gt 0 ]] || { echo "Error: --agents names no agent." >&2; exit 1; }
else
  $HAVE_CLAUDE && AGENTS+=(claude)
  $HAVE_CODEX && AGENTS+=(codex)
  if [[ ${#AGENTS[@]} -eq 0 ]]; then
    if $INTERACTIVE; then
      MS_OPT=(claude codex); MS_ON=(1 ""); MS_REF=("" ""); MS_LOCK=("" ""); MS_NOTE=""
      MS_DESC=("Claude Code — wires ~/.claude (settings, hooks, memories, skills) and ~/.agents."
               "Codex CLI — wires ~/.codex (AGENTS.md, hook wiring) and ~/.agents (skills).")
      say ""
      multiselect "Which agents do you run? (none found on PATH)" || { say "Aborted — nothing was changed."; exit 0; }
      for ((i = 0; i < ${#MS_OPT[@]}; i++)); do [[ ${MS_ON[i]:-} == 1 ]] && AGENTS+=("${MS_OPT[i]}"); done
    fi
    [[ ${#AGENTS[@]} -gt 0 ]] || { AGENTS=(claude); info "  (no agent CLI on PATH — wiring Claude Code; pass --agents to change)"; }
  fi
fi

# --- manifest ----------------------------------------------------------------
# Loaded into parallel arrays (bash 3.2 has no associative arrays). One row per component, fields
# joined on the unit separator (0x1f): a tab is IFS whitespace, so empty tab-separated fields collapse.
US=$'\037'
C_ID=(); C_GROUP=(); C_KIND=(); C_LABEL=(); C_DESC=(); C_DEFAULT=(); C_LOCKED=(); C_REQ=(); C_SOFT=()
C_AGENTS=(); C_NEEDS=(); C_SETTINGS=(); C_SKILL=(); C_LINKS=(); C_INSTALLED=(); C_INSTALL=(); C_REMOVE=()
while IFS="$US" read -r id group kind label desc def locked req soft agents needs settings skill links installed install remove; do
  C_ID+=("$id"); C_GROUP+=("$group"); C_KIND+=("$kind"); C_LABEL+=("$label"); C_DESC+=("$desc")
  C_DEFAULT+=("$def"); C_LOCKED+=("$locked"); C_REQ+=("$req"); C_SOFT+=("$soft"); C_AGENTS+=("$agents")
  C_NEEDS+=("$needs"); C_SETTINGS+=("$settings"); C_SKILL+=("$skill"); C_LINKS+=("$links")
  C_INSTALLED+=("$installed"); C_INSTALL+=("$install"); C_REMOVE+=("$remove")
done < <(jq -r '.components[] | [
    .id, .group, .kind, .label, (.description // ""),
    (if .default == false then "" else "1" end), (if .locked == true then "1" else "" end),
    ((.requires // []) | join(",")), ((.soft // []) | join(",")), ((.agents // []) | join(",")),
    ((.needs // []) | join(",")), (.settings // ""), (.skill // ""),
    ((.links // []) | map([.home, .repo, .type, (.agent // "")] | join("|")) | join(";")),
    ((.installed // []) | @json), ((.install // []) | @json), ((.remove // []) | @json)
  ] | join("")' "$MANIFEST")
G_ID=(); G_LABEL=()
while IFS="$US" read -r id label; do G_ID+=("$id"); G_LABEL+=("$label"); done \
  < <(jq -r '.groups[] | [.id, .label] | join("")' "$MANIFEST")
N=${#C_ID[@]}

cidx() {                            # $1 = component id -> its index, or return 1
  local i; for ((i = 0; i < N; i++)); do [[ "${C_ID[i]}" == "$1" ]] && { printf '%s' "$i"; return 0; }; done; return 1
}

applicable() {                      # $1 = index -> 0 when the row concerns a wired agent and its tools are present
  local a t hit=false
  if [[ -n "${C_AGENTS[$1]}" ]]; then
    IFS=',' read -r -a want <<< "${C_AGENTS[$1]}"
    for a in "${want[@]}"; do has_agent "$a" && hit=true; done
    $hit || return 1
  fi
  if [[ -n "${C_NEEDS[$1]}" ]]; then
    IFS=',' read -r -a want <<< "${C_NEEDS[$1]}"
    for t in "${want[@]}"; do have_tool "$t" || return 1; done
  fi
  return 0
}

skill_description() {               # the SKILL.md frontmatter `description:` value, or a safe fallback
  local f="${AGENTS_SRC}/skills/${1}/SKILL.md" line
  line="$(grep -m1 '^description:' "$f" 2>/dev/null || true)"
  line="${line#description:}"                       # drop the key
  line="${line#"${line%%[![:space:]]*}"}"           # trim leading whitespace
  if [[ -n "$line" ]]; then printf '%s' "$line"; else printf "the '%s' skill" "$1"; fi
}

row_desc() {                        # $1 = index -> the detail-pane text
  if [[ -n "${C_DESC[$1]}" ]]; then printf '%s' "${C_DESC[$1]}"
  elif [[ -n "${C_SKILL[$1]}" ]]; then skill_description "${C_SKILL[$1]}"
  else printf '%s' "${C_LABEL[$1]}"; fi
}

# each_link: iterate a component's link entries for the wired agents. Sets home_rel, repo_rel, ltype.
# usage: while each_link "$i"; do ...; done   (LINK_CUR resets per component)
LINK_CUR=""; LINK_REST=""
each_link() {
  local entry agent
  if [[ "$LINK_CUR" != "$1" ]]; then LINK_CUR="$1"; LINK_REST="${C_LINKS[$1]}"; fi
  while [[ -n "$LINK_REST" ]]; do
    entry="${LINK_REST%%;*}"
    if [[ "$LINK_REST" == *";"* ]]; then LINK_REST="${LINK_REST#*;}"; else LINK_REST=""; fi
    IFS='|' read -r home_rel repo_rel ltype agent <<< "$entry"
    [[ -z "$agent" ]] || has_agent "$agent" || continue
    return 0
  done
  LINK_CUR=""
  return 1
}

# Settings presets apply additively (see .claude/settings/merge.jq); a preset is "applied" when
# applying it again would change nothing.
preset_applied() {                  # $1 = fragment path
  [[ -f "${CLAUDE_SRC}/settings.json" ]] || return 1
  jq -e -s -L "${CLAUDE_SRC}/settings" 'include "merge"; apply(.[0]; .[1]) == .[0]' "${CLAUDE_SRC}/settings.json" "$1" >/dev/null 2>&1
}

skill_active() {                    # $1 = skill dir name -> 0 when either skill home links it into this repo
  ours_link "${CLAUDE_HOME}/skills/${1}" || ours_link "${HOME}/.agents/skills/${1}"
}

run_argv() {                        # $1 = JSON argv -> runs it; return 1 on an empty list
  local -a argv=()
  while IFS= read -r a; do argv+=("$a"); done < <(jq -r '.[]' <<< "$1")
  [[ ${#argv[@]} -gt 0 ]] || return 1
  "${argv[@]}"
}

on_disk() {                         # $1 = index -> 0 when the row is already installed
  local any=false
  case "${C_KIND[$1]}" in
    links)
      while each_link "$1"; do any=true; symlink_ok "${HOME}/${home_rel}" "${REPO_ROOT}/${repo_rel}" || ours_link "${HOME}/${home_rel}" || { LINK_CUR=""; return 1; }; done
      $any ;;
    settings) preset_applied "${REPO_ROOT}/${C_SETTINGS[$1]}" ;;
    skill)    skill_active "${C_SKILL[$1]}" ;;
    command)  [[ "${C_INSTALLED[$1]}" != "[]" ]] && run_argv "${C_INSTALLED[$1]}" >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

# --- selection ---------------------------------------------------------------
# A re-run seeds from disk (what is installed stays checked); a first run from the manifest defaults.
RERUN=false; ours_link "${CLAUDE_HOME}/settings.json" && RERUN=true
SEL=(); APPL=()
for ((i = 0; i < N; i++)); do
  if applicable "$i"; then APPL+=(1); else APPL+=(""); SEL+=(""); continue; fi
  if [[ -n "${C_LOCKED[i]}" ]]; then SEL+=(1)
  elif $RERUN; then if on_disk "$i"; then SEL+=(1); else SEL+=(""); fi
  else SEL+=("${C_DEFAULT[i]}"); fi
done

# Hard edges: a checked row checks its `requires` closure. Returns the ids it had to add in FORCED.
FORCED=()
settle_requires() {
  local i j changed=true id
  while $changed; do
    changed=false
    for ((i = 0; i < N; i++)); do
      [[ ${SEL[i]:-} == 1 && -n "${C_REQ[i]}" ]] || continue
      IFS=',' read -r -a want <<< "${C_REQ[i]}"
      for id in "${want[@]}"; do
        j="$(cidx "$id")" || continue
        [[ -n "${APPL[j]}" && ${SEL[j]:-} != 1 ]] || continue
        SEL[j]=1; FORCED+=("${C_ID[j]} (required by ${C_ID[i]})"); changed=true
      done
    done
  done
}

filter_kinds() {                    # $1 = csv of wanted ids, $2.. = kinds the filter covers
  local csv="$1" i k hit; shift
  for ((i = 0; i < N; i++)); do
    hit=false; for k in "$@"; do [[ "${C_KIND[i]}" == "$k" ]] && hit=true; done
    $hit && [[ -z "${C_LOCKED[i]}" ]] || continue
    if csv_has "$csv" "${C_ID[i]}"; then SEL[i]=1; else SEL[i]=""; fi
  done
}

if $COMPONENTS_SET; then
  for ((i = 0; i < N; i++)); do [[ -n "${C_LOCKED[i]}" ]] || SEL[i]=""; done
  IFS=',' read -r -a want <<< "$OPT_COMPONENTS"
  for id in "${want[@]:-}"; do
    id="$(trim "$id")"; [[ -z "$id" ]] && continue
    j="$(cidx "$id")" || { echo "Error: unknown component '${id}' (see kit.json)." >&2; exit 1; }
    [[ -n "${APPL[j]}" ]] && SEL[j]=1
  done
fi
if [[ -n "$OPT_WITHOUT" ]]; then
  IFS=',' read -r -a want <<< "$OPT_WITHOUT"
  for id in "${want[@]:-}"; do
    id="$(trim "$id")"; [[ -z "$id" ]] && continue
    j="$(cidx "$id")" || { warn "  unknown component '${id}' in --without — ignored"; continue; }
    [[ -n "${C_LOCKED[j]}" ]] && { warn "  ${id} is part of the core layout — kept"; continue; }
    SEL[j]=""
  done
fi
$PRESETS_SET && filter_kinds "$(trim "$OPT_PRESETS")" settings command hooks toggle
$SKILLS_SET  && filter_kinds "$(trim "$OPT_SKILLS")" skill upstream

# The picker: one grouped multiselect, section rows per group, dependency-aware toggles
# (toggle_row, defined next to multiselect). MS_ROW maps a component index to its row.
for ((i = 0; i < N; i++)); do MS_ROW+=(""); done
if $INTERACTIVE && ! $COMPONENTS_SET && ! $PRESETS_SET && ! $SKILLS_SET; then
  MS_OPT=(); MS_DESC=(); MS_ON=(); MS_REF=(); MS_LOCK=(); MS_NOTE=""
  for ((g = 0; g < ${#G_ID[@]}; g++)); do
    n_rows=0
    for ((i = 0; i < N; i++)); do [[ "${C_GROUP[i]}" == "${G_ID[g]}" && -n "${APPL[i]}" ]] && n_rows=$((n_rows + 1)); done
    [[ $n_rows -gt 0 ]] || continue
    MS_OPT+=("${G_LABEL[g]}"); MS_DESC+=(""); MS_ON+=(""); MS_REF+=("-1"); MS_LOCK+=("")
    for ((i = 0; i < N; i++)); do
      [[ "${C_GROUP[i]}" == "${G_ID[g]}" && -n "${APPL[i]}" ]] || continue
      MS_ROW[i]=${#MS_OPT[@]}
      MS_OPT+=("${C_LABEL[i]}"); MS_DESC+=("$(row_desc "$i")"); MS_ON+=("${SEL[i]}"); MS_REF+=("$i"); MS_LOCK+=("${C_LOCKED[i]}")
    done
  done
  say ""
  multiselect "What to install — everything on by default, uncheck what you don't want" || { say "Aborted — nothing was changed."; exit 0; }
  for ((i = 0; i < N; i++)); do
    row="${MS_ROW[i]:-}"; [[ -n "$row" ]] || continue
    if [[ ${MS_ON[row]:-} == 1 ]]; then SEL[i]=1; else SEL[i]=""; fi
  done
fi
settle_requires

selected() { [[ ${SEL[$1]:-} == 1 ]]; }
sel_id() { local j; j="$(cidx "$1")" || return 1; selected "$j"; }

# --- migration plan (an older fork's .claude/ layout) ------------------------
# Read-only here; APPLY runs it first. Everything it does is idempotent.
MIG_NOTES=()
old_tree() { [[ -d "$1" && ! -L "$1" ]] && [[ -n "$(find "$1" -mindepth 1 -print -quit 2>/dev/null)" ]]; }
[[ -f "${CLAUDE_SRC}/CLAUDE.md" && ! -e "${AGENTS_SRC}/AGENTS.md" ]] && MIG_NOTES+=(".claude/CLAUDE.md → .agents/AGENTS.md")
old_tree "${CLAUDE_SRC}/hooks"  && MIG_NOTES+=(".claude/hooks/* → .agents/hooks/")
old_tree "${CLAUDE_SRC}/skills" && MIG_NOTES+=(".claude/skills/* → .agents/skills/")
for p in hooks CLAUDE.md; do
  [[ -L "${CLAUDE_HOME}/${p}" ]] && ours_link "${CLAUDE_HOME}/${p}" && [[ "$(readlink "${CLAUDE_HOME}/${p}")" == "${CLAUDE_SRC}/"* ]] \
    && MIG_NOTES+=("link ~/.claude/${p} → the .agents tree")
done

# --- AGENTS.md ---------------------------------------------------------------
# keep = repo already has one (or migration brings one); adopt = copy your existing one in; generate = make a new one.
AGENTS_ACTION=""
AM_NAME=""; AM_ROLE=""; AM_LANG=""; AM_COMMS=""; AM_WORKFLOW=""; AM_ADOPT_FROM=""
AM_INTERVIEW=false
if sel_id instructions; then
  if [[ -e "${AGENTS_SRC}/AGENTS.md" || -f "${CLAUDE_SRC}/CLAUDE.md" ]]; then
    AGENTS_ACTION="keep"
  elif [[ -f "${CLAUDE_HOME}/CLAUDE.md" && ! -L "${CLAUDE_HOME}/CLAUDE.md" ]]; then
    AGENTS_ACTION="adopt"; AM_ADOPT_FROM="${CLAUDE_HOME}/CLAUDE.md"
  elif [[ -f "${HOME}/.codex/AGENTS.md" && ! -L "${HOME}/.codex/AGENTS.md" ]]; then
    AGENTS_ACTION="adopt"; AM_ADOPT_FROM="${HOME}/.codex/AGENTS.md"
  else
    AGENTS_ACTION="generate"
    step "AGENTS.md"
    info "  A few quick questions — you can edit the file afterwards."
    say ""
    AM_NAME="${OPT_NAME:-$(ask "  name?" "you")}"
    AM_ROLE="${OPT_ROLE:-$(ask "  role (one line)?" "Engineer")}"
    if $HAVE_CLAUDE && $INTERACTIVE && ! $SANDBOXED; then
      if confirm_opt "  let Claude interview you and draft the whole file (runs at the end)?"; then AM_INTERVIEW=true; fi
    elif $HAVE_CLAUDE && $SANDBOXED; then
      info "  (the Claude interview is skipped in --sandbox — it needs your real, logged-in Claude)"
    fi
    if ! $AM_INTERVIEW; then
      # Defaults are illustrative placeholders: press enter to accept a reasonable starting line,
      # then edit it. They keep the generated AGENTS.md useful instead of leaving empty sections.
      AM_LANG="$(ask "  language(s) / how to read your typos?" "English — interpret my typos generously")"
      AM_COMMS="$(ask "  how should the agent present work?" "ask when a request is ambiguous; keep solutions proportional, flag heavier options as opt-in")"
      AM_WORKFLOW="$(ask "  workflow habits?" "plan-first; conventional commits with a scope")"
    fi
  fi
fi

# --- settings.json -----------------------------------------------------------
# The presets apply additively on every run: arrays union, a scalar is set only when absent, nothing
# is removed. adopt = start from your existing ~/.claude/settings.json; create = start from base.json.
SETTINGS_ACTION="update"
if [[ ! -e "${CLAUDE_SRC}/settings.json" ]]; then
  if [[ -f "${CLAUDE_HOME}/settings.json" && ! -L "${CLAUDE_HOME}/settings.json" ]]; then SETTINGS_ACTION="adopt"
  else SETTINGS_ACTION="create"; fi
fi
PRESETS=()
for ((i = 0; i < N; i++)); do [[ "${C_KIND[i]}" == settings ]] && selected "$i" && PRESETS+=("${C_ID[i]}"); done

# --- link plan (read-only classification of every selected link) -------------
PLAN_LINKS=()             # "home_rel|repo_rel|type"
declare -a LINK_MERGE=()  # existing real content -> merged into repo, then linked
declare -a LINK_FOREIGN=() # a symlink pointing elsewhere -> we'll ask before replacing
declare -a LINK_DONE=()   # already correctly linked (or ours, to retarget)
LINKS_DROP=()             # "home_rel|repo_rel": a kit link whose row is now unchecked -> restored as a real copy
for ((i = 0; i < N; i++)); do
  [[ "${C_KIND[i]}" == links && -n "${APPL[i]}" ]] || continue
  if ! selected "$i"; then
    while each_link "$i"; do ours_link "${HOME}/${home_rel}" && LINKS_DROP+=("${home_rel}|${repo_rel}"); done
    continue
  fi
  while each_link "$i"; do
    PLAN_LINKS+=("${home_rel}|${repo_rel}|${ltype}")
    home="${HOME}/${home_rel}"
    if symlink_ok "$home" "${REPO_ROOT}/${repo_rel}" || ours_link "$home"; then LINK_DONE+=("$home_rel")
    elif [[ -L "$home" ]]; then LINK_FOREIGN+=("$home_rel")
    elif [[ -e "$home" ]]; then LINK_MERGE+=("$home_rel")
    fi
  done
done

# --- skills ------------------------------------------------------------------
SKILLS_WANT=(); SKILLS_DROP=()
for ((i = 0; i < N; i++)); do
  [[ "${C_KIND[i]}" == skill ]] || continue
  if selected "$i"; then SKILLS_WANT+=("${C_SKILL[i]}")
  elif [[ -n "${APPL[i]}" ]] && skill_active "${C_SKILL[i]}"; then SKILLS_DROP+=("${C_SKILL[i]}"); fi
done

# --- commands (the chrome-devtools MCP) --------------------------------------
CMDS=()
for ((i = 0; i < N; i++)); do [[ "${C_KIND[i]}" == command ]] && selected "$i" && CMDS+=("$i"); done

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
rc() { printf '  %s%-10s%s %s\n' "$C_BOLD" "$1" "$C_RESET" "$2"; }

rc "agents" "$(IFS=,; printf '%s' "${AGENTS[*]}")"
if [[ ${#MIG_NOTES[@]} -gt 0 ]]; then
  rc "migration" "an older layout was found — moved in place first:"
  for m in "${MIG_NOTES[@]}"; do printf '             %s• %s%s\n' "$C_DIM" "$m" "$C_RESET"; done
fi

case "$AGENTS_ACTION" in
  "")     rc "AGENTS.md" "not linked (unchecked)" ;;
  keep)   rc "AGENTS.md" "keep the repo's existing file (unchanged)" ;;
  adopt)  rc "AGENTS.md" "adopt ${AM_ADOPT_FROM/#$HOME/~} (unchanged)" ;;
  generate)
    if $AM_INTERVIEW; then rc "AGENTS.md" "template now → Claude interview at the end (${AM_NAME})"
    else                   rc "AGENTS.md" "generate — ${AM_NAME}, ${AM_ROLE}"; fi ;;
esac

plist="none"; [[ ${#PRESETS[@]} -gt 0 ]] && plist="$(IFS=,; printf '%s' "${PRESETS[*]}")"
case "$SETTINGS_ACTION" in
  adopt)  rc "settings" "adopt your ~/.claude/settings.json, then apply presets: ${plist}" ;;
  create) rc "settings" "create from base.json, presets: ${plist}" ;;
  update) rc "settings" "apply presets additively: ${plist}" ;;
esac
for ((i = 0; i < N; i++)); do
  [[ -n "${APPL[i]}" && "${C_KIND[i]}" == settings ]] && ! selected "$i" && preset_applied "${REPO_ROOT}/${C_SETTINGS[i]}" \
    && info "             (${C_ID[i]} was applied earlier — opting out is a manual edit of .claude/settings.json)"
done
for ci in "${CMDS[@]:-}"; do [[ -n "$ci" ]] && rc "${C_ID[ci]}" "install ${C_LABEL[ci]}"; done

if [[ ${#PLAN_LINKS[@]} -eq 0 ]]; then
  rc "linking" "nothing selected"
elif [[ ${#LINK_DONE[@]} -eq ${#PLAN_LINKS[@]} ]]; then
  rc "linking" "already wired (${#PLAN_LINKS[@]} links)"
else
  homes=""
  for l in "${PLAN_LINKS[@]}"; do homes+="${l%%|*}, "; done
  rc "linking" "${homes%, } → ~"
fi
if [[ ${#LINKS_DROP[@]} -gt 0 ]]; then
  homes=""
  for l in "${LINKS_DROP[@]}"; do homes+="${l%%|*}, "; done
  rc "unlinking" "${homes%, } (unchecked — each becomes a real copy of its content)"
fi

if [[ ${#SKILLS_WANT[@]} -eq 0 ]]; then
  rc "skills" "none selected"
else
  rc "skills" "${#SKILLS_WANT[@]} active (~/.claude/skills and ~/.agents/skills):"
  for s in "${SKILLS_WANT[@]}"; do printf '             %s• %s%s\n' "$C_DIM" "$s" "$C_RESET"; done
fi
[[ ${#SKILLS_DROP[@]} -gt 0 ]] && rc "" "deactivate: $(IFS=,; printf '%s' "${SKILLS_DROP[*]}")"
[[ ${#FORCED[@]} -gt 0 ]] && rc "kept on" "$(IFS=';'; printf '%s' "${FORCED[*]}")"
# a re-run seeds from disk, so a row that arrived with a pull is off until picked: say which
NEW_OFF=()
if $RERUN; then
  for ((i = 0; i < N; i++)); do
    [[ -n "${APPL[i]}" && -n "${C_DEFAULT[i]}" ]] && ! selected "$i" && ! on_disk "$i" && NEW_OFF+=("${C_ID[i]}")
  done
fi
[[ ${#NEW_OFF[@]} -gt 0 ]] && rc "available" "$(IFS=,; printf '%s' "${NEW_OFF[*]}") — unchecked; pick them in the picker or with --components"

case "$PRIV_STATE" in
  public)  rc "privacy" "repo is PUBLIC — will offer to make it private" ;;
  private) rc "privacy" "repo is private — good" ;;
  none)    rc "privacy" "no gh remote — memories are tracked, keep any fork private" ;;
  unknown) rc "privacy" "visibility unknown — memories are tracked, keep the fork private" ;;
esac

if [[ ${#LINK_MERGE[@]} -gt 0 ]]; then
  warn "  ⚠ existing ~/{$(IFS=,; printf '%s' "${LINK_MERGE[*]}")} will be merged into the repo first (nothing overwritten)"
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
step "Applying"

# --- 0. migration — an older fork's .claude/ layout moves into .agents/ ------
#     Idempotent: a second run finds nothing to do. Nothing is deleted before it is copied or backed up.
migrate_tree() {                    # $1 = old dir, $2 = new dir; copies files, backs up collisions, removes the old dir
  local src="$1" dst="$2" f rel to bak failed=0
  [[ -d "$src" && ! -L "$src" ]] || return 0
  old_tree "$src" || { rmdir "$src" 2>/dev/null || true; return 0; }   # an empty leftover dir
  while IFS= read -r f; do
    rel="${f#"$src"/}"; to="${dst}/${rel}"
    mkdir -p "$(dirname "$to")"
    if [[ ! -e "$to" && ! -L "$to" ]]; then
      cp -R "$f" "$to" || { failed=$((failed + 1)); continue; }
    elif [[ -f "$f" && -f "$to" ]] && cmp -s "$f" "$to"; then
      :                                                     # same content already there
    else
      bak="${to}.clankers-bak"                              # never clobber an earlier backup
      if [[ -e "$bak" ]] && ! cmp -s "$f" "$bak" 2>/dev/null; then bak="${bak}.$(date +%Y%m%d%H%M%S)"; fi
      cp -R "$f" "$bak" || { failed=$((failed + 1)); continue; }
      warn "  migrate     ${rel} differs from the kit's — yours saved as ${bak#"$REPO_ROOT"/}"
    fi
  done < <(find "$src" \( -type f -o -type l \) 2>/dev/null)
  if [[ $failed -eq 0 ]]; then rm -rf "$src"; ok "  migrate     ${src#"$REPO_ROOT"/}/ → ${dst#"$REPO_ROOT"/}/"
  else warn "  migrate     ${failed} file(s) could not be copied from ${src#"$REPO_ROOT"/} — left in place"; fi
}
if [[ -f "${CLAUDE_SRC}/CLAUDE.md" ]]; then
  if [[ ! -e "${AGENTS_SRC}/AGENTS.md" ]]; then
    mkdir -p "$AGENTS_SRC"; mv "${CLAUDE_SRC}/CLAUDE.md" "${AGENTS_SRC}/AGENTS.md"
    ok "  migrate     .claude/CLAUDE.md → .agents/AGENTS.md"
  elif cmp -s "${CLAUDE_SRC}/CLAUDE.md" "${AGENTS_SRC}/AGENTS.md"; then
    rm -f "${CLAUDE_SRC}/CLAUDE.md"
  else
    warn "  migrate     both .claude/CLAUDE.md and .agents/AGENTS.md exist and differ — AGENTS.md is the one linked; merge by hand"
  fi
fi
migrate_tree "${CLAUDE_SRC}/hooks"  "${AGENTS_SRC}/hooks"
migrate_tree "${CLAUDE_SRC}/skills" "${AGENTS_SRC}/skills"
# a skill link into the old .claude/skills tree (yours or the kit's) follows its dir
for d in "${CLAUDE_HOME}/skills" "${HOME}/.agents/skills"; do
  [[ -d "$d" ]] || continue
  while IFS= read -r l; do
    [[ "$(readlink "$l")" == "${CLAUDE_SRC}/skills/"* ]] || continue
    name="$(basename "$l")"
    [[ -d "${AGENTS_SRC}/skills/${name}" ]] || continue
    replace_with_symlink "$l" "${AGENTS_SRC}/skills/${name}"
    ok "  migrate     ${l/#$HOME/~} → .agents/skills/${name}"
  done < <(find "$d" -mindepth 1 -maxdepth 1 -type l 2>/dev/null)
done

# --- 1. AGENTS.md ------------------------------------------------------------
generate_agents_md() {              # fill the template from the gathered answers
  local content langline="" commsline="" wfline=""
  content="$(cat "${AGENTS_SRC}/AGENTS.template.md")"
  content="${content//\{\{NAME\}\}/$AM_NAME}"
  content="${content//\{\{ROLE\}\}/$AM_ROLE}"
  [[ -n "$AM_LANG" ]]     && langline="- ${AM_LANG}"
  [[ -n "$AM_COMMS" ]]    && commsline="- ${AM_COMMS}"
  [[ -n "$AM_WORKFLOW" ]] && wfline="- ${AM_WORKFLOW}"
  content="${content//\{\{LANGUAGE\}\}/$langline}"
  content="${content//\{\{COMMS\}\}/$commsline}"
  content="${content//\{\{WORKFLOW\}\}/$wfline}"
  printf '%s\n' "$content" > "${AGENTS_SRC}/AGENTS.md"
}
case "$AGENTS_ACTION" in
  "") ;;
  keep)
    ok "  AGENTS.md   kept the repo's existing file" ;;
  adopt)
    cp "$AM_ADOPT_FROM" "${AGENTS_SRC}/AGENTS.md"
    ok "  AGENTS.md   adopted ${AM_ADOPT_FROM/#$HOME/~}" ;;
  generate)
    generate_agents_md   # always write the template first; the interview (if chosen) refines it at the end
    if $AM_INTERVIEW; then ok "  AGENTS.md   template written — Claude will refine it via the interview at the end"
    else                   ok "  AGENTS.md   generated from template — flesh out the sections"; fi ;;
esac

# --- 2. settings.json — additive apply ---------------------------------------
frags=()
case "$SETTINGS_ACTION" in
  adopt)  frags+=("${CLAUDE_HOME}/settings.json") ;;
  create) frags+=("${CLAUDE_SRC}/settings/base.json") ;;
  update) frags+=("${CLAUDE_SRC}/settings.json") ;;
esac
for ((i = 0; i < N; i++)); do
  [[ "${C_KIND[i]}" == settings ]] || continue
  selected "$i" || continue
  [[ -f "${REPO_ROOT}/${C_SETTINGS[i]}" ]] || { warn "  unknown preset file for '${C_ID[i]}' — skipping"; continue; }
  frags+=("${REPO_ROOT}/${C_SETTINGS[i]}")
done
# Apply atomically: a failed jq (e.g. an edited preset with invalid JSON) must NOT leave a
# truncated settings.json behind — otherwise the recommended re-run would adopt the empty file.
if jq -s -L "${CLAUDE_SRC}/settings" 'include "merge"; reduce .[] as $frag ({}; apply(.; $frag))' "${frags[@]}" > "${CLAUDE_SRC}/settings.json.tmp"; then
  if [[ -f "${CLAUDE_SRC}/settings.json" ]] && cmp -s "${CLAUDE_SRC}/settings.json.tmp" "${CLAUDE_SRC}/settings.json"; then
    rm -f "${CLAUDE_SRC}/settings.json.tmp"
    ok "  settings    unchanged (presets: ${plist})"
  else
    mv -f "${CLAUDE_SRC}/settings.json.tmp" "${CLAUDE_SRC}/settings.json"
    ok "  settings    ${SETTINGS_ACTION}d (presets: ${plist})"
  fi
else
  rm -f "${CLAUDE_SRC}/settings.json.tmp"
  warn "  failed to apply the settings presets — is a fragment valid JSON? Nothing was written."
  exit 1
fi

# --- 3. link config into ~/.claude, ~/.agents, ~/.codex ----------------------
#     Preserves any existing real content by merging it into the repo first (no overwrite).
seed_repo_file() {                  # $1 = repo file a link needs; an absent JSON file starts as {}
  [[ -e "$1" ]] && return 0
  mkdir -p "$(dirname "$1")"
  if [[ "$1" == *.json ]]; then printf '{}\n' > "$1"; else : > "$1"; fi
}

link_one() {                        # $1 = home-relative path, $2 = repo-relative path, $3 = file|dir
  local home_rel="$1" repo_rel="$2" kind="$3"
  local home="${HOME}/${home_rel}" repo="${REPO_ROOT}/${repo_rel}" hf a

  if [[ "$kind" == "dir" ]]; then mkdir -p "$repo"; else seed_repo_file "$repo"; fi

  if symlink_ok "$home" "$repo"; then
    ok "  linked      ~/${home_rel} (already)"
    return 0
  fi

  if ours_link "$home"; then                      # an older link into this repo -> retarget silently
    rm -f "$home"
  elif [[ -L "$home" ]]; then                     # foreign symlink -> always confirm, never with --yes alone
    warn "  ~/${home_rel} -> $(readlink "$home") (expected ${repo})"
    if ! $INTERACTIVE; then echo "Error: refusing to replace a foreign symlink non-interactively: ~/${home_rel}" >&2; exit 1; fi
    read -r -p "  Replace this symlink? [y/N] " a || a=""
    [[ "$a" =~ ^[Yy]$ ]] || { say "  skip  ~/${home_rel}"; return 0; }
    rm -f "$home"
  elif [[ -e "$home" ]]; then                     # real file/dir -> merge into repo (preserve), then link
    if [[ "$kind" == "dir" ]]; then
      # file by file (BSD cp -n exits 1 on a skipped file): a missing file is copied, an identical
      # one is fine, a differing one is shadowed by the kit's version and left in place.
      local rel to failed=0
      while IFS= read -r hf; do
        rel="${hf#"$home"/}"; to="${repo}/${rel}"
        if [[ -e "$to" || -L "$to" ]]; then
          if ! { [[ -f "$hf" && -f "$to" ]] && cmp -s "$hf" "$to"; }; then
            warn "  note: ~/${home_rel}/${rel} is shadowed by the kit's version (yours is not copied)"
          fi
        else
          mkdir -p "$(dirname "$to")"
          cp -R "$hf" "$to" || failed=$((failed + 1))
        fi
      done < <(find "$home" \( -type f -o -type l \) 2>/dev/null)
      # Only remove the original AFTER the copy succeeds, so a failed merge never loses your data.
      if [[ $failed -gt 0 ]]; then
        warn "  could not merge ~/${home_rel} into the repo (${failed} file(s)) — leaving it in place, not linking"
        return 0
      fi
    else
      if [[ -s "$repo" ]] && ! cmp -s "$home" "$repo"; then
        cp "$home" "${home}.clankers-bak"
        warn "  note: ~/${home_rel} differs from the repo's — yours saved as ~/${home_rel}.clankers-bak"
      elif [[ ! -s "$repo" ]]; then
        cp "$home" "$repo"
      fi
    fi
    rm -rf "$home"
  fi

  mkdir -p "$(dirname "$home")"
  replace_with_symlink "$home" "$repo"
  ok "  linked      ~/${home_rel}"
}

for l in "${PLAN_LINKS[@]:-}"; do
  [[ -n "$l" ]] || continue
  IFS='|' read -r home_rel repo_rel ltype <<< "$l"
  link_one "$home_rel" "$repo_rel" "$ltype"
done

unlink_one() {                      # $1 = home-relative path, $2 = repo-relative path; the row was unchecked
  local home="${HOME}/$1" repo="${REPO_ROOT}/$2"
  ours_link "$home" || return 0
  rm -f "$home"
  if [[ -e "$repo" ]]; then cp -R "$repo" "$home"; ok "  unlinked    ~/$1 (now a real copy — the repo keeps its own)"
  else ok "  unlinked    ~/$1 (was dangling)"; fi
}
for l in "${LINKS_DROP[@]:-}"; do
  [[ -n "$l" ]] || continue
  unlink_one "${l%%|*}" "${l#*|}"
done

# --- 4. skills — activate by per-skill symlink in both skill homes (re-runnable) ------
SKILL_HOMES=("${CLAUDE_HOME}/skills" "${HOME}/.agents/skills")
for d in "${SKILL_HOMES[@]}"; do mkdir -p "$d"; done
activate_skill() {
  local name="$1" repo="${AGENTS_SRC}/skills/${1}" home d done=0
  [[ -d "$repo" ]] || { warn "  no such skill: ${name}"; return 0; }
  for d in "${SKILL_HOMES[@]}"; do
    home="${d}/${name}"
    if symlink_ok "$home" "$repo"; then done=$((done + 1)); continue; fi
    if ours_link "$home"; then rm -f "$home"                # an older link into this repo -> retarget
    elif [[ -e "$home" || -L "$home" ]]; then warn "  skip skill ${name}: ${home/#$HOME/~} already exists"; continue; fi
    replace_with_symlink "$home" "$repo"
  done
  if [[ $done -eq ${#SKILL_HOMES[@]} ]]; then ok "  skill       ${name} (already active)"; else ok "  skill       ${name} activated"; fi
}
deactivate_skill() {
  local name="$1" d
  for d in "${SKILL_HOMES[@]}"; do ours_link "${d}/${name}" && rm -f "${d}/${name}"; done
  ok "  skill       ${name} deactivated"
}
for s in "${SKILLS_WANT[@]:-}"; do [[ -n "$s" ]] && activate_skill "$s"; done
for s in "${SKILLS_DROP[@]:-}"; do [[ -n "$s" ]] && deactivate_skill "$s"; done

# --- 5. commands (the chrome-devtools MCP), only if opted in -----------------
for ci in "${CMDS[@]:-}"; do
  [[ -n "$ci" ]] || continue
  if [[ "${C_INSTALLED[ci]}" != "[]" ]] && run_argv "${C_INSTALLED[ci]}" >/dev/null 2>&1; then
    ok "  ${C_ID[ci]}         already installed"
  elif run_argv "${C_INSTALL[ci]}" >/dev/null 2>&1; then
    ok "  ${C_ID[ci]}         installed ${C_LABEL[ci]}"
  else
    warn "  ${C_ID[ci]}: install failed — run it later by hand: $(jq -r 'join(" ")' <<< "${C_INSTALL[ci]}")"
  fi
done

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
while IFS= read -r l; do ours_link "$l" && ACTIVE+=("$(basename "$l")"); done < <(find "${CLAUDE_HOME}/skills" "${HOME}/.agents/skills" -mindepth 1 -maxdepth 1 -type l 2>/dev/null | sort -u)
step "Done"
ok "  ~/.claude, ~/.agents$(has_agent codex && printf ', ~/.codex') → repo (memories tracked — keep the repo private)"
say "  active skills: $(printf '%s\n' "${ACTIVE[@]:-none}" | sort -u | tr '\n' ' ')"
info "  edit .agents/AGENTS.md, then restart your agent · re-run ./setup.sh to change the selection · undo any time with ./uninstall.sh"

# --- 8. Claude interview — deferred to the very end, once all wiring is done -------------------
# Runs in your real shell/HOME (where you're logged in) and hands off to Claude, which drafts your
# AGENTS.md over the template we just wrote. Never reached in --sandbox (offer was skipped there).
if $AM_INTERVIEW && $HAVE_CLAUDE; then
  step "Claude interview"
  info "  Setup is done. Handing off to Claude — answer its questions and it writes your AGENTS.md."
  interview_prompt="Help me set up my personal instructions file for my coding agents (read by Claude Code as CLAUDE.md and by Codex as AGENTS.md). Interview me with a few concise questions about my role, the languages I work in and how to read my typos, how I want you to present work (proposals, code citations, comment style), my tool/command habits, and my workflow habits (planning, PR hygiene, commit conventions, how I verify changes). Then write a terse, high-signal file to ${AGENTS_SRC}/AGENTS.md following the section structure in ${AGENTS_SRC}/AGENTS.template.md (Role, Language, Communication style, Tool & command preferences, Workflow habits). Use the name '${AM_NAME}' and role '${AM_ROLE}'. Every line is re-read each turn, so keep it lean. Do not put these instructions in the file."
  exec claude "$interview_prompt"
elif $SANDBOXED && $HAVE_CLAUDE && [[ "$AGENTS_ACTION" == generate ]]; then
  step "Claude interview"
  info "  ↑ In a real run, Claude would start here to interview you and draft your AGENTS.md."
  info "  Skipped in --sandbox — a throwaway HOME isn't logged in."
fi
