#!/usr/bin/env bash
# Runs every session-cleanup fixture case and asserts on its output; exits non-zero on any
# failure. Locates the hook relative to this file's own path, so it keeps working once these
# fixtures are copied into the real repo.
#
# Unlike the other runners, the assertions here are on FILESYSTEM state, not stdout, so each
# case builds its own sandbox TMPDIR rather than relying on the fixture JSON alone. The fixture
# markers use PID-suffixed session ids so a concurrent run of this file never collides with
# another one's files. The trap removes the sandboxes regardless of pass or fail.

set -u

fixtures_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
hook="$fixtures_dir/../../session-cleanup.sh"

overall=0
pass() { printf 'PASS %s\n' "$1"; }
fail_case() { printf 'FAIL %s: %s\n' "$1" "$2"; overall=1; }

sid_a="fixture-sid-a"
sid_b="fixture-sid-b-$$"

# shellcheck disable=SC2329,SC2317  # invoked by the trap below
cleanup() {
  rm -rf "$end_work" "$sweep_work" "$agent_work" 2>/dev/null
}
trap cleanup EXIT

# --- syntax check -------------------------------------------------------------
if bash -n "$hook" 2>/tmp/sc-syn.$$; then
  pass "syntax:hook"
else
  fail_case "syntax:hook" "bash -n failed: $(head -3 /tmp/sc-syn.$$ 2>/dev/null)"
fi
rm -f /tmp/sc-syn.$$ 2>/dev/null

make_four() {  # $1=sid $2=tmpdir — pre-creates the four files a session-cleanup family owns
  local sid="$1" td="$2"
  : > "$td/claude-narration-$sid"
  : > "$td/claude-style-$sid"
  : > "$td/claude-plan-gate-$sid"
  : > "$td/claude-plan-nudge-$sid"
}

four_files() {  # $1=sid $2=tmpdir — prints the four paths, one per line
  local sid="$1" td="$2"
  printf '%s\n' \
    "$td/claude-narration-$sid" \
    "$td/claude-style-$sid" \
    "$td/claude-plan-gate-$sid" \
    "$td/claude-plan-nudge-$sid"
}

all_gone() {  # $1=sid $2=tmpdir
  local f
  while IFS= read -r f; do
    [ -e "$f" ] && return 1
  done < <(four_files "$1" "$2")
  return 0
}

all_present() {  # $1=sid $2=tmpdir
  local f
  while IFS= read -r f; do
    [ -e "$f" ] || return 1
  done < <(four_files "$1" "$2")
  return 0
}

# --- SessionEnd: removes exactly the four files for its sid, leaves another sid's alone -------
end_work=$(mktemp -d "${TMPDIR:-/tmp}/claude-sc-fixture-XXXXXX")
make_four "$sid_a" "$end_work"
make_four "$sid_b" "$end_work"

TMPDIR="$end_work" bash "$hook" < "$fixtures_dir/session-end.json" >/dev/null 2>&1

if all_gone "$sid_a" "$end_work"; then
  pass "session-end-removes-its-four"
else
  fail_case "session-end-removes-its-four" "a file for $sid_a survived"
fi

if all_present "$sid_b" "$end_work"; then
  pass "session-end-leaves-other-sid"
else
  fail_case "session-end-leaves-other-sid" "a file for $sid_b was removed"
fi

# --- SessionStart: sweeps a 2-day-old file, keeps a fresh one ----------------------------------
sweep_work=$(mktemp -d "${TMPDIR:-/tmp}/claude-sc-sweep-XXXXXX")
old="$sweep_work/claude-narration-old"
fresh="$sweep_work/claude-narration-fresh"
: > "$old"
: > "$fresh"
touch -t "$(date -v-2d +%Y%m%d0000 2>/dev/null || date -d '2 days ago' +%Y%m%d0000)" "$old"

TMPDIR="$sweep_work" bash "$hook" < "$fixtures_dir/session-start.json" >/dev/null 2>&1

if [ ! -e "$old" ] && [ -e "$fresh" ]; then
  pass "session-start-sweeps-old-keeps-fresh"
else
  fail_case "session-start-sweeps-old-keeps-fresh" \
    "old present=$([ -e "$old" ] && printf yes || printf no), fresh present=$([ -e "$fresh" ] && printf yes || printf no)"
fi

# --- malformed: stays silent, exit 0 -----------------------------------------------------------
mal_out=$(bash "$hook" < "$fixtures_dir/malformed.json" 2>/dev/null)
mal_rc=$?
if [ "$mal_rc" -eq 0 ] && [ -z "$mal_out" ]; then
  pass "malformed"
else
  fail_case "malformed" "rc=$mal_rc out=$mal_out"
fi

# --- agent_id: a subagent's SessionEnd never touches the files ---------------------------------
agent_work=$(mktemp -d "${TMPDIR:-/tmp}/claude-sc-agent-XXXXXX")
make_four "$sid_a" "$agent_work"
TMPDIR="$agent_work" bash "$hook" < "$fixtures_dir/session-end-agent-id.json" >/dev/null 2>&1
if all_present "$sid_a" "$agent_work"; then
  pass "agent-id-silence"
else
  fail_case "agent-id-silence" "a file was removed despite agent_id"
fi

exit $overall
