#!/usr/bin/env bash
# Lint kit.json, the manifest setup.sh reads: ids unique and referenced groups declared, every
# `requires` and `soft` edge resolves, no `requires` cycle, every declared path exists, and every
# skill dir under .agents/skills is declared. Exit 1 with one line per finding.
# Usage: bash .agents/lint-manifest.sh   (from anywhere; the repo root is this script's parent)
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
manifest="${root}/kit.json"
fail=0
finding() { echo "lint-manifest: $*" >&2; fail=1; }

[ -f "$manifest" ] || { finding "kit.json missing at ${root}"; exit 1; }
jq -e '(.groups | type == "array") and (.components | type == "array")' "$manifest" >/dev/null 2>&1 \
  || { finding "kit.json is not an object with .groups and .components arrays"; exit 1; }

# --- structural checks, one jq program, one finding per line -------------------------------
while IFS= read -r line; do [ -n "$line" ] && finding "$line"; done < <(jq -r '
  (.groups | map(.id)) as $gids
  | (.components | map(.id)) as $ids
  | [
      (.components | group_by(.id) | map(select(length > 1) | .[0].id) | .[] | "duplicate id: \(.)"),
      (.components[] | select((.id // "") == "") | "a component has no id"),
      (.components[] | select(.kind == null) | "\(.id): no kind"),
      (.components[] | select((.kind | IN("links","settings","hooks","skill","upstream","command","toggle")) | not) | "\(.id): unknown kind \(.kind)"),
      (.components[] | .group as $g | select(($gids | index($g)) == null) | "\(.id): group \($g) is not declared"),
      (.components[] | .id as $id | (.requires // [])[] | . as $r | select(($ids | index($r)) == null) | "\($id): requires unknown component \($r)"),
      (.components[] | .id as $id | (.soft // [])[] | . as $r | select(($ids | index($r)) == null) | "\($id): soft edge to unknown component \($r)"),
      (.components[] | .id as $id | (.agents // [])[] | select(IN("claude","codex") | not) | "\($id): unknown agent \(.)"),
      (.components[] | select(.kind == "links" and ((.links // []) | length) == 0) | "\(.id): kind links without links"),
      (.components[] | select(.kind == "settings" and (.settings // "") == "") | "\(.id): kind settings without a settings path"),
      (.components[] | select(.kind == "hooks" and (.hooks // "") == "") | "\(.id): kind hooks without a hooks fragment path"),
      (.components[] | select(.kind == "skill" and (.skill // "") == "") | "\(.id): kind skill without a skill dir"),
      (.components[] | select(.kind == "command" and ((.install // []) | length) == 0) | "\(.id): kind command without an install argv"),
      (.components[] | select(.kind == "upstream" and ((.upstream.source // "") == "" or (.upstream.skill // "") == "")) | "\(.id): kind upstream needs upstream.source and upstream.skill"),
      (.components[] | .id as $id | (.links // [])[] | select((.type | IN("file","dir")) | not) | "\($id): link type must be file or dir: \(.home)"),
      (.components[] | .id as $id | (.links // [])[] | select(.agent != null and ((.agent | IN("claude","codex")) | not)) | "\($id): link agent must be claude or codex: \(.home)")
    ] | .[]' "$manifest")

# --- requires must be acyclic -------------------------------------------------------------
cycle="$(jq -r '
  (.components | map({key: .id, value: (.requires // [])}) | from_entries) as $g
  | def walk($n; $seen): if ($seen | index($n)) != null then [$n] else ($g[$n] // [])[] as $m | walk($m; $seen + [$n]) end;
  [ $g | keys[] as $n | walk($n; []) ] | .[0] // empty' "$manifest")"
[ -z "$cycle" ] || finding "requires cycle through ${cycle}"

# --- every declared path exists ---------------------------------------------------------
while IFS=$'\t' read -r id kind path; do
  [ -n "$path" ] || continue
  case "$kind" in
    skill) [ -f "${root}/.agents/skills/${path}/SKILL.md" ] || finding "${id}: .agents/skills/${path}/SKILL.md missing" ;;
    *)     [ -e "${root}/${path}" ] || finding "${id}: ${path} missing" ;;
  esac
done < <(jq -r '.components[] | .id as $id | ([.settings, .hooks] | map(select(. != null)) | .[] | [$id, "file", .] | @tsv), (.skill // empty | [$id, "skill", .] | @tsv)' "$manifest")

# link targets, by repo path; the generated AGENTS.md, settings.json and the Codex wiring do not
# exist before the first run, so setup.sh seeds those three and the lint skips them
while IFS=$'\t' read -r id repo; do
  case "$repo" in
    .agents/AGENTS.md|.claude/settings.json|.codex/user-hooks.json) ;;
    *) [ -e "${root}/${repo}" ] || finding "${id}: link target ${repo} missing" ;;
  esac
done < <(jq -r '.components[] | .id as $id | (.links // [])[] | [$id, .repo] | @tsv' "$manifest")

# --- fragments: a settings preset carries no hooks (the composer owns them), a hooks fragment
#     holds ${CLAUDE_PLUGIN_ROOT}/ script commands only ---------------------------------------
while IFS=$'\t' read -r id path; do
  [ -f "${root}/${path}" ] || continue
  jq -e 'has("hooks") | not' "${root}/${path}" >/dev/null 2>&1 || finding "${id}: settings preset ${path} holds a hooks key — make it a hooks fragment"
done < <(jq -r '.components[] | select(.settings != null) | [.id, .settings] | @tsv' "$manifest")
while IFS=$'\t' read -r id path; do
  [ -f "${root}/${path}" ] || continue
  jq -e '.hooks | type == "object"' "${root}/${path}" >/dev/null 2>&1 || { finding "${id}: ${path} has no .hooks object"; continue; }
  # shellcheck disable=SC2016  # the literal placeholder is the fragment contract
  bad="$(jq -r '.hooks[][]?.hooks[]? | (.command // "<no command>") | select(startswith("${CLAUDE_PLUGIN_ROOT}/") | not)' "${root}/${path}")"
  [ -z "$bad" ] || finding "${id}: ${path} holds a command that is not a \${CLAUDE_PLUGIN_ROOT}/ script path: ${bad}"
done < <(jq -r '.components[] | select(.hooks != null) | [.id, .hooks] | @tsv' "$manifest")

# --- every skill dir is declared ----------------------------------------------------------
declared="$(jq -r '[.components[] | .skill // empty, (.upstream.skill // empty)] | .[]' "$manifest")"
for d in "${root}"/.agents/skills/*/; do
  [ -d "$d" ] || continue
  name="$(basename "$d")"
  case "$name" in .*) continue ;; esac
  [ -f "${d}SKILL.md" ] || continue
  printf '%s\n' "$declared" | grep -qx "$name" || finding ".agents/skills/${name} is not declared in kit.json"
done

[ "$fail" -eq 0 ] && echo "lint-manifest: ok"
exit "$fail"
