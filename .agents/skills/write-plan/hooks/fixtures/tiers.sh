#!/usr/bin/env bash
# Sourced by the run.sh files once AGENTS_WORKFLOW_MODELS is exported. The only file that reads the
# tier tables, so a tier rename or edit never touches a fixture. A fixture plan holds
# __TIER_FIRST__ / __TIER_A__ / __TIER_B__ / __TIER_LAST__ (worker tiers), __RUN_TIER__ / __NONDELEGABLE_TIER__
# (the tier that runs the plan and the first tier that is neither a worker nor the one running it), __MODEL__ / __EFFORT__ (Claude row of the running tier) and __CODEX_MODEL__ /
# __CODEX_EFFORT__ (Codex row of the running tier); `fill_exec` swaps them for the real values on stdin.

# shellcheck source=../lib/plan-tiers.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/plan-tiers.sh"

# tiers.md "Tier<TAB>Kind" per row, as plan-check.sh reads it: slots come from Kind, never from position
_tier_kinds() {
  awk -F'|' '/^\|/ {
    for (i = 2; i < NF; i++) { c = $i; gsub(/^ +| +$/, "", c); cell[i] = c }
    if (!h) { for (i = 2; i < NF; i++) if (cell[i] == "Kind") h = i; next }
    if (cell[2] !~ /^-+$/) print cell[2] "\t" cell[h]
  }' "$AGENTS_WORKFLOW_MODELS/tiers.md"
}

WORKERS=()
RUN_TIER="" NONDELEGABLE_TIER=""
while IFS=$'\t' read -r _t _k; do
  case "$_k" in
    "$WORKER_KIND") WORKERS+=("$_t") ;;
    "$RUN_KIND") RUN_TIER=$_t ;;
    *) [ -n "$NONDELEGABLE_TIER" ] || NONDELEGABLE_TIER=$_t ;;
  esac
done < <(_tier_kinds)
if [ "${#WORKERS[@]}" -lt 4 ] || [ -z "$RUN_TIER" ] || [ -z "$NONDELEGABLE_TIER" ]; then
  printf 'tiers.sh: tiers.md in %s needs 4 worker rows plus the tier that runs the plan and a non-delegable tier; found %s workers\n' "$AGENTS_WORKFLOW_MODELS" "${#WORKERS[@]}" >&2
  exit 1
fi
TIER_FIRST=${WORKERS[0]}
TIER_A=${WORKERS[2]}
TIER_B=${WORKERS[3]}
TIER_LAST=${WORKERS[$((${#WORKERS[@]} - 1))]}

_run_tier_cell() {
  awk -F'|' -v col="$2" -v tier="$RUN_TIER" '
    /^\|/ {
      for (i = 2; i < NF; i++) { c = $i; gsub(/^ +| +$/, "", c); cell[i] = c }
      if (!h) { for (i = 2; i < NF; i++) if (cell[i] == col) h = i; next }
      if (tolower(cell[2]) == tolower(tier)) { print cell[h]; exit }
    }' "$AGENTS_WORKFLOW_MODELS/$1.md"
}

RUN_MODEL=$(_run_tier_cell claude Model)
RUN_EFFORT=$(_run_tier_cell claude Effort)
RUN_CODEX_MODEL=$(_run_tier_cell codex Model)
RUN_CODEX_EFFORT=$(_run_tier_cell codex Effort)
if [ -z "$RUN_MODEL" ] || [ -z "$RUN_EFFORT" ] || [ -z "$RUN_CODEX_MODEL" ] || [ -z "$RUN_CODEX_EFFORT" ]; then
  printf 'tiers.sh: no %s row in %s\n' "$RUN_TIER" "$AGENTS_WORKFLOW_MODELS" >&2
  exit 1
fi

# an effort that differs from the running session's, for the wrong-effort cases
other_effort() { if [ "$1" = high ]; then printf low; else printf high; fi; }
# shellcheck disable=SC2034
RUN_CODEX_OTHER_EFFORT=$(other_effort "$RUN_CODEX_EFFORT")

fill_exec() {
  sed -e "s/__CODEX_MODEL__/$RUN_CODEX_MODEL/g" -e "s/__CODEX_EFFORT__/$RUN_CODEX_EFFORT/g" \
    -e "s/__MODEL__/$RUN_MODEL/g" -e "s/__EFFORT__/$RUN_EFFORT/g" \
    -e "s/__TIER_FIRST__/$TIER_FIRST/g" -e "s/__TIER_A__/$TIER_A/g" -e "s/__TIER_B__/$TIER_B/g" \
    -e "s/__TIER_LAST__/$TIER_LAST/g" -e "s/__RUN_TIER__/$RUN_TIER/g" -e "s/__NONDELEGABLE_TIER__/$NONDELEGABLE_TIER/g"
}
