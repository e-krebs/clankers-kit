#!/usr/bin/env bash
# SessionStart hook: surface the resolved workflow profile (org template + repo override) for
# this cwd as additionalContext, so skills can read the rows straight from context instead of
# re-reading the files. When nothing resolves, nudge once per repo to run /workflow-profile,
# then stay quiet (a ".asked/<key>" marker records the nudge).
#
# Fails open everywhere: bad/missing stdin, a subagent session, a cwd outside any git repo, or
# any resolution error all just exit 0 with no output.
# codex: yes

hooks_lib="${AGENTS_HOOKS_LIB:-$(dirname "${BASH_SOURCE[0]}")/../../../hooks/lib}"
[ -f "$hooks_lib/hook-log.sh" ] || hooks_lib="$HOME/.claude/hooks/lib"
# shellcheck source=../../../hooks/lib/hook-log.sh
source "$hooks_lib/hook-log.sh"

input=$(jq -c 'select(type == "object")' 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0                        # empty stdin, null or a scalar: nothing to act on

HOOK_SESSION=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)

agent_id=$(printf '%s' "$input" | jq -r '.agent_id // empty' 2>/dev/null)
[ -z "$agent_id" ] || exit 0

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$cwd" ] || cwd=$PWD
[ -d "$cwd" ] || exit 0

is_repo=$(command cd "$cwd" 2>/dev/null && git rev-parse --is-inside-work-tree 2>/dev/null)
[ "$is_repo" = "true" ] || exit 0

resolver="${AGENTS_WORKFLOW_RESOLVER:-$HOME/.agents/skills/workflow-profile/scripts/resolve-profile.sh}"
[ -f "$resolver" ] || exit 0                     # the setup skill is not installed: nothing to resolve
# shellcheck source=../../workflow-profile/scripts/resolve-profile.sh
source "$resolver" || exit 0
resolve_profile "$cwd"

if profile_resolved; then
  org_label="none"
  [ -n "$PROFILE_ORG_FILE" ] && org_label="$PROFILE_OWNER"
  repo_label="none"
  [ -n "$PROFILE_REPO_FILE" ] && repo_label="$PROFILE_REPO"
  org_path="${PROFILE_ORG_FILE:-none}"
  repo_path="${PROFILE_REPO_FILE:-none}"

  header="Workflow profile resolved (org: ${org_label}, repo override: ${repo_label}). Files: ${org_path}; ${repo_path}. Skills read these rows from context and re-read the files only when absent."
  rows=$(profile_rows)
  context="${header}
${rows}"

  if [ -n "$PROFILE_ORG_FILE" ] && grep -q '^## Tracker rules' "$PROFILE_ORG_FILE" 2>/dev/null; then
    context="${context}
Tracker rules live in ${PROFILE_ORG_FILE} under ## Tracker rules."
  fi

  hook_log nudge resolved
  jq -nc --arg ctx "$context" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}'
  exit 0
fi

marker="$PROFILES_DIR/.asked/$PROFILE_KEY"
[ -e "$marker" ] && exit 0

mkdir -p "$PROFILES_DIR/.asked" 2>/dev/null
: > "$marker" 2>/dev/null

if [ "$PROFILE_KIND" = "remote" ]; then
  msg="No workflow profile for ${PROFILE_OWNER}/${PROFILE_REPO} (remote). Run /workflow-profile to configure it; suggested org template: ${PROFILE_OWNER}.md."
else
  msg="No workflow profile for ${PROFILE_REPO} (no remote). Run /workflow-profile to configure it as repos/${PROFILE_REPO}.md."
fi

hook_log nudge unresolved
jq -nc --arg ctx "$msg" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}'
exit 0
