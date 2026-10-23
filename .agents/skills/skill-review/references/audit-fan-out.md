# Audit fan-out

Read this file when a run has no argument or `gather`, and either two or more targets or one
target over ~150 lines or with `references/`. A short single target stays inline. Steps 1-3
then run in one read-only subagent per target, so the target bodies stay out of the main
context. Pick the tier from `~/.agents/workflow-models/tiers.md` by the shape of the work (a
self-contained read of one target). If that file is absent, name a cheaper agent than the
general-purpose default instead.

The order is:

1. The main agent runs step 1's prose lookup.
2. The subagents run the rest of step 1, then steps 2-3.
3. The main agent loads the conventions itself before step 5 applies a fix.

The main agent sends each subagent the target path, the path of skill-review's SKILL.md, the
prose source (a path to read, or `fallback checklist` plus why), and the installed skill names
for step 3. Each subagent grades the target against the Checklist, the progressive-disclosure
rubric and that SKILL.md's `Delegation and context rubric` section. Each subagent returns one
row per finding (section, quoted lines, flag, proposed fix), or one line for a clean skill, and
always its prose-pass row naming the source it applied. A rubric finding names its rubric row as
the flag. A reference-only target returns one N/A line for the delegation rubric. The return
holds at most 20 finding rows plus the prose-pass row. On overflow, the subagent writes its full
list to `<scratch>/<skill>-findings.md` (the harness's scratch directory, else a directory from
`mktemp -d`) and the overflow line names that path instead of a count. When a return lacks the
prose-pass row, re-run that subagent. When an overflow line names a path, step 5 reads that
file before proposing fixes for that skill.

`apply <path>` never fans out, and a run with no subagent tool stays inline.
