#!/usr/bin/env bash
# Compact PR state for pr-followup, so raw statusCheckRollup and review bodies never reach the context.
# Usage: pr-state.sh [<pr>] [--stack]   summary JSON (--stack adds baseRefName, isCrossRepository)
#        pr-state.sh --checks <pr>      check counts by state, e.g. {"SUCCESS":13,"PENDING":2}
#        pr-state.sh --failing <pr>     one {name,state,url} per check that is not passing
# Exits non-zero, gh's error on stderr, when no PR resolves.
set -uo pipefail

state='if (.conclusion // "") != "" then .conclusion else (.state // .status) end'
counts=".statusCheckRollup | map($state) | group_by(.) | map({(.[0]): length}) | add // {}"

case "${1:-}" in
  --checks)
    exec gh pr view "$2" --json statusCheckRollup --jq "$counts" ;;
  --failing)
    exec gh pr view "$2" --json statusCheckRollup --jq "[.statusCheckRollup[] | {name: (.name // .context), state: ($state), url: (.detailsUrl // .targetUrl)} | select(.state as \$s | [\"SUCCESS\",\"SKIPPED\",\"NEUTRAL\"] | index(\$s) | not)]" ;;
esac

pr=(); extra=""; stack=""
for a in "$@"; do
  case "$a" in
    --stack) extra=",baseRefName,isCrossRepository"; stack=", baseRefName, isCrossRepository" ;;
    *) pr=("$a") ;;
  esac
done

exec gh pr view ${pr[@]+"${pr[@]}"} \
  --json "number,state,isDraft,url,title,body,author,latestReviews,reviewRequests,headRefName,statusCheckRollup$extra" \
  --jq "{number, state, isDraft, url, title, body, author: .author.login, headRefName$stack,
    reviewers: ([.latestReviews[].author.login] | unique),
    requested: [.reviewRequests[] | (.login // .slug)],
    checks: ($counts)}"
