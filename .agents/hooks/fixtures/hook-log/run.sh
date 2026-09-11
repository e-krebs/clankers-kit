#!/usr/bin/env bash
# Runs every hook-log fixture case and asserts on its output; exits non-zero on any failure.
# Locates the lib relative to this file's own path so it still works once these fixtures are
# copied into the real repo. Every case points AGENTS_HOOK_LOG at a private sandbox file so the
# real ~/.claude/hook-events.log is never touched.

set -u

fixtures_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
libfile="$fixtures_dir/../../lib/hook-log.sh"

overall=0
sandbox=$(mktemp -d "${TMPDIR:-/tmp}/hooklog-fixture.XXXXXX")
trap 'rm -rf "$sandbox" 2>/dev/null' EXIT

pass() { printf 'PASS %s\n' "$1"; }
fail_case() { printf 'FAIL %s: %s\n' "$1" "$2"; overall=1; }

if bash -n "$libfile" 2>/tmp/hl-syn.$$; then
  pass "syntax:lib"
else
  fail_case "syntax:lib" "bash -n failed: $(head -3 /tmp/hl-syn.$$ 2>/dev/null)"
fi
rm -f /tmp/hl-syn.$$ 2>/dev/null

# --- line-shape: sourced form, via a stub hook script --------------------------------------
case_name="line-shape"
stub="$sandbox/stub-hook.sh"
cat > "$stub" <<STUB
#!/usr/bin/env bash
source "$libfile"
HOOK_SESSION=sid
hook_log deny r1
STUB
chmod +x "$stub"
log1="$sandbox/line-shape.log"
AGENTS_HOOK_LOG="$log1" bash "$stub" >/dev/null 2>&1
line=$(cat "$log1" 2>/dev/null)
err=""
if printf '%s' "$line" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z sid stub-hook deny r1$'; then
  :
else
  err="unexpected line: $line"
fi
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- env-override: two calls, two AGENTS_HOOK_LOG destinations, no cross-contamination -----
case_name="env-override"
logA="$sandbox/envA.log"
logB="$sandbox/envB.log"
AGENTS_HOOK_LOG="$logA" bash "$libfile" hookA nudge >/dev/null 2>&1
AGENTS_HOOK_LOG="$logB" bash "$libfile" hookB deny >/dev/null 2>&1
lineA=$(cat "$logA" 2>/dev/null)
lineB=$(cat "$logB" 2>/dev/null)
err=""
case "$lineA" in *" hookA nudge -") ;; *) err="logA line: $lineA" ;; esac
if [ -z "$err" ]; then
  case "$lineB" in *" hookB deny -") ;; *) err="logB line: $lineB" ;; esac
fi
[ "$(wc -l < "$logA" 2>/dev/null)" -eq 1 ] || err="${err:+$err; }logA line count != 1"
[ "$(wc -l < "$logB" 2>/dev/null)" -eq 1 ] || err="${err:+$err; }logB line count != 1"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- script-form: bash hook-log.sh <hook> <outcome> -----------------------------------------
case_name="script-form"
log3="$sandbox/script-form.log"
AGENTS_HOOK_LOG="$log3" bash "$libfile" my-hook nudge >/dev/null 2>&1
line3=$(cat "$log3" 2>/dev/null)
err=""
case "$line3" in *" unknown my-hook nudge -") ;; *) err="unexpected line: $line3" ;; esac
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- default-rule-dash: sourced form, hook_log called with no rule --------------------------
case_name="default-rule-dash"
stub2="$sandbox/stub-hook2.sh"
cat > "$stub2" <<STUB2
#!/usr/bin/env bash
source "$libfile"
HOOK_SESSION=sid2
hook_log advise
STUB2
chmod +x "$stub2"
log4="$sandbox/default-rule.log"
AGENTS_HOOK_LOG="$log4" bash "$stub2" >/dev/null 2>&1
line4=$(cat "$log4" 2>/dev/null)
err=""
case "$line4" in *" sid2 stub-hook2 advise -") ;; *) err="unexpected line: $line4" ;; esac
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- trim-keeps-recent: 501 lines 40 days old + 3 today, one more append triggers the trim --
case_name="trim-keeps-recent"
old_date=$(date -u -v-40d +%Y-%m-%d 2>/dev/null || date -u -d "-40 days" +%Y-%m-%d 2>/dev/null)
today=$(date -u +%Y-%m-%d)
log5="$sandbox/trim.log"
: > "$log5"
i=0
while [ "$i" -lt 501 ]; do
  printf '%sT00:00:00Z sid old-hook advise -\n' "$old_date" >> "$log5"
  i=$((i + 1))
done
j=0
while [ "$j" -lt 3 ]; do
  printf '%sT12:0%d:00Z sid recent-hook advise -\n' "$today" "$j" >> "$log5"
  j=$((j + 1))
done
AGENTS_HOOK_LOG="$log5" bash "$libfile" today-hook nudge >/dev/null 2>&1
err=""
kept=$(wc -l < "$log5" 2>/dev/null); kept=${kept:-0}
[ "$kept" -eq 4 ] || err="expected 4 lines after trim, got $kept"
if [ -z "$err" ]; then
  stale=$(grep -vc "^${today}" "$log5" 2>/dev/null); stale=${stale:-0}
  [ "$stale" -eq 0 ] || err="a stale (40-day-old) line survived the trim"
fi
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- unwritable-dir-silent: AGENTS_HOOK_LOG's parent dir is a regular file -------------------
case_name="unwritable-dir-silent"
blocker="$sandbox/blocker-file"
: > "$blocker"
log6="$blocker/sub/hook-events.log"
out6=$(AGENTS_HOOK_LOG="$log6" bash "$libfile" x nudge 2>/dev/null)
rc6=$?
err=""
[ "$rc6" -eq 0 ] || err="exit $rc6"
[ -z "$out6" ] || err="${err:+$err; }expected no stdout, got: $out6"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- stale-lock-does-not-block: a pre-existing lock dir never blocks the write --------------
case_name="stale-lock-does-not-block"
log7="$sandbox/stale-lock.log"
mkdir -p "$log7.lock"
AGENTS_HOOK_LOG="$log7" HOOK_SESSION=sid7 bash "$libfile" hook7 nudge rule7 >/dev/null 2>&1
line7=$(cat "$log7" 2>/dev/null)
err=""
case "$line7" in *" sid7 hook7 nudge rule7") ;; *) err="expected the line to land, got: $line7" ;; esac
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- old-lock-is-removed: a lock older than five seconds is stale and gets retaken -----------
case_name="old-lock-is-removed"
log7b="$sandbox/old-lock.log"
mkdir -p "$log7b.lock"
touch -t 202001010000 "$log7b.lock"
AGENTS_HOOK_LOG="$log7b" HOOK_SESSION=sid7b bash "$libfile" hook7b deny r7b >/dev/null 2>&1
line7b=$(cat "$log7b" 2>/dev/null)
err=""
case "$line7b" in *" sid7b hook7b deny r7b") ;; *) err="expected the line to land, got: $line7b" ;; esac
[ -d "$log7b.lock" ] && err="${err:+$err; }the stale lock dir survived"
if [ -z "$err" ]; then pass "$case_name"; else fail_case "$case_name" "$err"; fi

# --- concurrent-appends-with-trim: 501 aged lines force a trim while 20 writers append; every
#     writer line survives the trim ------------------------------------------------------------
case_name="concurrent-appends-with-trim"
log9="$sandbox/trim-race.log"
seed=0
: > "$log9"
while [ "$seed" -lt 501 ]; do
  printf '2020-01-01T00:00:00Z seed seed-hook nudge -\n' >> "$log9"
  seed=$((seed + 1))
done
k=0
while [ "$k" -lt 20 ]; do
  AGENTS_HOOK_LOG="$log9" bash "$libfile" racer nudge "r$k" >/dev/null 2>&1 &
  k=$((k + 1))
done
wait
racers=$(grep -c " racer nudge r" "$log9" 2>/dev/null)
if [ "$racers" = "20" ]; then pass "$case_name"; else fail_case "$case_name" "expected 20 racer lines, got $racers"; fi

# --- concurrent-appends: 20 background script-form invocations, all 20 lines land ----------
case_name="concurrent-appends"
log8="$sandbox/concurrent.log"
: > "$log8"
k=0
while [ "$k" -lt 20 ]; do
  AGENTS_HOOK_LOG="$log8" bash "$libfile" c nudge >/dev/null 2>&1 &
  k=$((k + 1))
done
wait
count8=$(wc -l < "$log8" 2>/dev/null); count8=${count8:-0}
if [ "$count8" -eq 20 ]; then pass "$case_name"; else fail_case "$case_name" "expected 20 lines, got $count8"; fi

exit $overall
