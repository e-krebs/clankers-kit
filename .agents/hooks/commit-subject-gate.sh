#!/usr/bin/env bash
# PreToolUse(Bash) gate: block a "git commit" whose subject isn't "type(scope): text", or that
# smuggles a ticket key into the subject (a ticket ref belongs in the PR body, not the subject).
# Profile-gated: only runs when the resolved profile's Commit convention starts with
# "conventional" (case-insensitive); every other repo is skipped.
#
# Fails open everywhere: bad/missing stdin, a subagent session, no "git commit" in the command,
# no profile resolved, a non-conventional profile, an editor/-F commit, --amend --no-edit,
# --fixup, --squash, a Merge/Revert subject, or a $-prefixed subject all just exit 0, no output.
# codex: yes

input=$(jq -c 'select(type=="object")' 2>/dev/null) || exit 0
[ -n "$input" ] || exit 0

source "$(dirname "${BASH_SOURCE[0]}")/lib/hook-log.sh"
HOOK_SESSION=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)

agent_id=$(printf '%s' "$input" | jq -r '.agent_id // empty' 2>/dev/null)
[ -z "$agent_id" ] || exit 0

cmd=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -n "$cmd" ] || exit 0

case "$cmd" in
  *"git commit"*) ;;
  *) exit 0 ;;
esac

cwd=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$cwd" ] || cwd=$PWD

resolver="${AGENTS_WORKFLOW_RESOLVER:-$HOME/.agents/skills/workflow-profile/scripts/resolve-profile.sh}"
[ -f "$resolver" ] || exit 0
# shellcheck source=../skills/workflow-profile/scripts/resolve-profile.sh
source "$resolver" || exit 0
resolve_profile "$cwd"

convention=$(profile_field "Commit convention") || exit 0
[ -n "$convention" ] || exit 0

low=$(printf '%s' "$convention" | tr '[:upper:]' '[:lower:]')
case "$low" in
  conventional*) ;;
  *) exit 0 ;;
esac

deny() {  # $1 = reason shown back to Claude, $2 = rule id
  hook_log deny "$2"
  jq -nc --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

# --- isolate the "git commit" segment: from "git commit" onward, cut at the next unquoted
#     ; & or | (best-effort: a single/double-quote tracker, no heredoc awareness beyond that
#     the heredoc body sits inside the outer -m "..." double quotes anyway). --------------
rest="${cmd#*git commit}"
seg="git commit${rest}"

seg_len=${#seg}
in_sq=0
in_dq=0
cut=$seg_len
i=0
while [ "$i" -lt "$seg_len" ]; do
  c="${seg:$i:1}"
  if [ "$in_sq" -eq 1 ]; then
    [ "$c" = "'" ] && in_sq=0
  elif [ "$in_dq" -eq 1 ]; then
    [ "$c" = '"' ] && in_dq=0
  else
    case "$c" in
      "'") in_sq=1 ;;
      '"') in_dq=1 ;;
      ';'|'&'|'|') cut=$i; break ;;
    esac
  fi
  i=$((i + 1))
done
seg="${seg:0:$cut}"

# --- unconditional skips: amend-without-a-new-message, fixup, squash --------------------
printf '%s' "$seg" | grep -qE -- '(^|[[:space:]])--fixup([[:space:]=]|$)' && exit 0
printf '%s' "$seg" | grep -qE -- '(^|[[:space:]])--squash([[:space:]=]|$)' && exit 0
if printf '%s' "$seg" | grep -qE -- '(^|[[:space:]])--amend([[:space:]]|$)' \
   && printf '%s' "$seg" | grep -qE -- '(^|[[:space:]])--no-edit([[:space:]]|$)'; then
  exit 0
fi

# --- subject extraction, in order: heredoc, --message=, first -m ------------------------
subject=""
found=0

lines=()
while IFS= read -r line; do
  lines+=("$line")
done <<EOF
$seg
EOF

for idx in "${!lines[@]}"; do
  if printf '%s' "${lines[$idx]}" | grep -qE -- '-m[[:space:]]+"\$\(cat[[:space:]]*<<'; then
    next=$((idx + 1))
    if [ "$next" -lt "${#lines[@]}" ]; then
      subject="${lines[$next]}"
      found=1
    fi
    break
  fi
done

# first message argument in command order, -m or --message=, so a later one is body
if [ "$found" -eq 0 ]; then
  mtoken=$(printf '%s' "$seg" | grep -oE -- '(^|[[:space:]])(-m[[:space:]]+|--message=)("[^"]*"|'"'"'[^'"'"']*'"'"'|[^[:space:]]+)' | head -1)
  if [ -n "$mtoken" ]; then
    case "$mtoken" in
      *--message=*) subject="${mtoken#*--message=}" ;;
      *) subject="${mtoken#*-m}" ;;
    esac
    found=1
  fi
fi

[ "$found" -eq 1 ] || exit 0   # no -m/--message at all: editor or -F, nothing to check

# trim surrounding whitespace, then strip one layer of matching quotes
subject="${subject#"${subject%%[![:space:]]*}"}"
subject="${subject%"${subject##*[![:space:]]}"}"
case "$subject" in
  \"*\") subject="${subject#\"}"; subject="${subject%\"}" ;;
  \'*\') subject="${subject#\'}"; subject="${subject%\'}" ;;
esac

case "$subject" in
  '$'*) exit 0 ;;                      # unresolved variable subject: fail open
  "Merge "*|"Revert "*) exit 0 ;;      # auto-generated merge/revert subject
esac

if ! printf '%s' "$subject" | grep -qE '^[a-z]+\([^)]+\): .+'; then
  deny "Commit subject \"$subject\" doesn't match the required shape type(scope): text — e.g. feat(hooks): add x." "shape"
fi

shopt -s extglob
stripped="${subject//@(UTF|SHA|ISO|RFC|MD|ES)-+([0-9])/}"
shopt -u extglob

if printf '%s' "$stripped" | grep -qE '[A-Z]{2,}-[0-9]+'; then
  deny "Commit subject \"$subject\" holds a ticket key — a ticket reference belongs in the PR body only, not the subject." "ticket"
fi

exit 0
