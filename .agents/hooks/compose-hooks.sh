#!/usr/bin/env bash
# Composes the hook wiring files from hooks.json fragments: the shared one in this directory and
# one per skill under skills/<name>/hooks/. A fragment is plugin hooks.json content whose script
# commands read "${CLAUDE_PLUGIN_ROOT}/<path>"; the composer substitutes --root, wraps the path in
# bash "...", and passes any other command through untouched (inline hooks). Each script must
# exist under the local root and carry a header line "# codex: yes", "# codex: no" or
# "# codex: yes args=<string>": "no" drops it from the Codex output, args are appended to the
# Codex command only. The Codex output also renames Notification to PermissionRequest (no
# matcher) and caps SessionEnd timeouts at 3. Only the .hooks key of each output changes.
#
# Usage: compose-hooks.sh --root <install root> --own all|skills|root --claude <settings.json>
#        [--codex <hooks.json>] [--local <checkout root>] [<fragment>...]
#   --own all     replace the whole .hooks key (every hook here is composed); needs a fragment
#   --own skills  replace only the entries under <root>/skills/*/hooks/, keep the rest; takes
#                 skills/*/hooks/hooks.json fragments only, and those hold script hooks only
#   --own root    replace the entries this composer wrote: a quoted script path under <root>/
#                 that any fragment under --local declares (hooks/*.json, skills/*/hooks/
#                 hooks.json, passed or not) or that is shaped hooks/*.sh or skills/*/hooks/*.sh
#                 with no script under --local nor at <root> itself (a leading $HOME in <root>
#                 is expanded for that test); keep every other entry, and list both the kept
#                 entries under <root>/ and the dropped stale ones on stderr. Script hooks only.
#                 No fragment strips the owned set. A skill another tool installed under
#                 <root>/skills/ is live at <root>, so its entry stays even though --local
#                 knows nothing of it.
#   --local       the checkout dir that --root stands for; default: this script's parent dir
# Fragments compose in the order given; events follow a fixed order, entries the fragment order.
# Both outputs are built and validated before either is written; a write is atomic and skipped
# when .hooks is unchanged.
set -euo pipefail

root="" own="" claude_out="" codex_out="" local_root=""
frags=()
while [ $# -gt 0 ]; do
  case "$1" in
    --root) root="$2"; shift 2 ;;
    --own) own="$2"; shift 2 ;;
    --claude) claude_out="$2"; shift 2 ;;
    --codex) codex_out="$2"; shift 2 ;;
    --local) local_root="$2"; shift 2 ;;
    -h|--help) sed -n '2,/^set -euo/{/^set -euo/!p;}' "$0"; exit 0 ;;
    --) shift; frags+=("$@"); break ;;
    -*) echo "compose-hooks: unknown flag $1" >&2; exit 2 ;;
    *) frags+=("$1"); shift ;;
  esac
done
[ -n "$root" ] || { echo "compose-hooks: --root is required" >&2; exit 2; }
[ -n "$claude_out" ] || { echo "compose-hooks: --claude is required" >&2; exit 2; }
[ "$own" = all ] || [ "$own" = skills ] || [ "$own" = root ] || { echo "compose-hooks: --own must be all, skills or root" >&2; exit 2; }
[ ${#frags[@]} -gt 0 ] || [ "$own" != all ] || { echo "compose-hooks: no fragment given" >&2; exit 2; }
[ -n "$local_root" ] || local_root="$(dirname "${BASH_SOURCE[0]}")/.."
[ -d "$local_root" ] || { echo "compose-hooks: --local is not a directory: $local_root" >&2; exit 2; }
local_root="$(CDPATH='' cd -P "$local_root" && pwd)"
root="${root%/}"

# --- validate fragments and collect script metadata -----------------------------------------
# meta: {"<rel path>": {"codex": "yes|no", "args": "<string>"}}
meta='{}'
for frag in ${frags[@]+"${frags[@]}"}; do
  [ -f "$frag" ] || { echo "compose-hooks: fragment not found: $frag" >&2; exit 1; }
  jq -e '.hooks | type == "object"' "$frag" >/dev/null 2>&1 \
    || { echo "compose-hooks: $frag is not a hooks.json fragment (.hooks object missing)" >&2; exit 1; }
  # --own skills keeps every non-skill entry as found, so a shared fragment would duplicate on each run
  if [ "$own" = skills ]; then
    case "$(CDPATH='' cd -P "$(dirname "$frag")" && pwd)" in
      "$local_root"/skills/*) ;;
      *) echo "compose-hooks: --own skills takes skills/*/hooks/hooks.json fragments only: $frag" >&2; exit 2 ;;
    esac
  fi
  # an entry without a command (a prompt hook) has no path either, so the two narrow modes refuse it
  if [ "$own" != all ] && [ "$(jq -r '[.hooks[][]?.hooks[]? | select(has("command") | not)] | length' "$frag")" != 0 ]; then
    echo "compose-hooks: $frag: --own $own takes script hooks only, this fragment holds an entry without a command" >&2; exit 1
  fi
  while IFS= read -r cmd; do
    [ -n "$cmd" ] || continue
    # shellcheck disable=SC2016  # the literal placeholder is the contract, not an expansion
    case "$cmd" in
      '${CLAUDE_PLUGIN_ROOT}/'*) ;;
      *'${CLAUDE_PLUGIN_ROOT}'*)
        echo "compose-hooks: $frag: a script command holds the path only, arguments go in the header: $cmd" >&2; exit 1 ;;
      *)
        # an inline entry carries no path, so --own skills and --own root could never tell it apart from a foreign one
        if [ "$own" != all ]; then
          echo "compose-hooks: $frag: --own $own takes script hooks only, move this inline command into a script: $cmd" >&2; exit 1
        fi
        continue ;;
    esac
    rel="${cmd#\$\{CLAUDE_PLUGIN_ROOT\}/}"
    case "$rel" in
      *' '*|*'"'*) echo "compose-hooks: $frag: a script command holds the path only, arguments go in the header: $cmd" >&2; exit 1 ;;
    esac
    script="$local_root/$rel"
    [ -f "$script" ] || { echo "compose-hooks: $frag: script not found: $script" >&2; exit 1; }
    header=$(grep -m1 -E '^# codex: (yes|no)( args=.+)?$' "$script" || true)
    [ -n "$header" ] || { echo "compose-hooks: $script: missing '# codex: yes|no' header line" >&2; exit 1; }
    mode="${header#\# codex: }"
    args=""
    case "$mode" in
      "yes args="*) args="${mode#yes args=}"; mode=yes ;;
    esac
    meta=$(jq -c --arg rel "$rel" --arg mode "$mode" --arg args "$args" '.[$rel] = {codex: $mode, args: $args}' <<< "$meta")
  done < <(jq -r '.hooks[][]?.hooks[]?.command // empty' "$frag")
done

# --- compose ------------------------------------------------------------------------------
# shellcheck disable=SC2016  # jq programs: $meta, $root and the placeholder are jq-side names
compose_program='
def event_order: ["SessionStart","SessionEnd","Notification","PermissionRequest","Stop","PreToolUse","UserPromptSubmit","PostToolUse"];
def rewrite_hook:
  if ((.command // "") | startswith("${CLAUDE_PLUGIN_ROOT}/")) then
    (.command | ltrimstr("${CLAUDE_PLUGIN_ROOT}/")) as $rel
    | $meta[$rel] as $m
    | if $agent == "codex" and $m.codex == "no" then empty
      else .command = "bash \"" + $root + "/" + $rel + "\"" + (if $agent == "codex" and $m.args != "" then " " + $m.args else "" end)
      end
  else . end;
def codex_group($event):
  if $agent != "codex" then . else
    (if $event == "Notification" then del(.matcher) else . end)
    | if $event == "SessionEnd" then .hooks |= map(if has("timeout") then .timeout |= ([., 3] | min) else . end) else . end
  end;
def codex_event: if $agent == "codex" and . == "Notification" then "PermissionRequest" else . end;
# flatten every fragment into [{event, group}] in order
[ .[] | .hooks | to_entries[] | .key as $e | .value[] | {event: ($e | codex_event), group: (codex_group($e) | .hooks |= map(rewrite_hook))} ]
| map(select(.group.hooks | length > 0))
| (map(.event) | unique) as $present
| ((event_order | map(select(. as $o | $present | index($o)))) + ($present - event_order | sort)) as $ordered
| . as $flat
| reduce $ordered[] as $e ({}; .[$e] = [ $flat[] | select(.event == $e) | .group ])
'

compose_for() {  # $1 = claude|codex -> composed .hooks object on stdout
  if [ ${#frags[@]} -eq 0 ]; then echo '{}'; return 0; fi
  jq -s --arg agent "$1" --arg root "$root" --argjson meta "$meta" "$compose_program" "${frags[@]}"
}

# --own root: the paths every fragment under --local declares, passed to this run or not
declared='[]'
if [ "$own" = root ]; then
  for f in "$local_root"/hooks/*.json "$local_root"/skills/*/hooks/hooks.json; do
    [ -f "$f" ] || continue
    jq -e '.hooks | type == "object"' "$f" >/dev/null 2>&1 || continue
    # shellcheck disable=SC2016  # the literal placeholder is the contract, not an expansion
    add=$(jq -c '[.hooks[][]?.hooks[]?.command // empty | select(startswith("${CLAUDE_PLUGIN_ROOT}/")) | ltrimstr("${CLAUDE_PLUGIN_ROOT}/")]' "$f")
    declared=$(jq -c -n --argjson a "$declared" --argjson b "$add" '$a + $b | unique')
  done
fi

# shellcheck disable=SC2016  # jq programs
root_qpath='def qpath: ((.command // "") | split("\"") | (.[1] // ""));'
root_shape='^(hooks/[^/]+\.sh|skills/[^/]+/hooks/[^/]+\.sh)$'

root_missing() {  # $1 = existing doc -> JSON list of stale-shaped paths under <root>/ with no script under --local nor at <root>
  # a leading $HOME in <root> is expanded for the on-disk test, so a skill another tool installed
  # under <root>/skills/ (live there, absent under --local) is never called stale
  local out='[]' rel root_fs="${root/#\$HOME/$HOME}"
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    [ -f "$local_root/$rel" ] || [ -f "$root_fs/$rel" ] || out=$(jq -c --arg r "$rel" '. + [$r]' <<< "$out")
  done < <(jq -r --arg root "$root" --arg shape "$root_shape" "$root_qpath"'
    [.hooks[]?[]?.hooks[]? | qpath | select(startswith($root + "/")) | ltrimstr($root + "/") | select(test($shape))] | unique | .[]' <<< "$1")
  printf '%s' "$out"
}

root_report_kept() {  # $1 = existing doc, $2 = missing list, $3 = label -> one stderr line per entry under <root>/ that survives
  jq -r --arg root "$root" --argjson declared "$declared" --argjson missing "$2" --arg label "$3" "$root_qpath"'
    [.hooks[]?[]?.hooks[]? | qpath | select(startswith($root + "/")) | . as $p | ltrimstr($root + "/") as $r
     | select((($declared | index($r)) == null) and (($missing | index($r)) == null)) | $p] | unique | .[]
    | "compose-hooks: kept an entry under " + $root + " that no fragment declares (" + $label + "): " + .' <<< "$1" >&2
}

# merge the composed .hooks into an existing document, honoring --own
# shellcheck disable=SC2016
merge_program='
def qpath: ((.command // "") | split("\"") | (.[1] // ""));
def rel: (qpath | ltrimstr($root + "/"));
def owned:
  if $own == "skills" then ((.command // "") | contains($root + "/skills/"))
  else (rel as $r | (qpath | startswith($root + "/")) and ((($declared | index($r)) != null) or (($missing | index($r)) != null)))
  end;
(if $own == "all" then {} else
  ((.hooks // {}) | with_entries(.value |= (map(.hooks |= map(select(owned | not))) | map(select(.hooks | length > 0)))) | with_entries(select(.value | length > 0)))
 end) as $kept
| .hooks = (reduce (($kept | keys_unsorted) + ($composed | keys_unsorted) | unique)[] as $e ({};
    .[$e] = (($kept[$e] // []) + ($composed[$e] // [])))
  | with_entries(select(.value | length > 0)))
| .hooks |= (to_entries | sort_by(.key as $k | (["SessionStart","SessionEnd","Notification","PermissionRequest","Stop","PreToolUse","UserPromptSubmit","PostToolUse"] | index($k)) // 99, .key) | from_entries)
'

build_output() {  # $1 = agent, $2 = target path -> full document on stdout
  local existing='{}' missing='[]'
  [ -f "$2" ] && existing=$(jq -c . "$2")
  if [ "$own" = root ]; then
    missing=$(root_missing "$existing")
    root_report_kept "$existing" "$missing" "$1"
    jq -r --arg root "$root" --arg label "$1" '.[] | "compose-hooks: dropped a stale entry under " + $root + " whose script is gone (" + $label + "): " + $root + "/" + .' <<< "$missing" >&2
  fi
  jq --arg own "$own" --arg root "$root" --argjson declared "$declared" --argjson missing "$missing" \
    --argjson composed "$(compose_for "$1")" "$merge_program" <<< "$existing"
}

resolve_target() {  # follow symlinks so the write lands on the real file
  local p="$1" dir
  while [ -L "$p" ]; do
    dir=$(dirname "$p")
    p=$(readlink "$p")
    case "$p" in /*) ;; *) p="$dir/$p" ;; esac
  done
  printf '%s' "$p"
}

write_output() {  # $1 = label, $2 = target path, $3 = document
  local target tmp
  target=$(resolve_target "$2")
  if [ -f "$target" ] && [ "$(jq -S .hooks "$target")" = "$(jq -S .hooks <<< "$3")" ]; then
    echo "compose-hooks: $1 unchanged ($2)"
    return 0
  fi
  tmp="${target}.tmp.$$"
  printf '%s\n' "$3" > "$tmp"
  mv -f "$tmp" "$target"
  echo "compose-hooks: $1 written ($2)"
}

claude_doc=$(build_output claude "$claude_out")
jq -e '.hooks | type == "object"' <<< "$claude_doc" >/dev/null
codex_doc=""
if [ -n "$codex_out" ]; then
  codex_doc=$(build_output codex "$codex_out")
  jq -e '.hooks | type == "object"' <<< "$codex_doc" >/dev/null
fi

write_output claude "$claude_out" "$claude_doc"
[ -z "$codex_out" ] || write_output codex "$codex_out" "$codex_doc"
