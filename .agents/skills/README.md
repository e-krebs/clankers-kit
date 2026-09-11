# Skills

This is the **skill catalog**. Each subdirectory here is a skill (a `SKILL.md` plus any files it
needs: `references/`, `scripts/`, `evals/`, and for some a `hooks/` dir with its `hooks.json`
fragment and fixtures). `setup.sh` symlinks the ones you keep into both `~/.claude/skills/` and
`~/.agents/skills/` (Codex and Cursor read `~/.agents/skills/`), so you opt in per skill rather
than getting all of them at once. Every row is on by default in the picker; uncheck what you
don't want.

## Workflow skills

A composable family that reads one shared contract, the workflow profile (`workflow-profile`
writes it): the ticket system, the commit policy, the CI watcher, the verify commands. The usual
order is ticket-kickoff → write-plan → verify → review-changes → changes-to-pr → pr-followup →
pr-merge, and each skill still works on its own when typed as `/name`. The map with a diagram
lives in [workflow-profile/references/workflow-map.md](workflow-profile/references/workflow-map.md).

| Skill | What it does |
| --- | --- |
| [`workflow-profile`](workflow-profile/) | Create or refresh the workflow profile of the current repo (the org template plus the per-repo override). Typed only. |
| [`write-plan`](write-plan/) | Write the plan file for a piece of work: explore, interview, pick the model, run the plan review, then leave plan mode. |
| [`ticket-kickoff`](ticket-kickoff/) | Kick off a ticket: read it and any linked spec, then hand the work to planning. |
| [`verify`](verify/) | Run every check the repo's workflow profile lists, in parallel, and report one verdict each with every failure quoted. |
| [`changes-to-pr`](changes-to-pr/) | Turn working-tree changes into atomic commits and, where the repo's policy calls for one, a branch and a PR with a drafted description. |
| [`pr-followup`](pr-followup/) | Watch CI after a push or PR-create and advance the PR: green marks a draft ready or re-requests a stale review, red reports the failures. |
| [`pr-merge`](pr-merge/) | Merge an approved PR the way the profile prescribes: squash, delete the branch, move the linked ticket to Done, restack dependants. |
| [`rebase-branch`](rebase-branch/) | Rebase the current branch, or the whole stack it belongs to, onto its freshly-fetched base, losing no work from either side. |

## Review skills

| Skill | What it does |
| --- | --- |
| [`review-changes`](review-changes/) | Run independent reviewers over a working tree, a branch, a PR or a plan file, then triage their findings into one severity-ranked report. |
| [`skill-review`](skill-review/) | Review a skill or every installed skill for authoring quality: description triggers, completion criteria, no-ops, lint score, cross-references. |
| [`hooks-review`](hooks-review/) | Audit the hooks layer: inventory every hook, prune what drifted, and suggest new hooks from evidence. |
| [`memory-review`](memory-review/) | Audit the agent-memory store project by project: flag stale, duplicate and rule-covered memories, decide each with you, apply and commit. |
| [`clankers-review`](clankers-review/) | Run the full config audit behind two gates: pick sub-topics (memories, hooks, skills, AGENTS.md), gather, approve each change, apply, review. |

## Other skills

| Skill | What it does |
| --- | --- |
| [`typescript-tips`](typescript-tips/) | TypeScript best-practice conventions to apply to the `.ts`/`.tsx` you write, edit or review. |
| `writing-for-agents` | Matt Pocock's guide to writing documents for agents; `skill-review` reads it when present. Not tracked here: `setup.sh` installs it with `npx skills add mattpocock/skills --skill writing-for-agents` into `~/.agents/skills/`. |

## Skill hooks

A skill that ships a `hooks/` dir carries the hooks that trigger or guard it (a nudge when your
prompt matches, a gate on a step), next to their `hooks.json` fragment and fixtures. They stay
inert until the `skill trigger hooks` row of `setup.sh` is on: the composer then wires the hooks
of every active skill into `~/.claude/settings.json` and, for Codex, `~/.codex/hooks.json`.
`commit-subject-gate` lives in [`.agents/hooks/`](../hooks/) instead, because it enforces a
profile row rather than a skill.

## Add a skill

1. Drop a skill directory here: `skills/<name>/SKILL.md` (plus any scripts it needs, and an
   optional `hooks/` dir with its fragment and fixtures).
2. Add a `skill` row to `kit.json` with its `requires` and `soft` edges, run
   `bash .agents/lint-manifest.sh`, and add the row to the tables above.
3. Re-run `./setup.sh` and pick it when prompted — or `./setup.sh --skills <name>`.

That symlinks `~/.claude/skills/<name>` and `~/.agents/skills/<name>` → this repo, so your
agents auto-discover it and it's version-controlled in your fork.

## Grab a single skill into any agent

Owning the whole kit (above) is the intended path. But if you just want one skill dropped into
any agent — without cloning — use [`npx skills`](https://github.com/vercel-labs/skills):

```bash
npx skills add e-krebs/clankers-kit --skill typescript-tips
```

It copies the whole skill directory (including its `references/` and `hooks/`), so nothing is
left behind; the hooks stay unwired, because only `setup.sh` runs the composer. The workflow
skills expect the workflow profile and `ticket-kickoff` hands off to `write-plan`, so grab
those as a set; `pr-merge` restacks through `rebase-branch` and the review skills read
`skill-review` when present, and each says so when the sibling is absent (the `soft` edges in
`kit.json`). This is skill *distribution*, not a dependency to install — the kit itself is
still yours to own.
