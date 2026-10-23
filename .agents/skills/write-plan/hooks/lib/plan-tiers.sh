#!/usr/bin/env bash
# shellcheck disable=SC2154
# Sourced by plan-check.sh and plan-followthrough-codex.sh: the one reader of tiers.md. Tier names
# come from the Tier column and the protocol roles from the Kind column (worker, the tier that
# runs the plan), so no hook names a tier. Needs $models_dir set by the caller.
# The Kind words the hooks read live here and nowhere else.
RUN_KIND=run
WORKER_KIND=worker

# _column <file> <column-name> — prints "<first cell>\t<named cell>" for each data row of every
# table in the file that has that column
_column() {
  awk -F'|' -v want="$2" '
    /^\|/ {
      split("", cell)
      for (i = 2; i < NF; i++) { c = $i; gsub(/^ +| +$/, "", c); cell[i] = c }
      if (!col) { for (i = 2; i < NF; i++) if (cell[i] == want) col = i; next }
      if (cell[col] !~ /^-+$/ && cell[col] != "") print cell[2] "\t" cell[col]
      next
    }
    { col = 0 }' "$1" 2>/dev/null
}

# _tier_of_kind <kind>: the Tier whose Kind cell is <kind> in tiers.md (first match), lowercased;
# nothing when tiers.md is missing or has no Kind column
_tier_of_kind() {
  [ -f "$models_dir/tiers.md" ] || return 0
  _column "$models_dir/tiers.md" Kind | awk -F'\t' -v k="$1" 'tolower($2) == k { print tolower($1); exit }'
}

# _delegable_tiers: the tiers a Steps row may name, one per line, lowercased: every worker tier and
# the running session's tier
_delegable_tiers() {
  [ -f "$models_dir/tiers.md" ] || return 0
  _column "$models_dir/tiers.md" Kind | awk -F'\t' -v w="$WORKER_KIND" -v r="$RUN_KIND" \
    'tolower($2) == w || tolower($2) == r { print tolower($1) }'
}
