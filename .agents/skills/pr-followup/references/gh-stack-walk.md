# PR-graph walk (stack without local metadata)

Verified against `gh stack` v0.1.0.

Load this file when Step 0's lookup reports membership absent or unknown. The metadata records
**local tracking only**, so a stack `gh stack link` created is invisible to the lookup, and this
read-only walk settles whether a stack exists anyway.

There is no member list yet, so resolve the current branch's PR first with `$PRS --stack`. The
`--stack` fields (`baseRefName`, `isCrossRepository`) are the ones the walk needs. Step 0's missing-PR
rules apply: no live PR means nothing to walk and nothing to advance. Take the trunk from the
profile's Default branch row. That PR's own `baseRefName` and `headRefName` are the walk's two
starting points.

<!-- The three walk rules below are mirrored from the rebase capability's own cascade reference,
     sentence for sentence, so a diff across the two files catches drift. -->

Ask the PR graph, read-only, with **filtered** queries and no repo-wide scan — `gh pr list`
fetches 30 items by default, and an unfiltered listing on a busy repo silently misses the very PRs
that matter:

```
gh pr list --state open --base <b>               # what is stacked on <b>
gh pr list --state open --head <its baseRefName> # what <b> is stacked on
```

each carrying `number,url,headRefName,baseRefName,isCrossRepository`. Then **walk the chain in both
directions until nothing new appears**, one branch at a time. Run the `--base` query **even when
this PR's own base is the trunk**: that is the bottom-of-stack case, where a base test alone finds
nothing while children sit above. **Skip a `--head` query whose value is the trunk**: a repo
carrying a standing open trunk-to-release PR would otherwise make every ordinary PR look like a
chain. **Drop the cross-repo PRs.** `isCrossRepository` true means `headRefName` names a branch in
a fork, which is not a local branch and nothing here may act on it. Name them and exclude them. If the
walk finds no chain, close this file and take Step 0's single-PR path.

If it finds a chain, its branches and PR numbers, bottom to top, are the member list. Read
[gh-stack-followup.md](gh-stack-followup.md) in full and run it from F1.

Done when the walk has either handed a member list to that file or returned to Step 0's single-PR
path with the PR already resolved.
