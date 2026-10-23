#!/usr/bin/env bash
# plan_run_fence — reads plan text on stdin and prints the first fence under an unfenced "## Run"
# line (before the next unfenced "## " line) that holds a "claude --agent " or "codex -m " line quoting
# "/execute-plan " (claude) or "Execute the plan at " (codex), the two forms plan-check accepts. A fence closes only on its own marker
# char repeated at least as long, so a quoted fence nests. Lines come out trimmed, since
# plan-check trims them before matching.
plan_run_fence() {
  awk '
    match($0, /^[[:space:]]*(```+|~~~+)/) {
      m = substr($0, RSTART, RLENGTH); gsub(/[[:space:]]/, "", m)
      if (open == "") {
        open = m
        if (state == 1) { state = 2; buf = ""; found = 0 }
        next
      }
      rest = substr($0, RSTART + RLENGTH)
      if (substr(m, 1, 1) == substr(open, 1, 1) && length(m) >= length(open) && rest ~ /^[[:space:]]*$/) {
        open = ""
        if (state == 2) {
          if (found) { printf "%s", buf; exit }
          state = 1
        }
        next
      }
    }
    state == 2 {
      line = $0; sub(/^[[:space:]]+/, "", line); sub(/[[:space:]]+$/, "", line)
      if ((line ~ /^claude --agent / && line ~ /"\/execute-plan /) || (line ~ /^codex -m / && line ~ /"Execute the plan at /)) found = 1
      buf = buf line "\n"
      next
    }
    open != "" { next }
    state == 0 && /^## Run[[:space:]]*$/ { state = 1; next }
    state == 1 && /^## / { exit }
  '
}
