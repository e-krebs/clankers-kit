# Deep-merge JSON objects, CONCATENATING arrays (so multiple presets can each contribute
# to permissions.allow / hooks.* without clobbering each other). Used by setup.sh to
# compose ~/.claude/settings.json from base.json + the selected preset fragments:
#   jq -s -f merge.jq base.json <selected fragments...>
def deepmerge($a; $b):
  reduce ($b | keys_unsorted[]) as $k ($a;
    if   (($a[$k] | type) == "object") and (($b[$k] | type) == "object")
    then .[$k] = deepmerge($a[$k]; $b[$k])
    elif (($a[$k] | type) == "array")  and (($b[$k] | type) == "array")
    then .[$k] = ($a[$k] + $b[$k])
    else .[$k] = $b[$k]
    end
  );
reduce .[] as $frag ({}; deepmerge(.; $frag))
