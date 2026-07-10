# Project memories live here

Claude Code writes per-project **memories** under `.claude/projects/<project>/memory/`, and
`setup.sh` symlinks this directory into `~/.claude/projects/` so those memories are captured in
your clankers-kit fork — your agent's "brain" grows and is backed up as you work. Claude writes
them in its own format automatically; there's nothing to configure here.

## Privacy

> [!WARNING]
> These memories can hold **private, work-specific context** (what you're building, internal
> names, decisions you've made). Because clankers-kit **tracks them by default**, keep your fork
> **private** — or scrub this directory before pushing to any public remote. `setup.sh` offers
> to set your repo private for exactly this reason.
