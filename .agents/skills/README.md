# Skills

This is the **skill catalog**. Each subdirectory here is a Claude Code skill (a `SKILL.md`
plus any files it needs). `setup.sh` lets you pick which ones to *activate*: it symlinks the
ones you choose into `~/.claude/skills/`, so you opt in per skill rather than getting all of
them at once.

## Bring your own — plus a few curated examples

The whole point of the talk is *build your own*, so clankers-kit stays deliberately thin: it
ships only a small set of refined, broadly-useful examples and leaves the rest to you. PRs
adding more are welcome (see [CONTRIBUTING.md](../../CONTRIBUTING.md)).

| Skill | What it does |
| --- | --- |
| [`typescript-tips`](typescript-tips/) | Fifteen TypeScript best-practice conventions to apply to the `.ts`/`.tsx` you write or edit, for type-safety and maintainability. |
| [`ticket-kickoff`](ticket-kickoff/) | Kick off work from a tracker item — read the issue and any linked spec, plan in plan-mode, then move it to In Progress on approval (every mutation deferred until you accept the plan). |
| [`rebase-branch`](rebase-branch/) | Rebase the current branch onto its freshly-fetched base with a no-work-lost guarantee — auto-skips already-integrated commits and escalates only genuinely complex conflicts. |
| [`changes-to-pr`](changes-to-pr/) | Turn uncommitted changes into a branch, atomic conventional commits, and a draft PR (optional agent review + linked-issue move) behind a two-gate approval flow. |
| [`pr-followup`](pr-followup/) | After a push or PR, watch CI and advance it — on green mark a draft ready / re-request a stale review / move the linked issue forward; on red analyse and report. Never merges or auto-fixes. |

## Add a skill

1. Drop a skill directory here: `skills/<name>/SKILL.md` (plus any scripts it needs).
2. Re-run `./setup.sh` and pick it when prompted — or `./setup.sh --skills <name>`.

That symlinks `~/.claude/skills/<name>` → this repo, so Claude Code auto-discovers it and it's
version-controlled in your fork.

## Grab a single skill into any agent

Owning the whole kit (above) is the intended path. But if you just want one skill dropped into
any agent — without cloning — use [`npx skills`](https://github.com/vercel-labs/skills):

```bash
npx skills add e-krebs/clankers-kit --skill typescript-tips
```

It copies the whole skill directory (including its `references/`), so nothing is left behind.
This is skill *distribution*, not a dependency to install — the kit itself is still yours to own.
