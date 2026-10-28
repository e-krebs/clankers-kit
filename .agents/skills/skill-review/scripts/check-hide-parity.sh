#!/usr/bin/env bash
# Flags a skill hidden in one harness only: Claude reads disable-model-invocation in the
# frontmatter, Codex reads policy.allow_implicit_invocation in agents/openai.yaml.
set -u

agents_dir=$(CDPATH='' cd -P "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
status=0

for skill_md in "$agents_dir"/skills/*/SKILL.md; do
  [ -f "$skill_md" ] || continue
  skill_dir=$(dirname "$skill_md")
  name=$(basename "$skill_dir")

  claude_hidden=no
  if sed -n '2,/^---$/p' "$skill_md" | grep -q '^disable-model-invocation: *true'; then
    claude_hidden=yes
  fi

  codex_hidden=no
  yaml="$skill_dir/agents/openai.yaml"
  if [ -f "$yaml" ] && sed -n '/^policy:/,/^[^ ]/p' "$yaml" | grep -q 'allow_implicit_invocation: *false'; then
    codex_hidden=yes
  fi

  if [ "$claude_hidden" = yes ] && [ "$codex_hidden" = no ]; then
    printf '%s: hidden in claude only\n' "$name"
    status=1
  elif [ "$claude_hidden" = no ] && [ "$codex_hidden" = yes ]; then
    printf '%s: hidden in codex only\n' "$name"
    status=1
  fi
done

exit "$status"
