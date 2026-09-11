#!/usr/bin/env bash
# Shared hook-event logger, sourced by the deny/advise/nudge hooks that want a record of when
# they fired. Each call appends one line — "<utc stamp> <session> <hook> <outcome> <rule>" — to
# ${AGENTS_HOOK_LOG:-$HOME/.claude/hook-events.log}; AGENTS_HOOK_LOG lets a fixture runner point
# writes at a sandbox instead of the real log. Concurrent writers serialize on a bounded
# "mkdir $log.lock" lock (three tries, 0.05s apart) removed after the write; a lock older than
# five seconds is stale (a killed hook left it) and is removed and retaken, a younger one means a
# live writer, so the append goes ahead unlocked and only the trim waits for the next locked
# call. No trap: a sourced library must not replace the caller's EXIT trap. Once the log passes 500
# lines and its oldest line is older than 30 days, it is trimmed to the last 30 days inside the
# same lock, with the lines an unlocked writer appended during the rewrite carried over. Every write path fails silently
# (2>/dev/null || true): this library never changes the caller's exit status or prints to
# stdout. The hooks-review skill reads this file to rank rules by how often they fire.

_hook_log_write() {  # $1=hook $2=outcome $3=rule
  local hook="$1" outcome="$2" rule="${3:--}"
  local log="${AGENTS_HOOK_LOG:-$HOME/.claude/hook-events.log}"
  local session="${HOOK_SESSION:-unknown}"
  session=${session//[^A-Za-z0-9_-]/}
  local stamp
  stamp=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null) || return 0

  mkdir -p "$(dirname "$log")" 2>/dev/null || true

  # No trap here: a sourced library must not replace the caller's EXIT trap. A lock older than
  # five seconds is stale (a write takes milliseconds; a killed hook left it) and is removed and
  # retaken; a younger lock that outlives the three tries belongs to a live writer, so the append
  # proceeds unlocked (one line, atomic enough) and the trim below is skipped.
  local lock="${log}.lock" locked=0 tries=0 lock_mtime age
  while [ "$tries" -lt 3 ]; do
    if mkdir "$lock" 2>/dev/null; then
      locked=1
      break
    fi
    tries=$((tries + 1))
    [ "$tries" -lt 3 ] && sleep 0.05 2>/dev/null
  done
  if [ "$locked" -eq 0 ]; then
    lock_mtime=$(stat -f %m "$lock" 2>/dev/null || stat -c %Y "$lock" 2>/dev/null || printf '0')
    age=$(( $(date +%s) - ${lock_mtime:-0} ))
    if [ "$age" -gt 5 ]; then
      rmdir "$lock" 2>/dev/null || true
      mkdir "$lock" 2>/dev/null && locked=1
    fi
  fi

  printf '%s %s %s %s %s\n' "$stamp" "${session:-unknown}" "$hook" "$outcome" "$rule" 2>/dev/null >> "$log" || true

  # Trim only under the lock, only past 500 lines, and only when the oldest line has aged out:
  # a log of recent lines is never rewritten, so the rewrite (and its tiny loss window between
  # the tail merge and the rename) runs at most once per day.
  local count oldest cutoff
  count=$(wc -l 2>/dev/null < "$log")
  count=${count//[^0-9]/}
  cutoff=$(date -u -v-30d +%Y-%m-%d 2>/dev/null || date -u -d "-30 days" +%Y-%m-%d 2>/dev/null)
  oldest=$(head -n 1 "$log" 2>/dev/null); oldest=${oldest:0:10}
  if [ "$locked" -eq 1 ] && [ "${count:-0}" -gt 500 ] && [ -n "$cutoff" ] && [ "${oldest:-9999}" \< "$cutoff" ]; then
    local kept
    kept=$(mktemp "${TMPDIR:-/tmp}/hook-events-trim-XXXXXX" 2>/dev/null)
    if [ -n "$kept" ] \
       && jq -Rr --arg c "$cutoff" 'select(.[0:10] >= $c)' 2>/dev/null < "$log" > "$kept" \
       && [ -s "$kept" ]; then
      # an unlocked writer may have appended while jq ran: carry those tail lines over
      local now_count
      now_count=$(wc -l 2>/dev/null < "$log"); now_count=${now_count//[^0-9]/}
      if [ "${now_count:-0}" -gt "$count" ]; then
        tail -n $((now_count - count)) "$log" 2>/dev/null >> "$kept" || true
      fi
      mv "$kept" "$log" 2>/dev/null || true
    fi
    rm -f "$kept" 2>/dev/null || true
  fi

  [ "$locked" -eq 1 ] && rmdir "$lock" 2>/dev/null
  return 0
}

# hook_log <outcome> [rule] — logs against the current hook's own name: ${0##*/} with a
# trailing .sh stripped. Called from a sourced hook, so $0 is still that hook's script path.
hook_log() {
  local hook="${0##*/}"
  hook="${hook%.sh}"
  _hook_log_write "$hook" "$1" "${2:--}"
  return 0
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  _hook_log_write "${1:-}" "${2:-}" "${3:--}"
fi
