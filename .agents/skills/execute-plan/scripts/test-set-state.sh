#!/usr/bin/env bash
# Exits 0 only when every set-state.sh case passes; plans are built in a mktemp -d.
# shellcheck disable=SC2016  # the backticks in the expected table rows are literal
set -euo pipefail

sut="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/set-state.sh"
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT
plan="$dir/plan.md"
failures=0

_ok() { printf 'ok    %s\n' "$1"; }
_fail() { printf 'FAIL  %s\n' "$1"; failures=$((failures + 1)); }
_run() {
  rc=0
  err=$(bash "$sut" "$@" 2>&1 >/dev/null) || rc=$?
}
_lines() { printf '%s' "$1" | grep -c '' || true; }
_changed() { diff "$1" "$2" | grep -c '^[<>]' || true; }
_only_row_changed() { [ "$(_changed "$1" "$2")" -eq 2 ] && grep -qxF -- "$3" "$2"; }

_standard() {
  cat > "$plan" <<'EOF'
# Test plan

## Summary

Fixture for set-state.

## Decisions

None.

## Steps

| State | # | Task | Tier | After | Done when | Files |
|---|---|---|---|---|---|---|
| ➖ | S1 | First | x | — | `true` | `a.txt` |
| ➖ | S2 | Second | x | S1 | `true` | `b.txt` |

## Run

Fixture only.

## Briefs

### S2

Brief body.
EOF
  cp "$plan" "$dir/orig.md"
}

_expect_error() {
  local label=$1
  shift
  _run "$@"
  if [ "$rc" -eq 1 ] && [ "$(_lines "$err")" -eq 1 ] && cmp -s "$dir/orig.md" "$plan"; then
    _ok "$label"
  else
    _fail "$label (exit $rc, stderr lines $(_lines "$err"))"
  fi
}

_standard
_run "$plan" S2 '▶️'
if [ "$rc" -eq 0 ] && _only_row_changed "$dir/orig.md" "$plan" '| ▶️ | S2 | Second | x | S1 | `true` | `b.txt` |'; then
  _ok "S2 to ▶️ changes one State cell"
else
  _fail "S2 to ▶️ changes one State cell (exit $rc: $err)"
fi
_run "$plan" S2 '✅'
if [ "$rc" -eq 0 ] && _only_row_changed "$dir/orig.md" "$plan" '| ✅ | S2 | Second | x | S1 | `true` | `b.txt` |'; then
  _ok "S2 to ✅ changes one State cell"
else
  _fail "S2 to ✅ changes one State cell (exit $rc: $err)"
fi

cat > "$plan" <<'EOF'
## Steps

| State | # | Task | Tier | After | Done when | Files |
|---|---|---|---|---|---|---|
| ➖ | S1 | First | x | — | `true` | `a.txt` |

```text
| ➖ | S2 | Second | x | S1 | `true` | `b.txt` |
```

## Briefs

### S2

Brief body.
EOF
cp "$plan" "$dir/orig.md"
_expect_error "S2 only inside a fence and a heading exits 1" "$plan" S2 '✅'

_standard
_expect_error "unknown row exits 1" "$plan" S9 '✅'
_expect_error "invalid glyph exits 1" "$plan" S2 'X'

cat > "$plan" <<'EOF'
## Steps

Prose only, no table.

## Briefs

### S2
EOF
cp "$plan" "$dir/orig.md"
_expect_error "plan without a Steps table exits 1" "$plan" S2 '✅'

_expect_error "missing file exits 1" "$dir/absent.md" S2 '✅'
if [ -e "$dir/absent.md" ]; then _fail "missing file was created"; fi

cat > "$plan" <<'EOF'
## Steps

| State | # | Task | Tier | After | Done when | Files |
|---|---|---|---|---|---|---|
| ➖ | S1 | Pipe `a | b` | x | — | `true` | `a.txt` |
| ➖ | S2 | Second | x | S1 | `true` | `b.txt` |
EOF
cp "$plan" "$dir/orig.md"
_run "$plan" S1 '✅'
if [ "$rc" -eq 0 ] && _only_row_changed "$dir/orig.md" "$plan" '| ✅ | S1 | Pipe `a | b` | x | — | `true` | `a.txt` |'; then
  _ok "pipe inside a backticked Task cell changes only the State cell"
else
  _fail "pipe inside a backticked Task cell changes only the State cell (exit $rc: $err)"
fi

_standard
chmod 644 "$plan"
_run "$plan" S2 '▶️'
if [ "$rc" -eq 0 ] && [ "$(stat -c %a "$plan" 2>/dev/null || stat -f %Lp "$plan")" = 644 ]; then
  _ok "644 plan stays 644 after a State write"
else
  _fail "644 plan stays 644 after a State write (exit $rc: $err)"
fi

if [ "$failures" -eq 0 ]; then
  printf 'all set-state cases passed\n'
  exit 0
fi
printf '%s set-state case(s) failed\n' "$failures"
exit 1
