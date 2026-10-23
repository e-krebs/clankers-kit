#!/usr/bin/env bash
# Sets the State cell of one Steps table row in a plan: set-state.sh <plan> <S<n>> <glyph>
set -euo pipefail

STEPS_HEADER='| State | # | Task | Tier | After | Done when | Files |'
FENCE_RE='^ {0,3}(```+|~~~+)(.*)$'

_fail() {
  printf 'set-state: %s\n' "$1" >&2
  exit 1
}

_trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

[ "$#" -eq 3 ] || _fail "usage: set-state.sh <plan> <S<n>> <glyph>"
plan=$1 id=$2 glyph=$3
case "$glyph" in '➖'|'▶️'|'✅') ;; *) _fail "glyph '$glyph' is not ➖, ▶️ or ✅" ;; esac
{ [ -f "$plan" ] && [ -r "$plan" ]; } || _fail "cannot read plan '$plan'"

lines=()
while IFS= read -r line || [ -n "$line" ]; do
  lines+=("$line")
done < "$plan"
no_eol=0
[ -z "$(tail -c 1 "$plan")" ] || no_eol=1

in_steps=0 in_table=0 have_table=0 hits=0
fence_char="" fence_len=0
out=()
for ((i = 0; i < ${#lines[@]}; i++)); do
  line=${lines[i]}
  cur=$line
  trimmed=$(_trim "$line")

  if [[ $line =~ $FENCE_RE ]]; then
    marker=${BASH_REMATCH[1]}
    if [ -z "$fence_char" ]; then
      fence_char=${marker:0:1} fence_len=${#marker}
    elif [ "${marker:0:1}" = "$fence_char" ] && [ "${#marker}" -ge "$fence_len" ] \
      && [ -z "$(_trim "${BASH_REMATCH[2]}")" ]; then
      fence_char="" fence_len=0
    fi
  elif [ -n "$fence_char" ]; then
    :
  elif [[ $line =~ ^##[[:space:]] ]]; then
    in_steps=0 in_table=0
    [ "$trimmed" = "## Steps" ] && in_steps=1
  elif [ "$in_steps" -eq 1 ] && [ "$trimmed" = "$STEPS_HEADER" ]; then
    have_table=1 in_table=1
  elif [ "$in_table" -eq 1 ] && [[ $trimmed == \|* ]]; then
    prefix=${line%%|*}
    rest=${line#"$prefix"}
    rest=${rest#|}
    state=${rest%%|*}
    after=${rest#"$state"}
    cell=${after#|}
    cell=$(_trim "${cell%%|*}")
    if [ "$cell" = "$id" ]; then
      hits=$((hits + 1))
      lead=${state%%[![:space:]]*}
      tail=${state##*[![:space:]]}
      cur="$prefix|$lead$glyph$tail$after"
    fi
  else
    in_table=0
  fi
  out+=("$cur")
done

[ "$have_table" -eq 1 ] || _fail "no Steps table in $plan"
[ "$hits" -gt 0 ] || _fail "no Steps table row $id in $plan"
[ "$hits" -eq 1 ] || _fail "Steps table row $id appears $hits times in $plan"

tmp=$(mktemp "$plan.XXXXXX")
trap 'rm -f "$tmp"' EXIT
for ((i = 0; i < ${#out[@]}; i++)); do
  if [ "$i" -gt 0 ]; then printf '\n'; fi
  printf '%s' "${out[i]}"
done > "$tmp"
if [ "$no_eol" -eq 0 ]; then printf '\n' >> "$tmp"; fi
mode=$(stat -c %a "$plan" 2>/dev/null || stat -f %Lp "$plan")
chmod "$mode" "$tmp"
mv "$tmp" "$plan"
