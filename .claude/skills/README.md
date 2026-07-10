# Skills

This is the **skill catalog**. Each subdirectory here is a Claude Code skill (a `SKILL.md`
plus any files it needs). `setup.sh` lets you pick which ones to *activate*: it symlinks the
ones you choose into `~/.claude/skills/`, so you opt in per skill rather than getting all of
them at once.

## v1: bring your own

clankers-kit ships **no skills yet** — the whole point of the talk is *build your own*. Refined,
broadly-useful examples will land here over time, and PRs are welcome (see
[CONTRIBUTING.md](../../CONTRIBUTING.md)).

## Add a skill

1. Drop a skill directory here: `skills/<name>/SKILL.md` (plus any scripts it needs).
2. Re-run `./setup.sh` and pick it when prompted — or `./setup.sh --skills <name>`.

That symlinks `~/.claude/skills/<name>` → this repo, so Claude Code auto-discovers it and it's
version-controlled in your fork.
