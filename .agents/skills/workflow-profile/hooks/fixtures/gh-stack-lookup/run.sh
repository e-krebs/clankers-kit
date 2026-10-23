#!/usr/bin/env bash
# Runs every gh-stack-lookup fixture case and asserts on its output; exits non-zero on any
# failure. Locates the script relative to this file's own path so it still works once these
# fixtures are copied into the real repo.

set -u

fixtures_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
script="$fixtures_dir/../../../scripts/gh-stack-lookup.sh"

overall=0

pass() { printf 'PASS %s\n' "$1"; }
fail_case() { printf 'FAIL %s: %s\n' "$1" "$2"; overall=1; }

root=$(mktemp -d "${TMPDIR:-/tmp}/ghsl.XXXXXX")
trap 'rm -rf "$root" 2>/dev/null' EXIT

new_tmp() {
  mktemp -d "$root/t.XXXXXX"
}

BASE_JSON='{
  "schemaVersion": 1,
  "repository": "acme/widgets",
  "stacks": [
    {
      "id": "1",
      "number": 30118,
      "trunk": { "branch": "develop", "head": "deadbeef" },
      "branches": [
        { "branch": "credentials/base", "head": "a1", "base": "deadbeef",
          "pullRequest": { "number": 30096, "id": "PR1",
            "url": "https://github.com/acme/widgets/pull/30096", "merged": true } },
        { "branch": "credentials/read", "head": "a2", "base": "a1",
          "pullRequest": { "number": 30116, "id": "PR2",
            "url": "https://github.com/acme/widgets/pull/30116", "merged": true } },
        { "branch": "credentials/list", "head": "a3", "base": "a2",
          "pullRequest": { "number": 30129, "id": "PR3",
            "url": "https://github.com/acme/widgets/pull/30129", "merged": null } },
        { "branch": "credentials/delete", "head": "a4", "base": "a3",
          "pullRequest": { "number": 30132, "id": "PR4",
            "url": "https://github.com/acme/widgets/pull/30132", "merged": null } }
      ]
    },
    {
      "id": "2",
      "number": null,
      "trunk": { "branch": "main", "head": "cafebabe" },
      "branches": [
        { "branch": "feat/solo", "head": "b1", "base": "cafebabe",
          "pullRequest": { "number": 30140, "id": "PR5",
            "url": "https://github.com/acme/widgets/pull/30140", "merged": null } }
      ]
    }
  ]
}'

THIRD_STACK_JSON='{
  "schemaVersion": 1,
  "repository": "acme/widgets",
  "stacks": [
    {
      "id": "1",
      "number": 30118,
      "trunk": { "branch": "develop", "head": "deadbeef" },
      "branches": [
        { "branch": "credentials/base", "head": "a1", "base": "deadbeef",
          "pullRequest": { "number": 30096, "id": "PR1",
            "url": "https://github.com/acme/widgets/pull/30096", "merged": true } },
        { "branch": "credentials/read", "head": "a2", "base": "a1",
          "pullRequest": { "number": 30116, "id": "PR2",
            "url": "https://github.com/acme/widgets/pull/30116", "merged": true } },
        { "branch": "credentials/list", "head": "a3", "base": "a2",
          "pullRequest": { "number": 30129, "id": "PR3",
            "url": "https://github.com/acme/widgets/pull/30129", "merged": null } },
        { "branch": "credentials/delete", "head": "a4", "base": "a3",
          "pullRequest": { "number": 30132, "id": "PR4",
            "url": "https://github.com/acme/widgets/pull/30132", "merged": null } }
      ]
    },
    {
      "id": "2",
      "number": null,
      "trunk": { "branch": "main", "head": "cafebabe" },
      "branches": [
        { "branch": "feat/solo", "head": "b1", "base": "cafebabe",
          "pullRequest": { "number": 30140, "id": "PR5",
            "url": "https://github.com/acme/widgets/pull/30140", "merged": null } }
      ]
    },
    {
      "id": "3",
      "number": 30200,
      "trunk": { "branch": "develop", "head": "d1" },
      "branches": [
        { "branch": "credentials/list", "head": "c1", "base": "d1",
          "pullRequest": { "number": 30201, "id": "PR6",
            "url": "https://github.com/acme/widgets/pull/30201", "merged": null } }
      ]
    }
  ]
}'

EXPECTED_LINE='stack 30118 (trunk develop): credentials/base#30096 (merged) -> credentials/read#30116 (merged) -> credentials/list#30129 -> credentials/delete#30132'
EXPECTED_SOLO_LINE='stack untracked (trunk main): feat/solo#30140'
EXPECTED_THIRD_LINE='stack 30200 (trunk develop): credentials/list#30201'

assert_eq_case() {  # name got want
  if [ "$2" = "$3" ]; then
    pass "$1"
  else
    fail_case "$1" "expected [$3], got [$2]"
  fi
}

# --- set up a repo with a linked worktree and the base fixture -------------------
repo_root=$(new_tmp)
repo="$repo_root/repo"
mkdir -p "$repo"
(
  cd "$repo" || exit 1
  git init -q
  git config user.email t@t.com
  git config user.name t
  printf 'x\n' > README.md
  git add README.md
  git commit -q -m init
) >/dev/null 2>&1

worktree_parent=$(new_tmp)
worktree="$worktree_parent/wt"
(cd "$repo" && git worktree add -q -b credentials/list "$worktree") >/dev/null 2>&1

printf '%s' "$BASE_JSON" > "$repo/.git/gh-stack"

# 1. --pr 30132 -> stack 30118 line, exit 0
out=$(bash "$script" --pr 30132 "$repo")
rc=$?
if [ "$rc" -eq 0 ]; then
  assert_eq_case "pr-30132" "$out" "$EXPECTED_LINE"
else
  fail_case "pr-30132" "exit $rc, out: $out"
fi

# 2. --branch credentials/read -> same line
out=$(bash "$script" --branch credentials/read "$repo")
rc=$?
if [ "$rc" -eq 0 ]; then
  assert_eq_case "branch-credentials-read" "$out" "$EXPECTED_LINE"
else
  fail_case "branch-credentials-read" "exit $rc, out: $out"
fi

# 3. --branch feat/solo -> untracked stack line
out=$(bash "$script" --branch feat/solo "$repo")
rc=$?
if [ "$rc" -eq 0 ]; then
  assert_eq_case "branch-feat-solo" "$out" "$EXPECTED_SOLO_LINE"
else
  fail_case "branch-feat-solo" "exit $rc, out: $out"
fi

# 4. --pr 1 -> no match, exit 3, no stdout
out=$(bash "$script" --pr 1 "$repo")
rc=$?
if [ "$rc" -eq 3 ] && [ -z "$out" ]; then
  pass "pr-no-match"
else
  fail_case "pr-no-match" "exit $rc, out: $out"
fi

# 5. from the linked worktree -> common dir shared, same line
out=$(bash "$script" --pr 30132 "$worktree")
rc=$?
if [ "$rc" -eq 0 ]; then
  assert_eq_case "from-worktree" "$out" "$EXPECTED_LINE"
else
  fail_case "from-worktree" "exit $rc, out: $out"
fi

# 6a. not a git repo -> exit 4
plain=$(new_tmp)
out=$(bash "$script" --pr 30132 "$plain")
rc=$?
if [ "$rc" -eq 4 ] && [ -z "$out" ]; then
  pass "not-a-git-repo"
else
  fail_case "not-a-git-repo" "exit $rc, out: $out"
fi

# 6b. git repo without the file -> exit 4
norepo_root=$(new_tmp)
norepo="$norepo_root/repo"
mkdir -p "$norepo"
(cd "$norepo" && git init -q) >/dev/null 2>&1
out=$(bash "$script" --pr 30132 "$norepo")
rc=$?
if [ "$rc" -eq 4 ] && [ -z "$out" ]; then
  pass "git-repo-no-file"
else
  fail_case "git-repo-no-file" "exit $rc, out: $out"
fi

# 8. arg validation errors -> exit 2, no stdout
out=$(bash "$script" --branch "" "$repo")
rc=$?
if [ "$rc" -eq 2 ] && [ -z "$out" ]; then
  pass "empty-branch"
else
  fail_case "empty-branch" "exit $rc, out: $out"
fi

out=$(bash "$script" "$repo")
rc=$?
if [ "$rc" -eq 2 ] && [ -z "$out" ]; then
  pass "no-flag"
else
  fail_case "no-flag" "exit $rc, out: $out"
fi

out=$(bash "$script" --pr abc "$repo")
rc=$?
if [ "$rc" -eq 2 ] && [ -z "$out" ]; then
  pass "pr-not-digits"
else
  fail_case "pr-not-digits" "exit $rc, out: $out"
fi

# 9. a branch listed in two stacks -> two lines, exit 0
printf '%s' "$THIRD_STACK_JSON" > "$repo/.git/gh-stack"
out=$(bash "$script" --branch credentials/list "$repo")
rc=$?
want=$(printf '%s\n%s' "$EXPECTED_LINE" "$EXPECTED_THIRD_LINE")
if [ "$rc" -eq 0 ]; then
  assert_eq_case "branch-in-two-stacks" "$out" "$want"
else
  fail_case "branch-in-two-stacks" "exit $rc, out: $out"
fi

# 7a. valid JSON with the wrong shape -> exit 5, never 3 (a future schema must read unknown)
printf '{"schemaVersion":2,"stackList":[]}' > "$repo/.git/gh-stack"
out=$(bash "$script" --pr 30132 "$repo")
rc=$?
if [ "$rc" -eq 5 ] && [ -z "$out" ]; then
  pass "wrong-shape-json"
else
  fail_case "wrong-shape-json" "exit $rc, out: $out"
fi

# 7b. a null-branches stack after the match -> exit 5, not a partial present
printf '{"stacks":[{"number":1,"trunk":{"branch":"develop"},"branches":[{"branch":"credentials/read","pullRequest":{"number":30116}}]},{"number":2,"trunk":{"branch":"develop"},"branches":null}]}' > "$repo/.git/gh-stack"
out=$(bash "$script" --pr 30116 "$repo")
rc=$?
if [ "$rc" -eq 5 ]; then
  pass "null-branches-after-match"
else
  fail_case "null-branches-after-match" "exit $rc, out: $out"
fi

# 7. malformed JSON -> exit 5 (done last: this corrupts the fixture file)
printf '{not json' > "$repo/.git/gh-stack"
out=$(bash "$script" --pr 30132 "$repo")
rc=$?
if [ "$rc" -eq 5 ] && [ -z "$out" ]; then
  pass "malformed-json"
else
  fail_case "malformed-json" "exit $rc, out: $out"
fi

exit $overall
