# Sourced library: resolve which workflow-profile files apply to a cwd, and read/merge their
# tables. Defines functions and globals only — running this file directly does nothing.
#
# Fails open: on any resolution failure (no git repo, no toplevel, bad remote) the PROFILE_*
# globals end up empty/basename-shaped and profile_resolved reports false; callers exit 0.

PROFILES_DIR="${AGENTS_WORKFLOW_PROFILES:-$HOME/.agents/workflow-profiles}"

# owner/repo from a git remote URL, parameter-expansion only. Handles:
#   https://github.com/owner/repo.git   https://github.com/owner/repo   https://host:443/owner/repo.git/
#   git@github.com:owner/repo.git       ssh://git@github.com:2222/owner/repo.git
# A URI form drops its authority (user@host:port) up to the first slash; the scp-like form
# splits on its colon. Empty results when the remainder holds no owner/repo pair.
_parse_remote_url() {
  local url="$1" rest
  url="${url%/}"
  url="${url%.git}"
  url="${url%/}"
  case "$url" in
    *://*) rest="${url#*://}"; rest="${rest#*/}" ;;
    *:*)   rest="${url#*:}" ;;
    *)     rest="$url" ;;
  esac
  rest="${rest#/}"
  case "$rest" in
    */*) ;;
    *) _PARSED_OWNER=""; _PARSED_REPO=""; return 0 ;;
  esac
  _PARSED_OWNER="${rest%%/*}"
  _PARSED_REPO="${rest#*/}"
  _PARSED_REPO="${_PARSED_REPO%%/*}"
}

_sanitize_key() {
  printf '%s' "$1" | tr -c 'A-Za-z0-9_.-' '-'
}

# resolve_profile <cwd> — sets PROFILE_KIND, PROFILE_OWNER, PROFILE_REPO, PROFILE_ORG_FILE,
# PROFILE_REPO_FILE, PROFILE_KEY. Always returns 0; a failed resolution just leaves the globals
# empty-ish (PROFILE_REPO empty), which profile_resolved reports as unresolved.
resolve_profile() {
  local cwd="$1" remote_url toplevel

  PROFILE_KIND=""
  PROFILE_OWNER=""
  PROFILE_REPO=""
  PROFILE_ORG_FILE=""
  PROFILE_REPO_FILE=""
  PROFILE_KEY=""

  remote_url=$(command cd "$cwd" 2>/dev/null && git remote get-url origin 2>/dev/null)

  if [ -n "$remote_url" ]; then
    PROFILE_KIND="remote"
    _parse_remote_url "$remote_url"
    PROFILE_OWNER="$_PARSED_OWNER"
    PROFILE_REPO="$_PARSED_REPO"
  else
    PROFILE_KIND="basename"
    toplevel=$(command cd "$cwd" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null)
    toplevel="${toplevel%/}"
    PROFILE_REPO="${toplevel##*/}"
  fi

  [ -n "$PROFILE_REPO" ] || return 0

  if [ "$PROFILE_KIND" = "remote" ] && [ -n "$PROFILE_OWNER" ]; then
    [ -f "$PROFILES_DIR/$PROFILE_OWNER.md" ] && PROFILE_ORG_FILE="$PROFILES_DIR/$PROFILE_OWNER.md"
  fi
  [ -f "$PROFILES_DIR/repos/$PROFILE_REPO.md" ] && PROFILE_REPO_FILE="$PROFILES_DIR/repos/$PROFILE_REPO.md"

  local sown srepo
  sown=$(_sanitize_key "$PROFILE_OWNER")
  srepo=$(_sanitize_key "$PROFILE_REPO")
  if [ "$PROFILE_KIND" = "remote" ]; then
    PROFILE_KEY="remote-${sown}-${srepo}"
  else
    PROFILE_KEY="basename-${srepo}"
  fi
  return 0
}

# profile_field <Field> — prints the repo override's value when present and not "—", else the
# org file's value when present and not "—", else nothing (and no trailing newline).
profile_field() {
  local target="$1" file prefix line val
  prefix="| $target |"
  for file in "$PROFILE_REPO_FILE" "$PROFILE_ORG_FILE"; do
    [ -n "$file" ] && [ -f "$file" ] || continue
    line=$(grep -Fm1 -- "$prefix" "$file" 2>/dev/null)
    [ -n "$line" ] || continue
    val="${line#"$prefix"}"
    [ "$val" != "$line" ] || continue          # grep hit but not anchored at line start
    val="${val%%|*}"
    val="${val#"${val%%[![:space:]]*}"}"       # trim leading space
    val="${val%"${val##*[![:space:]]}"}"       # trim trailing space
    [ "$val" = "—" ] && continue
    printf '%s' "$val"
    return 0
  done
  return 1
}

# _parse_table_line <line> — on a data row (anything but the header/separator) under a
# "| Field | Value |" table, sets _RF/_RV and returns 0; otherwise returns 1.
_parse_table_line() {
  local line="$1" rest
  case "$line" in
    '| '*' | '*' |') ;;
    *) return 1 ;;
  esac
  rest="${line#| }"
  _RF="${rest%% | *}"
  rest="${rest#*" | "}"
  _RV="${rest% |}"
  case "$_RF" in
    Field|---*) return 1 ;;
  esac
  return 0
}

# profile_rows — prints the merged "| Field | Value |" table: org file rows in their order,
# with repo-file rows replacing a matching field in place or appending when the field is new.
# An override row holding "—" (unset) never erases an inherited value, matching profile_field.
# No hardcoded field list — any row under the header counts.
profile_rows() {
  local -a fields=() values=()
  local file line idx j

  for file in "$PROFILE_ORG_FILE" "$PROFILE_REPO_FILE"; do
    [ -n "$file" ] && [ -f "$file" ] || continue
    while IFS= read -r line; do
      _parse_table_line "$line" || continue
      idx=-1
      for ((j = 0; j < ${#fields[@]}; j++)); do
        if [ "${fields[j]}" = "$_RF" ]; then
          idx=$j
          break
        fi
      done
      if [ "$idx" -ge 0 ]; then
        [ "$_RV" = "—" ] || values[idx]="$_RV"
      else
        fields+=("$_RF")
        values+=("$_RV")
      fi
    done < "$file"
  done

  printf '| Field | Value |\n| --- | --- |\n'
  for ((j = 0; j < ${#fields[@]}; j++)); do
    printf '| %s | %s |\n' "${fields[j]}" "${values[j]}"
  done
}

# profile_resolved — true when at least one of the org/repo files was found.
profile_resolved() {
  [ -n "$PROFILE_ORG_FILE" ] || [ -n "$PROFILE_REPO_FILE" ]
}

# CLI: `bash resolve-profile.sh [--rows|--field <Field>|--files] [cwd]` — the same resolution the hooks
# use, for a skill that finds no profile rows in context. Sourcing the file runs none of this.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  mode="${1:---rows}"
  case "$mode" in
    --field) shift; field="${1:-}"; shift; ;;
    *) shift ;;
  esac
  resolve_profile "${1:-$PWD}"
  if ! profile_resolved; then
    printf 'no workflow profile resolved for %s (%s). Files looked for: %s\n' "$PROFILE_REPO" "$PROFILE_KIND" "$PROFILES_DIR/${PROFILE_OWNER:-<owner>}.md, $PROFILES_DIR/repos/$PROFILE_REPO.md" >&2
    exit 1
  fi
  case "$mode" in
    --rows) profile_rows ;;
    --field) profile_field "$field"; printf '\n' ;;
    --files) printf '%s\n%s\n' "${PROFILE_ORG_FILE:-none}" "${PROFILE_REPO_FILE:-none}" ;;
    *) printf 'usage: resolve-profile.sh [--rows|--field <Field>|--files] [cwd]\n' >&2; exit 2 ;;
  esac
fi
