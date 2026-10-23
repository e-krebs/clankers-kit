#!/usr/bin/env bash
# Runs the requires-cycle rule of lint-manifest.sh on temp manifests: a mutual pair passes, while a
# self-edge, a 3-cycle and a mixed cycle (a<->b with b->c->a) fail. Exit 1 on any miss.
set -euo pipefail

lint="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/lint-manifest.sh"
dir="$(mktemp -d)"
trap 'rm -rf "$dir"' EXIT
failures=0

t() {                                  # $1 = id, $2 = requires list (JSON, without brackets)
  printf '{"id":"%s","group":"other","kind":"toggle","requires":[%s]}' "$1" "$2"
}

_case() {                              # $1 = label, $2 = pass|fail, $3 = components JSON array
  local rc=0 got=pass
  printf '{"groups":[{"id":"other","label":"Other"}],"components":%s}\n' "$3" > "$dir/kit.json"
  KIT_ROOT="$dir" KIT_MANIFEST="$dir/kit.json" bash "$lint" >/dev/null 2>&1 || rc=$?
  [ "$rc" -eq 0 ] || got=fail
  if [ "$got" = "$2" ]; then
    printf 'ok    %s\n' "$1"
  else
    printf 'FAIL  %s (lint %s)\n' "$1" "$got"
    failures=$((failures + 1))
  fi
}

_case "mutual pair passes" pass "[$(t a '"b"'),$(t b '"a"')]"
_case "self-edge fails" fail "[$(t a '"a"')]"
_case "3-cycle fails" fail "[$(t a '"b"'),$(t b '"c"'),$(t c '"a"')]"
_case "mixed cycle fails" fail "[$(t a '"b"'),$(t b '"a","c"'),$(t c '"a"')]"

if [ "$failures" -eq 0 ]; then
  printf 'all lint-manifest cases passed\n'
  exit 0
fi
printf '%s lint-manifest case(s) failed\n' "$failures"
exit 1
