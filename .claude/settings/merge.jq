# Apply preset fragments onto a settings document, ADDITIVELY: objects recurse, arrays union (the
# existing order is kept, new entries are appended once), and a scalar is set only when absent.
# Nothing is ever removed, so re-running setup.sh is safe and opting a preset out later is a
# manual edit. setup.sh loads this as a module:
#   jq -s 'include "merge"; reduce .[] as $frag ({}; apply(.; $frag))' -L .claude/settings \
#      <settings.json or base.json> <selected fragments...>
def apply($a; $b):
  reduce ($b | keys_unsorted[]) as $k ($a;
    if   (($a[$k] | type) == "object") and (($b[$k] | type) == "object")
    then .[$k] = apply($a[$k]; $b[$k])
    elif (($a[$k] | type) == "array")  and (($b[$k] | type) == "array")
    then .[$k] = ($a[$k] + reduce ($b[$k] - $a[$k])[] as $x ([]; if index($x) != null then . else . + [$x] end))
    elif ($a | has($k))
    then .
    else .[$k] = $b[$k]
    end
  );
