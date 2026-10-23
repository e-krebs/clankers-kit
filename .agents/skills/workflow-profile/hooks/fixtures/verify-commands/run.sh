#!/usr/bin/env bash
# Asserts resolve-profile.sh --verify-commands output on synthetic profiles.
# shellcheck disable=SC2016  # literal backticks in profile rows

set -u

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
script="$here/../../../scripts/resolve-profile.sh"
overall=0
root=$(mktemp -d "${TMPDIR:-/tmp}/vc.XXXXXX")
trap 'rm -rf "$root" 2>/dev/null' EXIT

# run_case <name> <row value> <expected output, \n and \t escapes>
run_case() {
  local name="$1" row="$2" want="$3" got repo="$root/$1"
  mkdir -p "$repo/profiles/repos" "$repo/work"
  printf '| Field | Value |\n| --- | --- |\n| Verify commands | %s |\n' "$row" >"$repo/profiles/repos/$name.md"
  git -C "$repo/work" init -q
  git -C "$repo/work" remote add origin "https://github.com/acme/$name.git"
  got=$(AGENTS_WORKFLOW_PROFILES="$repo/profiles" bash "$script" --verify-commands "$repo/work")
  want=$(printf '%b' "$want")
  if [ "$got" = "$want" ]; then printf 'PASS %s\n' "$name"; else printf 'FAIL %s\n--- got\n%s\n--- want\n%s\n' "$name" "$got" "$want"; overall=1; fi
}

run_case plain 'yarn lint, yarn test' '\tyarn lint\n\tyarn test'
run_case dir '_client: yarn test, yarn lint --quiet' '_client\tyarn test\n_client\tyarn lint --quiet'
run_case spans '`yarn lint`; `VITE_API_MODE=real yarn build`' '\tyarn lint\n\tVITE_API_MODE=real yarn build'
run_case outer '`yarn lint && yarn test`' '\tyarn lint && yarn test'
run_case dirspans 'web: `yarn lint`, `yarn test`' 'web\tyarn lint\nweb\tyarn test'
run_case pipe 'yarn lint | tee l.log, a || b' '\tyarn lint | tee l.log\n\ta || b'
run_case comma 'x --agents claude,codex, y' '\tx --agents claude,codex\n\ty'
run_case iffi '_client: if ! git diff --quiet; then yarn e; fi, yarn tc' '_client\tif ! git diff --quiet; then yarn e; fi\n_client\tyarn tc'
run_case unset '—' ''

exit $overall
