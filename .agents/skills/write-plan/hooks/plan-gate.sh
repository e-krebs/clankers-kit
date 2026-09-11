#!/usr/bin/env bash
# PreToolUse gate on ExitPlanMode: enforces the plan-file contract before a plan can be approved
# — the ten `## ` headings, in this order, plus content checks on Model pick (names a tiers-file
# model, no TBD/TODO/<placeholder>) and Plan review (names a reviewing agent). When the plan text
# holds a `Source: <path>.html` line, that HTML file is the plan: its <h2> texts become the
# headings and the text between each <h2> and the next becomes that section, tags stripped
# before the placeholder checks run — a missing HTML file fails open silently. Blocks when a
# workflow profile resolves for this cwd; otherwise advises the same message. A stall guard stops
# denying after 3 denials per session. Once the headings pass, it also scores the plan text (or,
# for an HTML plan, the tag-stripped body text) with style-metrics/measure.py --document and
# surfaces the misses as advisory context — style never blocks, so a python failure or a
# miss-free plan both stay silent on this front. Wired: PreToolUse, matcher ExitPlanMode.
# codex: no

MAX_DENIALS=3

input=$(jq -c 'select(type=="object")' 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0

hooks_lib="${AGENTS_HOOKS_LIB:-$(dirname "${BASH_SOURCE[0]}")/../../../hooks/lib}"
[ -f "$hooks_lib/hook-log.sh" ] || hooks_lib="$HOME/.claude/hooks/lib"
# shellcheck source=../../../hooks/lib/hook-log.sh
source "$hooks_lib/hook-log.sh"
HOOK_SESSION=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)

agent_id=$(printf '%s' "$input" | jq -r '.agent_id // empty' 2>/dev/null)
[ -z "$agent_id" ] || exit 0

plan_text=$(printf '%s' "$input" | jq -r '.tool_input.plan // empty' 2>/dev/null)
plan_file=$(printf '%s' "$input" | jq -r '.tool_input.planFilePath // empty' 2>/dev/null)
if [ -z "$plan_text" ]; then
  [ -n "$plan_file" ] || exit 0
  [ -f "$plan_file" ] || exit 0
  plan_text=$(< "$plan_file") 2>/dev/null
  [ -n "$plan_text" ] || exit 0
fi

# HTML source of truth: a `Source: <path>.html` line means the markdown is a stub and the named
# HTML file is the plan to check — its <h2> texts become the headings, and the text between each
# <h2> and the next (or the end) becomes that section. Path is relative to plan_file's directory
# when planFilePath was set and the path itself is relative; otherwise taken as given. A missing
# target fails open silently — no deny, no advisory, nothing on stdout.
html_mode=0
html_rel=""
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in
    "Source: "*.html) html_rel="${line#Source: }"; break ;;
  esac
done <<< "$plan_text"

if [ -n "$html_rel" ]; then
  case "$html_rel" in
    /*) html_path="$html_rel" ;;
    *)
      if [ -n "$plan_file" ]; then
        html_dir="${plan_file%/*}"
        [ "$html_dir" != "$plan_file" ] || html_dir="."
        html_path="$html_dir/$html_rel"
      else
        html_path="$html_rel"
      fi
      ;;
  esac
  [ -f "$html_path" ] || exit 0
  html_text=$(< "$html_path") 2>/dev/null
  [ -n "$html_text" ] || exit 0
  html_mode=1
fi

expected=("Context" "Decisions" "Ticket" "Approach + Files" "Model pick" "Deferred kickoff actions" "Steps + delegation" "Verification" "Closing steps" "Plan review")

heading_text=()
html_section_text=()
if [ "$html_mode" -eq 1 ]; then
  rest="$html_text"
  while :; do
    case "$rest" in
      *'<h2'*) ;;
      *) break ;;
    esac
    rest="${rest#*<h2}"     # strip through the "<h2" that opens the tag
    rest="${rest#*>}"       # strip attrs through the end of the opening tag
    h="${rest%%</h2>*}"     # this heading's text
    rest="${rest#*</h2>}"   # remainder of the document after this heading closes
    sect="${rest%%<h2*}"    # this heading's section: everything up to the next <h2>, or EOF
    heading_text+=("$h")
    html_section_text+=("$sect")
  done
else
  lines=()
  while IFS= read -r line || [ -n "$line" ]; do
    lines+=("$line")
  done <<< "$plan_text"

  heading_idx=()
  i=0
  for line in "${lines[@]}"; do
    case "$line" in
      '## '*)
        h="${line#'## '}"
        h="${h%"${h##*[![:space:]]}"}"
        heading_idx+=("$i")
        heading_text+=("$h")
        ;;
    esac
    i=$((i + 1))
  done
fi

fail=""
rule=""
n=0
for exp in "${expected[@]}"; do
  got="${heading_text[$n]:-}"
  if [ "$got" != "$exp" ]; then
    if [ -z "$got" ]; then
      fail="plan-gate: heading #$((n + 1)) is missing — expected '${exp}'."
      rule="heading"
    else
      fail="plan-gate: heading #$((n + 1)) should be '${exp}', found '${got}' — the ten headings must appear in order."
      rule="heading"
    fi
    break
  fi
  n=$((n + 1))
done

# _style_advisory <plan-text> — measure.py --document's misses, one line, prefixed for the
# reader; empty when clean, when python3/measure.py is unavailable, or on any failure. Advisory
# only: its result is never folded into $fail, so a style miss can never block the plan.
_style_advisory() {
  local measure tmp out lines
  # cd -P resolves the hook's physical directory first, so a call through a ~/.claude symlink
  # still lands on the repo's style-metrics rather than on a missing ~/.claude sibling.
  measure="$(CDPATH='' cd -P "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/../../../../.claude/style-metrics/measure.py"
  command -v python3 >/dev/null 2>&1 || return 0
  [ -f "$measure" ] || return 0
  tmp=$(mktemp "${TMPDIR:-/tmp}/claude-plangate-style-XXXXXX" 2>/dev/null) || return 0
  printf '%s' "$1" > "$tmp" 2>/dev/null
  out=$(python3 "$measure" --text "$tmp" --document --json 2>/dev/null)
  rm -f "$tmp" 2>/dev/null
  [ -n "$out" ] || return 0
  lines=$(printf '%s' "$out" | jq -r '.lines[]?' 2>/dev/null | tr '\n' ' ')
  lines="${lines% }"
  [ -n "$lines" ] || return 0
  printf 'plan-gate style (advisory): %s' "$lines"
}

# _strip_tags <text> — removes every "<...>" run (HTML tags) before a placeholder regex runs,
# so an HTML tag is never misread as a `<...>` placeholder. Bash only, per spec: no sed/awk.
_strip_tags() {
  local s="$1"
  while case "$s" in *'<'*'>'*) true;; *) false;; esac; do
    s="${s%%<*}${s#*>}"
  done
  printf '%s' "$s"
}

# Only once the headings pass: a plan with the wrong shape gets the heading failure, not a style
# note on top of it. Computed here, used later — a later Model pick / Plan review failure still
# routes to $fail as before, and the advisory is simply not attached to a deny.
style_ctx=""
if [ -z "$fail" ]; then
  if [ "$html_mode" -eq 1 ]; then
    body="$html_text"
    case "$body" in
      *'<body'*)
        body="${body#*<body}"
        body="${body#*>}"
        body="${body%%</body>*}"
        ;;
    esac
    style_ctx=$(_style_advisory "$(_strip_tags "$body")")
  else
    style_ctx=$(_style_advisory "$plan_text")
  fi
fi

# _model_alternation <tiers-file> — prints a "Name1|Name2|..." regex built from the Claude and
# Codex columns of the model-tiers table, or the fallback list when the file is absent.
_model_alternation() {
  local file="$1" line rest cell w out=""
  if [ -f "$file" ]; then
    while IFS= read -r line; do
      case "$line" in
        '| '*' | '*' | '*' | '*' |') ;;
        *) continue ;;
      esac
      rest="${line#| }"
      rest="${rest#*" | "}"
      rest="${rest#*" | "}"
      cell="${rest%% | *}"
      case "$cell" in Claude|---*) continue ;; esac
      for w in $(printf '%s' "$cell" | grep -oE '[A-Za-z]+' 2>/dev/null); do
        [ "$w" = "workers" ] || out="${out:+$out|}$w"
      done
      cell="${rest#*" | "}"
      cell="${cell%" |"}"
      for w in $(printf '%s' "$cell" | grep -oE '[A-Za-z]+' 2>/dev/null); do
        [ "$w" = "workers" ] || out="${out:+$out|}$w"
      done
    done < "$file"
  fi
  [ -n "$out" ] || out="Sonnet|Opus|Fable|Luna|Sol|Astra"
  printf '%s' "$out"
}

# section_text <expected-index (0-based)> — text mode only: prints the lines between that
# heading and the next, using heading_idx/lines built above.
section_text() {
  local idx="$1" start end out="" j
  start=$(( ${heading_idx[$idx]} + 1 ))
  if [ -n "${heading_idx[$((idx + 1))]:-}" ]; then
    end=$(( ${heading_idx[$((idx + 1))]} - 1 ))
  else
    end=$(( ${#lines[@]} - 1 ))
  fi
  for ((j = start; j <= end; j++)); do
    out="${out}${lines[$j]}
"
  done
  printf '%s' "$out"
}

# get_section <expected-index (0-based)> — html_mode: the h2-delimited slice with tags
# stripped; text mode: section_text's markdown slice, unchanged (no stripping: a literal
# `<placeholder>` in markdown is meant to be caught).
get_section() {
  local idx="$1"
  if [ "$html_mode" -eq 1 ]; then
    _strip_tags "${html_section_text[$idx]:-}"
  else
    section_text "$idx"
  fi
}

if [ -z "$fail" ]; then
  tiers_file="${HOME}/.agents/skills/write-plan/references/model-tiers.md"
  model_pick=$(get_section 4)
  models=$(_model_alternation "$tiers_file")
  if ! printf '%s' "$model_pick" | grep -qE "$models"; then
    fail="plan-gate: the Model pick section names no model from the tiers file."
    rule="model"
  elif printf '%s' "$model_pick" | grep -qE 'TBD|TODO|<[^>]*>'; then
    fail="plan-gate: the Model pick section still holds a placeholder (TBD/TODO/<...>)."
    rule="model"
  fi
fi

if [ -z "$fail" ]; then
  plan_review=$(get_section 9)
  if ! printf '%s' "$plan_review" | grep -qiE 'codex|claude|opus|sonnet|fable|gpt|astra|sol|luna'; then
    fail="plan-gate: the Plan review section names no reviewing agent."
    rule="review"
  fi
fi

if [ -z "$fail" ]; then
  if [ -n "$style_ctx" ]; then
    hook_log advise style
    jq -nc --arg ctx "$style_ctx" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$ctx}}'
  fi
  exit 0
fi

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$cwd" ] || cwd=$PWD

resolver="${AGENTS_WORKFLOW_RESOLVER:-$HOME/.agents/skills/workflow-profile/scripts/resolve-profile.sh}"
resolved=1
# shellcheck source=../../workflow-profile/scripts/resolve-profile.sh
if [ -f "$resolver" ] && source "$resolver" 2>/dev/null; then
  resolve_profile "$cwd"
  profile_resolved || resolved=0
else
  resolved=0                                     # no setup skill installed: advise, never deny
fi

if [ "$resolved" -eq 1 ]; then
  session=$(printf '%s' "$input" | jq -r '.session_id // "unknown"' 2>/dev/null)
  counter="${TMPDIR:-/tmp}/claude-plan-gate-${session//[^A-Za-z0-9_-]/}"
  d=0
  [ -f "$counter" ] && d=$(< "$counter")
  case "$d" in ''|*[!0-9]*) d=0 ;; esac
  if [ "$d" -ge "$MAX_DENIALS" ]; then
    hook_log advise "budget:${rule:--}"
    exit 0
  fi
  printf '%s' "$((d + 1))" > "$counter" 2>/dev/null || exit 0   # no counter, no escape hatch: allow
  hook_log deny "$rule"
  jq -nc --arg r "$fail" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
fi

hook_log advise "no-profile:${rule:--}"
jq -nc --arg ctx "$fail" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$ctx}}'
exit 0
