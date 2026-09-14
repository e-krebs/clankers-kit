# Flag heuristics

A memory is flagged when any check below fires. Flags rank the interview order (worst first)
and shape the recommended verdict; the user decides.

## Mechanical checks (scriptable, run first)

| Flag | Check | Leans toward |
| --- | --- | --- |
| Dangling wikilink | a `[[slug]]` matching no memory's `name:` in any store | fix or delete the link |
| Slug drift | `name:` differs from the hyphenated filename, or is prose | normalize |
| Frontmatter shape | missing `metadata:` block, `node_type`, or `description` | normalize |
| Index mismatch | a `MEMORY.md` line disagreeing with its file, or missing/orphan lines | rebuild index |
| Age | no `modified:` touch in 60+ days | verify, then refresh or keep |
| Size | body over ~120 lines | trim to durable mechanics |

## State checks (need gh / Jira / the repo)

| Flag | Check | Leans toward |
| --- | --- | --- |
| Expired trigger | "pending/after X" where X already happened (PR merged, flag gone) | do X, delete |
| Contradicted state | a named PR/ticket/branch whose live state differs from the memory | refresh |
| Derivable status | counts, SHAs, sprint names, per-PR states that `gh`/Jira/a repo file answers | cut those lines |
| Repo-recorded | the fact sits in code, a repo doc, package.json, or a template | delete or trim to the non-derivable judgment |

## Cross-memory checks

| Flag | Check | Leans toward |
| --- | --- | --- |
| Duplicate | the same fact in 2+ memories (also across projects) | merge, one owner |
| Contradiction | two memories give opposite instructions | resolve with the user, fix both |
| Retraction below | a statement later retracted lower in the same file | rewrite in place |
| Stranded scope | a generic rule filed under a dormant or rarely-loaded project | promote |

## Covered-by-a-rule checks (need the phase-2 rules inventory)

| Flag | Check | Leans toward |
| --- | --- | --- |
| Hook-covered | a hook already denies or automates what the memory instructs | delete |
| CLAUDE.md-covered | the global instructions already state it | delete |
| Skill-covered | an installed skill's contract already encodes it | delete, or brief the gap |
| Style-covered | the output style already enforces it | delete |
