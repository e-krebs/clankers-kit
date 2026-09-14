#!/usr/bin/env bash
# Runs every play-sound fixture case in dry-run mode and asserts on the sound kind it picks; exits
# non-zero on any failure. Locates the hook relative to this file's own path.

set -u

fixtures_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
hook="$fixtures_dir/../../play-sound.sh"

overall=0
pass() { printf 'PASS %s\n' "$1"; }
fail_case() { printf 'FAIL %s: %s\n' "$1" "$2"; overall=1; }

if bash -n "$hook" 2>/dev/null; then pass "syntax:hook"; else fail_case "syntax:hook" "bash -n failed"; fi

# expect <case> <fixture> <kind or "">
expect() {
  local case_name="$1" fixture="$2" want="$3" out rc
  out=$(PLAY_SOUND_DRY_RUN=1 bash "$hook" < "$fixtures_dir/$fixture" 2>/dev/null)
  rc=$?
  if [ "$rc" -eq 0 ] && [ "$out" = "$want" ]; then pass "$case_name"
  else fail_case "$case_name" "rc=$rc out='$out' want='$want'"; fi
}

expect "notification-plays-notify"      notification.json       notify
expect "permission-request-plays-notify" permission-request.json notify
expect "stop-plays-stop"                 stop.json               stop
expect "other-event-is-silent"           other-event.json        ""
expect "malformed-is-silent"             malformed.json          ""

exit $overall
