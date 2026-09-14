#!/usr/bin/env bash
# SessionEnd + SessionStart housekeeping: reaps the per-session tmp markers other hooks leave
# behind (forbid-narration.sh, style-report.sh's attempt counter, plan-gate.sh's denial counter,
# plan-nudge.sh's once-per-session marker). SessionEnd does not fire on a kill or
# a crash, so orphaned markers accumulate; the SessionStart sweep is the backstop, keyed on file
# AGE rather than session id, since a crashed session's id is never seen again. Wired: SessionEnd,
# SessionStart.
#
# Each family's filename mirrors the writer hook's own sanitization exactly, or the match below
# would miss it (or worse, touch a differently-shaped file another hook owns). Never a blanket
# 'claude-*' sweep — four named families only.
# Also wired from ~/.codex/hooks.json on SessionStart and SessionEnd; under Codex only the plan-nudge marker family arises.
# codex: yes

input=$(jq -c 'select(type=="object")' 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0

agent_id=$(printf '%s' "$input" | jq -r '.agent_id // empty' 2>/dev/null)
[ -z "$agent_id" ] || exit 0

event=$(printf '%s' "$input" | jq -r '.hook_event_name // empty' 2>/dev/null)
session=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)

tmpdir="${TMPDIR:-/tmp}"

# sweep_family <dir> <name-glob> — deletes files older than a day matching the glob, read-only
# find (-print, never -delete) piped into a while/rm loop so a pasted body never trips the
# find -delete ban.
sweep_family() {
  local dir="$1" pattern="$2" f
  while IFS= read -r f; do
    [ -n "$f" ] && rm -f "$f" 2>/dev/null
  done < <(find "$dir" -maxdepth 1 -name "$pattern" -mmin +1440 -type f -print 2>/dev/null)
}

case "$event" in
  SessionEnd)
    [ -n "$session" ] || exit 0

    # forbid-narration.sh's denial counter: sanitized, untruncated.
    sid_san="${session//[^A-Za-z0-9_-]/}"
    [ -n "$sid_san" ] && rm -f "$tmpdir/claude-narration-$sid_san" 2>/dev/null

    # style-report.sh's per-turn attempt counter: sanitized AND truncated to 64 chars, matching
    # the hook's own `session=${session:0:64}`.
    sid_style="${sid_san:0:64}"
    [ -n "$sid_style" ] && rm -f "$tmpdir/claude-style-$sid_style" 2>/dev/null

    # plan-gate.sh's denial counter, and plan-nudge.sh's once-per-session marker: both sanitized,
    # untruncated, same as forbid-narration.sh's.
    [ -n "$sid_san" ] && rm -f "$tmpdir/claude-plan-gate-$sid_san" 2>/dev/null
    [ -n "$sid_san" ] && rm -f "$tmpdir/claude-plan-nudge-$sid_san" 2>/dev/null
    ;;

  SessionStart)
    sweep_family "$tmpdir" "claude-narration-*"
    sweep_family "$tmpdir" "claude-style-*"
    sweep_family "$tmpdir" "claude-plan-gate-*"
    sweep_family "$tmpdir" "claude-plan-nudge-*"
    ;;
esac

exit 0
