#!/usr/bin/env bash
# Runs every fixture suite, one at a time: fixtures/*/run.sh under this directory and under each
# skills/*/hooks/. Prints one line per suite and exits non-zero when any suite failed.
set -u

hooks_dir=$(CDPATH='' cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)
agents_dir=$(dirname "$hooks_dir")

suites=()
while IFS= read -r s; do suites+=("$s"); done < <(
  find "$hooks_dir/fixtures" "$agents_dir"/skills/*/hooks/fixtures -mindepth 2 -maxdepth 2 -name run.sh 2>/dev/null | sort
)

failed=0
for suite in "${suites[@]}"; do
  name="${suite#"$agents_dir"/}"
  if out=$(bash "$suite" 2>&1); then
    printf 'PASS %s\n' "$name"
  else
    failed=$((failed + 1))
    printf 'FAIL %s\n%s\n' "$name" "$(printf '%s\n' "$out" | grep -E '^(FAIL|SKIP)' || printf '%s' "$out" | tail -5)"
  fi
done

printf '%d suites, %d failed\n' "${#suites[@]}" "$failed"
[ "$failed" -eq 0 ]
