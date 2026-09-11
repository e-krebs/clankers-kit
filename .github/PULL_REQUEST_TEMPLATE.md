## What & why

<!-- What does this change, and why? -->

## Type

- [ ] New skill
- [ ] Hook / setting preset
- [ ] Port to another agent (Cursor, Aider, …)
- [ ] Docs
- [ ] Other:

## Checklist

- [ ] No personal data (names other than authorship, emails, employer/project names, ticket IDs, absolute paths)
- [ ] `shellcheck $(git ls-files '*.sh')` passes
- [ ] Tested `setup.sh` in a sandbox `HOME` (not my real `~/.claude`)
- [ ] A hook change comes with a fixture case (`bash .agents/hooks/run-fixtures.sh` passes)
- [ ] Anything opinionated is opt-in and documented
