#!/usr/bin/env bash
# The write-plan plan checker, harness-neutral: the Claude and Codex gate adapters call it.
# The tier of the session that runs the plan and the delegable tiers are the tiers.md rows by Kind; no tier name
# is written here, and a tiers.md without them fails the rule `tiers`.
# Usage: plan-check.sh --plan <path> [--plan-file-path <path>] [--cwd <dir>]. The six `## `
# headings (Summary, Decisions, Steps, Run, Plan review, Briefs) must appear in order; headings
# are scanned outside ``` and ~~~ fences only, and a `### S<n>` inside a <details> fold still
# counts. Then, one rule at a time: Steps holds the pinned table with valid State cells (steps),
# ends on the Review, Gates, Approval and Hand-off rows with a `<tier> tier × <n>` Review
# (closing), every Tier cell is a tier name from tiers.md, never the tier of the session that writes the plan, every Done when cell but Approval's and
# Hand-off's is one backticked span (done-when), and every delegated row has a `### <id>` heading or the `Briefs:`
# pointer line under Briefs (brief); with --plan-file-path, a pointer's brief files must exist and be non-empty (brief). Run holds a fence with either the one line
# `claude --agent <tier of the running session> "/execute-plan <path>"`, or the one line `codex -m <model> -c
# model_reasoning_effort=<effort> "Execute the plan at <path>"`, where <path> equals
# --plan-file-path when given (fence). Another agent name is denied (run); a Codex model and effort
# equal codex.md's row for the tier of the running session (run). The Run text holds no TBD/TODO/<placeholder>, names a tier,
# and names an absolute run-rules.md path (run). Plan review names a reviewing agent (review).
# First failure: "deny<TAB><rule><TAB><message>" and exit 1 when a workflow profile resolves for
# --cwd, else "advise<TAB>unresolved-profile:<rule><TAB><message>" and exit 0. A pass prints one
# "advise<TAB>link<TAB>..." line per absolute link to a missing file and one
# "advise<TAB>brief<TAB>..." line per brief file above 25 non-blank lines, then exits 0.
# An unreadable or empty plan
# prints nothing and exits 2. No stdin, no stall counter, no JSON: the adapters own those.

STEPS_HEADER='| State | # | Task | Tier | After | Done when | Files |'
CLAUDE_RUN='^claude --agent ([^ ]+) "/execute-plan (/[^"]*\.md)"$'
CODEX_RUN='^codex -m ([^ ]+) -c model_reasoning_effort=([^ ]+) "Execute the plan at (/[^"]*\.md)"$'

plan="" plan_file="" cwd=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --plan) plan="${2:-}" ;;
    --plan-file-path) plan_file="${2:-}" ;;
    --cwd) cwd="${2:-}" ;;
    *) shift; continue ;;
  esac
  shift
  [ "$#" -eq 0 ] || shift
done

[ -n "$plan" ] && [ -f "$plan" ] && [ -r "$plan" ] || exit 2
plan_text=$(< "$plan") 2>/dev/null
[ -n "$plan_text" ] || exit 2
[ -n "$cwd" ] || cwd=$PWD

models_dir="${AGENTS_WORKFLOW_MODELS:-$HOME/.agents/workflow-models}"
# shellcheck source=plan-tiers.sh
source "$(dirname "${BASH_SOURCE[0]}")/plan-tiers.sh" || exit 2
run_tier=$(_tier_of_kind "$RUN_KIND")
delegable=$(_delegable_tiers)

_emit() { printf '%s\t%s\t%s\n' "$1" "$2" "$3"; }

expected=("Summary" "Decisions" "Steps" "Run" "Plan review" "Briefs")

_trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

lines=()
while IFS= read -r line || [ -n "$line" ]; do
  lines+=("$line")
done <<< "$plan_text"

# _fence <line>: a ``` or ~~~ run after up to 3 spaces sets fence_mark and fence_rest
_fence() {
  local s="$1" c k=0
  while [ "$k" -lt 3 ] && [ "${s# }" != "$s" ]; do s="${s# }"; k=$((k + 1)); done
  case "$s" in
    '```'*) c='`' ;;
    '~~~'*) c='~' ;;
    *) return 1 ;;
  esac
  fence_mark=""
  while [ "${s#"$c"}" != "$s" ]; do fence_mark="$fence_mark$c"; s="${s#"$c"}"; done
  fence_rest="$s"
}

# fenced[i]=1 for a fence delimiter line and every line between a pair; fence_delim[i] is
# open or close on a delimiter. A fence closes only on its own char repeated at least as long,
# so a quoted fence nests.
fenced=()
fence_delim=()
heading_idx=()
heading_text=()
open_mark=""
for ((i = 0; i < ${#lines[@]}; i++)); do
  line="${lines[$i]}"
  fence_delim[i]=""
  if _fence "$line"; then
    if [ -z "$open_mark" ]; then
      open_mark="$fence_mark"
      fenced[i]=1 fence_delim[i]=open
      continue
    fi
    case "$fence_rest" in
      *[![:space:]]*) ;;
      *)
        if [ "${fence_mark:0:1}" = "${open_mark:0:1}" ] && [ "${#fence_mark}" -ge "${#open_mark}" ]; then
          open_mark=""
          fenced[i]=1 fence_delim[i]=close
          continue
        fi
        ;;
    esac
  fi
  if [ -n "$open_mark" ]; then fenced[i]=1; continue; fi
  fenced[i]=0
  case "$line" in
    '## '*)
      h="${line#'## '}"
      h="${h%"${h##*[![:space:]]}"}"
      heading_idx+=("$i")
      heading_text+=("$h")
      ;;
  esac
done

fail=""
rule=""
n=0
for exp in "${expected[@]}"; do
  got="${heading_text[$n]:-}"
  if [ "$got" != "$exp" ]; then
    if [ -z "$got" ]; then
      fail="plan-gate: heading #$((n + 1)) is missing — expected '${exp}'."
    else
      fail="plan-gate: heading #$((n + 1)) should be '${exp}', found '${got}' — the six headings must appear in order."
    fi
    rule="heading"
    break
  fi
  n=$((n + 1))
done

# section_range <expected-index (0-based)> — prints "start end" line indexes of that section's body
section_range() {
  local idx="$1" start end
  start=$(( ${heading_idx[$idx]} + 1 ))
  if [ -n "${heading_idx[$((idx + 1))]:-}" ]; then
    end=$(( ${heading_idx[$((idx + 1))]} - 1 ))
  else
    end=$(( ${#lines[@]} - 1 ))
  fi
  printf '%s %s' "$start" "$end"
}

section_text() {
  local start end out="" j
  read -r start end <<< "$(section_range "$1")"
  for ((j = start; j <= end; j++)); do
    out="${out}${lines[$j]}
"
  done
  printf '%s' "$out"
}

# _model_alternation <models-dir> — prints a "name1|name2|..." regex built from the Model column
# of every tier table in that dir, or nothing when none is there.
_model_alternation() {
  local f
  for f in "$1"/*.md; do
    [ -f "$f" ] && _column "$f" Model | cut -f2
  done | sort -u | sed 's/\./\\./g' | paste -sd'|' -
}

# _tier_names: every Tier of tiers.md, one per line, lowercased
_tier_names() { _column "$models_dir/tiers.md" Tier 2>/dev/null | cut -f1 | tr '[:upper:]' '[:lower:]'; }

# _run_tier_cell <file> <column>: the cell of the running session tier's row of a tier file, lowercased
_run_tier_cell() {
  _column "$1" "$2" | awk -F'\t' -v t="$run_tier" 'tolower($1) == t { print tolower($2); exit }'
}

if [ -z "$fail" ] && [ -z "$run_tier" ]; then
  fail="plan-gate: tiers.md in $models_dir is missing or has no Kind column naming the tier that runs the plan, so the tier checks cannot run."
  rule="tiers"
fi

# Steps table: rows as parallel arrays, parsed once
row_id=(); row_task=(); row_tier=(); row_state=(); row_done=()
if [ -z "$fail" ]; then
  read -r s_start s_end <<< "$(section_range 2)"
  header_at=-1
  for ((j = s_start; j <= s_end; j++)); do
    [ "${fenced[$j]}" -eq 0 ] || continue
    if [ "$(_trim "${lines[$j]}")" = "$STEPS_HEADER" ]; then header_at=$j; break; fi
  done
  malformed=0
  if [ "$header_at" -ge 0 ]; then
    for ((j = header_at + 2; j <= s_end; j++)); do
      line=$(_trim "${lines[$j]}")
      case "$line" in '|'*) ;; *) break ;; esac
      line="${line//\\|/$'\x01'}"
      line="${line#|}"
      line="${line%|}"
      IFS='|' read -ra cells <<< "$line"
      if [ "${#cells[@]}" -ne 7 ]; then malformed=1; break; fi
      row_state+=("$(_trim "${cells[0]}")")
      row_id+=("$(_trim "${cells[1]}")")
      row_task+=("$(_trim "${cells[2]}")")
      row_tier+=("$(_trim "${cells[3]}")")
      row_done+=("$(_trim "${cells[5]}")")
    done
  fi
  has_s_row=0
  for id in "${row_id[@]}"; do
    [[ "$id" =~ ^S[0-9]+$ ]] && has_s_row=1
  done
  bad_state=0
  for st in "${row_state[@]}"; do
    case "$st" in '➖'|'▶️'|'▶'|'✅') ;; *) bad_state=1 ;; esac
  done
  if [ "$header_at" -lt 0 ] || [ "$malformed" -eq 1 ] || [ "$has_s_row" -eq 0 ] || [ "$bad_state" -eq 1 ]; then
    fail="plan-gate: the Steps section has no table with the header '${STEPS_HEADER}' and at least one row."
    rule="steps"
  fi
fi

if [ -z "$fail" ]; then
  count=${#row_id[@]}
  closing_ok=1
  if [ "$count" -lt 4 ]; then
    closing_ok=0
  else
    k=0
    for name in Review Gates Approval Hand-off; do
      case "${row_task[$((count - 4 + k))]}" in "$name"*) ;; *) closing_ok=0 ;; esac
      k=$((k + 1))
    done
    printf '%s' "${row_task[$((count - 4))]}" | grep -qE 'tier (×|x) [0-9]+' || closing_ok=0
    rt=$(printf '%s' "${row_task[$((count - 4))]}" | sed -nE 's/.*[ ,]([A-Za-z]+) tier (×|x) [0-9]+.*/\1/p' | tr '[:upper:]' '[:lower:]')
    { [ -n "$rt" ] && printf '%s\n' "$delegable" | grep -qx "$rt"; } || closing_ok=0
  fi
  if [ "$closing_ok" -eq 0 ]; then
    fail="plan-gate: Steps must end with the Review, Gates, Approval and Hand-off rows, and the Review row's Task must name '<tier> tier × <n>'."
    rule="closing"
  fi
fi

if [ -z "$fail" ]; then
  for ((k = 0; k < ${#row_id[@]}; k++)); do
    t=$(printf '%s' "${row_tier[$k]}" | tr '[:upper:]' '[:lower:]')
    if ! printf '%s\n' "$delegable" | grep -qx "$t"; then
      fail="plan-gate: Steps row ${row_id[$k]} has tier '${row_tier[$k]}', which is not delegable; use a worker tier from tiers.md or '$run_tier'."
      rule="tier"
      break
    fi
  done
fi

if [ -z "$fail" ]; then
  done_re="^\`[^\`]+\`\$"
  for ((k = 0; k < ${#row_id[@]}; k++)); do
    case "${row_task[$k]}" in Approval*|Hand-off*) continue ;; esac
    if ! [[ "${row_done[$k]}" =~ $done_re ]]; then
      fail="plan-gate: Steps row ${row_id[$k]} has a Done when that is not one backticked command."
      rule="done-when"
      break
    fi
  done
fi

# _delegated_ids: the id of every Steps row whose tier is not the running session's, one per line
_delegated_ids() {
  local k
  for ((k = 0; k < ${#row_id[@]}; k++)); do
    [ "$(printf '%s' "${row_tier[$k]}" | tr '[:upper:]' '[:lower:]')" = "$run_tier" ] || printf '%s\n' "${row_id[$k]}"
  done
}

pointer=0
if [ -z "$fail" ]; then
  read -r b_start b_end <<< "$(section_range 5)"
  brief_ids=" "
  for ((j = b_start; j <= b_end; j++)); do
    [ "${fenced[$j]}" -eq 0 ] || continue
    case "${lines[$j]}" in
      'Briefs: '*'.briefs/'*)
        pointer=1
        pointer_dir="${lines[$j]#'Briefs: '}"
        pointer_dir="${pointer_dir%%, *}"
        pointer_dir="${pointer_dir%/}"
        ;;
      '### '*)
        id="${lines[$j]#'### '}"
        id="${id%% *}"
        brief_ids="${brief_ids}${id} "
        ;;
    esac
  done
  for id in $(_delegated_ids); do
    [ "$pointer" -eq 0 ] || break
    case "$brief_ids" in
      *" $id "*) ;;
      *)
        fail="plan-gate: Steps row $id is delegated, but Briefs has no '### $id'."
        rule="brief"
        break
        ;;
    esac
  done
  if [ -z "$fail" ] && [ "$pointer" -eq 1 ] && [ -n "$plan_file" ]; then
    if [ "$pointer_dir" != "${plan_file%.md}.briefs" ]; then
      fail="plan-gate: the Briefs pointer names $pointer_dir; the brief files must sit at ${plan_file%.md}.briefs."
      rule="brief"
    fi
    for id in $(_delegated_ids); do
      [ -z "$fail" ] || break
      brief_file="${plan_file%.md}.briefs/$id.md"
      if [ ! -s "$brief_file" ]; then
        fail="plan-gate: Steps row $id is delegated, but its brief file $brief_file is missing or empty."
        rule="brief"
        break
      fi
    done
  fi
fi

# _path_ok <execute-path>: true when no --plan-file-path was given or the path equals it
_path_ok() { [ -z "$plan_file" ] || [ "$1" = "$plan_file" ]; }

# Run: the first fence holding exactly the one Claude line or the one Codex line
if [ -z "$fail" ]; then
  read -r r_start r_end <<< "$(section_range 3)"
  fence_model=""
  fence_form=""
  fence_ok=0
  bad_agent=""
  blk_claude="" blk_codex="" blk_codex_effort="" blk_lines=0 in_blk=0
  run_effort=""
  for ((j = r_start; j <= r_end; j++)); do
    line="${lines[$j]}"
    [ "$fence_ok" -eq 0 ] || continue
    case "${fence_delim[$j]}" in
      open)
        in_blk=1 blk_claude="" blk_codex="" blk_codex_effort="" blk_lines=0
        continue
        ;;
      close)
        in_blk=0
        if [ "$blk_lines" -eq 1 ] && [ -n "$blk_claude" ]; then
          fence_ok=1 fence_form=claude
        elif [ "$blk_lines" -eq 1 ] && [ -n "$blk_codex" ]; then
          fence_ok=1 fence_form=codex fence_model="$blk_codex" run_effort="$blk_codex_effort"
        fi
        continue
        ;;
    esac
    [ "$in_blk" -eq 1 ] || continue
    line=$(_trim "$line")
    [ -z "$line" ] || blk_lines=$((blk_lines + 1))
    case "$line" in
      'claude '*)
        if [[ "$line" =~ $CLAUDE_RUN ]] && _path_ok "${BASH_REMATCH[2]}"; then
          if [ "${BASH_REMATCH[1]}" = "$run_tier" ]; then blk_claude=1; else bad_agent="${BASH_REMATCH[1]}"; fi
        fi
        ;;
      'codex '*) [[ "$line" =~ $CODEX_RUN ]] && _path_ok "${BASH_REMATCH[3]}" && blk_codex="${BASH_REMATCH[1]}" blk_codex_effort="${BASH_REMATCH[2]}" ;;
    esac
  done
  if [ "$fence_ok" -eq 0 ] && [ -n "$bad_agent" ]; then
    fail="plan-gate: the Run fence names agent '$bad_agent'; the line must be: claude --agent $run_tier \"/execute-plan ${plan_file:-<plan path>}\""
    rule="run"
  elif [ "$fence_ok" -eq 0 ]; then
    fail="plan-gate: the Run section has no fenced block holding only the line 'claude --agent $run_tier \"/execute-plan ${plan_file:-<plan path>}\"', or the one line 'codex -m <model> -c model_reasoning_effort=<effort> \"Execute the plan at <plan path>\"'."
    rule="fence"
  fi
fi

if [ -z "$fail" ]; then
  if [ "$fence_form" = codex ]; then
    form_models=""
    [ -f "$models_dir/codex.md" ] && form_models=$(_column "$models_dir/codex.md" Model | cut -f2 | tr '[:upper:]' '[:lower:]')
    want=$(printf '%s' "$fence_model" | tr '[:upper:]' '[:lower:]')
    if [ -n "$form_models" ] && ! printf '%s\n' "$form_models" | grep -qxF "$want"; then
      fail="plan-gate: the Run section names no model from ~/.agents/workflow-models/codex.md."
      rule="run"
    fi
    if [ -z "$fail" ] && [ -n "$form_models" ]; then
      want_model=$(_run_tier_cell "$models_dir/codex.md" Model)
      want_effort=$(_run_tier_cell "$models_dir/codex.md" Effort)
      got_effort=$(printf '%s' "$run_effort" | tr '[:upper:]' '[:lower:]')
      if [ -n "$want_model" ] && { [ "$want" != "$want_model" ] || [ "$got_effort" != "$want_effort" ]; }; then
        fail="plan-gate: the Run section must name the $run_tier row of codex.md: $want_model at $want_effort effort, not $fence_model at $run_effort."
        rule="run"
      fi
    fi
  fi
  if [ -z "$fail" ] && ! section_text 3 | sed -e 's/run-rules//g' -e "s/--agent $run_tier//g" | grep -qiwE "$(_tier_names | paste -sd'|' -)"; then
    fail="plan-gate: the Run section names no tier."
    rule="run"
  fi
  if [ -z "$fail" ] && section_text 3 | grep -qE 'TBD|TODO|<[^>]*>'; then
    fail="plan-gate: the Run section still holds a placeholder (TBD/TODO/<...>)."
    rule="run"
  fi
  if [ -z "$fail" ] && ! section_text 3 | grep -qE '(^|[^[:alnum:]_.~-])/[^[:space:]`)]*/execute-plan/references/run-rules\.md'; then
    fail="plan-gate: the Run section names no absolute path to execute-plan/references/run-rules.md."
    rule="run"
  fi
fi

if [ -z "$fail" ]; then
  models=$(_model_alternation "$models_dir")
  if ! section_text 4 | grep -qiwE "codex|claude|gpt${models:+|$models}"; then
    fail="plan-gate: the Plan review section names no reviewing agent."
    rule="review"
  fi
fi

if [ -z "$fail" ]; then
  unfenced=""
  for ((j = 0; j < ${#lines[@]}; j++)); do
    [ "${fenced[$j]}" -eq 0 ] && unfenced="${unfenced}${lines[$j]}
"
  done
  while IFS= read -r target; do
    [ -n "$target" ] || continue
    path="${target%%#*}"
    [ -e "$path" ] && continue
    _emit advise link "plan-gate: the plan links a file that does not exist: ${path}."
  done <<< "$(printf '%s' "$unfenced" | grep -oE '\]\(/[^) ]+\)' | sed -e 's/^](//' -e 's/)$//' | awk '!seen[$0]++')"
  if [ -n "$plan_file" ] && [ "$pointer" -eq 1 ]; then
    for id in $(_delegated_ids); do
      brief_file="${plan_file%.md}.briefs/$id.md"
      brief_lines=$(awk 'NF { n++ } END { print n + 0 }' "$brief_file")
      [ "$brief_lines" -le 25 ] || _emit advise brief "plan-gate: brief file $brief_file has $brief_lines non-blank lines; keep a brief to 25 non-blank lines or fewer."
    done
  fi
  exit 0
fi

resolver="${AGENTS_WORKFLOW_RESOLVER:-$HOME/.agents/skills/workflow-profile/scripts/resolve-profile.sh}"
resolved=1
# shellcheck source=/dev/null
if [ -f "$resolver" ] && source "$resolver" 2>/dev/null; then
  resolve_profile "$cwd"
  profile_resolved || resolved=0
else
  resolved=0                                     # no resolver in bin/: advise, never deny
fi

if [ "$resolved" -eq 1 ]; then
  _emit deny "$rule" "$fail"
  exit 1
fi
_emit advise "unresolved-profile:$rule" "$fail"
exit 0
