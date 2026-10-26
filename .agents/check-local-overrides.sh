#!/usr/bin/env bash
# Guard .claude/settings.local.json: only skillOverrides with "on" values, parseable, and committable (not git-ignored).
# Usage: bash .agents/check-local-overrides.sh [--allow-missing] [repo root]   (root defaults to this script's parent)
set -euo pipefail

allow_missing=0
root=""
for arg in "$@"; do
  case "$arg" in
    --allow-missing) allow_missing=1 ;;
    *) root="$arg" ;;
  esac
done
root="${root:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"
file="${root}/.claude/settings.local.json"
fail=0
finding() { echo "check-local-overrides: $*" >&2; fail=1; }

if [ ! -f "$file" ]; then
  [ "$allow_missing" -eq 1 ] && exit 0
  finding "missing ${file}"; exit 1
fi
jq -e . "$file" >/dev/null 2>&1 || { finding "not valid JSON: ${file}"; exit 1; }
jq -e 'keys == ["skillOverrides"]' "$file" >/dev/null 2>&1 \
  || finding "top-level keys must be exactly [\"skillOverrides\"]: ${file}"
jq -e '(.skillOverrides | type == "object") and ([.skillOverrides[]] | all(. == "on"))' "$file" >/dev/null 2>&1 \
  || finding "every skillOverrides value must be \"on\": ${file}"
git -C "$root" check-ignore -q "$file" && finding "git ignores ${file}; un-ignore it in .gitignore"

exit "$fail"
