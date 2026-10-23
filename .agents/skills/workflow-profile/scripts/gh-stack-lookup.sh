#!/usr/bin/env bash
# A membership lookup over gh stack's (GitHub's stacked-PR extension) local metadata, read from
# the git common dir so it works from a linked worktree, not just the main one.
#
# CLI: `bash gh-stack-lookup.sh (--pr <n> | --branch <name>) [cwd]`

set -u

usage() {
  printf 'usage: gh-stack-lookup.sh (--pr <n> | --branch <name>) [cwd]\n' >&2
}

pr=""
branch=""
have_pr=0
have_branch=0
cwd=""
positional_set=0

while [ $# -gt 0 ]; do
  case "$1" in
    --pr)
      shift
      [ $# -gt 0 ] || { usage; exit 2; }
      pr="$1"
      have_pr=1
      shift
      ;;
    --branch)
      shift
      [ $# -gt 0 ] || { usage; exit 2; }
      branch="$1"
      have_branch=1
      shift
      ;;
    *)
      if [ "$positional_set" -eq 0 ]; then
        cwd="$1"
        positional_set=1
        shift
      else
        usage
        exit 2
      fi
      ;;
  esac
done

if [ "$have_pr" -eq 1 ] && [ "$have_branch" -eq 1 ]; then
  usage
  exit 2
fi
if [ "$have_pr" -eq 0 ] && [ "$have_branch" -eq 0 ]; then
  usage
  exit 2
fi

if [ "$have_pr" -eq 1 ]; then
  case "$pr" in
    ''|*[!0-9]*)
      usage
      exit 2
      ;;
  esac
fi

if [ "$have_branch" -eq 1 ] && [ -z "$branch" ]; then
  usage
  exit 2
fi

cwd="${cwd:-$PWD}"

common=$(command cd "$cwd" 2>/dev/null && git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
[ -n "$common" ] || exit 4

file="$common/gh-stack"
[ -f "$file" ] || exit 4

command -v jq >/dev/null 2>&1 || exit 127
jq empty "$file" >/dev/null 2>&1 || exit 5

# A parse-clean file with the wrong shape ({} or no .stacks) errors here; that is unknown, not
# absent, so the query's own status decides before the empty-output test does.
output=$(jq -r \
  --arg b "$branch" \
  --arg n "$pr" \
  '
  .stacks[]
  | select(
      ($b != "" and any(.branches[]; .branch == $b))
      or
      ($n != "" and any(.branches[]; ((.pullRequest.number // -1) | tostring) == $n))
    )
  | (.number // "untracked") as $num
  | (.trunk.branch // "?") as $trunk
  | [ .branches[]
      | "\(.branch)#\(.pullRequest.number // "-")"
        + (if .pullRequest.merged == true then " (merged)" else "" end)
    ] as $members
  | "stack \($num) (trunk \($trunk)): " + ($members | join(" -> "))
  ' "$file" 2>/dev/null) || exit 5

[ -n "$output" ] || exit 3

printf '%s\n' "$output"
