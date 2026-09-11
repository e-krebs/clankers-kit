# Contributing to clankers-kit

Thanks for wanting to help. clankers-kit is a **starter people fork and own**, so the bar for
what ships here is "would this help a stranger, out of the box, without leaking my life into
it?" A few kinds of contribution are especially welcome:

## Ports to other agents

The examples target **Claude Code**, but the ideas are agent-agnostic. If you've translated a
hook, the `CLAUDE.md` shape, the memory setup, or a skill to another coding agent (Cursor,
Windsurf, Aider, Gemini CLI, …), open a PR. Keep ports clearly separated (e.g. a sibling
directory or a documented section) so each tool's setup stays turnkey.

## Adding a skill

Skills are held to a **"refined enough to represent you publicly"** bar — generic, self-contained,
and genuinely useful, not tuned to one company's stack.

1. Add `.agents/skills/<name>/SKILL.md` (plus any scripts it needs, and an optional `hooks/` dir:
   a script with a `# codex:` header, its `hooks.json` fragment, and a `fixtures/<name>/run.sh`
   suite).
2. Make it **portable**: no employer/project names, no hard-coded personal paths, no assumptions
   about a specific issue tracker or repo layout. Where an integration is unavoidable, make it
   opt-in and document it. Add a `skill` row to `kit.json` with its `requires` edges.
3. Note in the PR how you verified it runs standalone.

A skill that reads the workflow profile must still run, and say so, when no profile resolves.

## Presets and hooks

- **Setting presets** live in `.claude/settings/<preset>.json`, allowlist-style, and are applied
  additively by `.claude/settings/merge.jq` (arrays union, a scalar is set only when absent,
  nothing removed). Add a fragment + a `settings` row in `kit.json`.
- **Hooks** are a script under `.agents/hooks/` with a `# codex: yes|no` header, its
  `hooks.json` fragment, a `fixtures/<name>/run.sh` suite, and a `hooks` row in `kit.json`. Keep
  every hook **fail-open** (a hook error must never block the user) and cross-platform where
  practical (see `play-sound.sh` for the pattern). Run the whole fixture suite with
  `bash .agents/hooks/run-fixtures.sh`.

## Manifest

A new preset, skill, or link needs a row in `kit.json` (id, group, kind, label, defaults,
`requires`). Run `bash .agents/lint-manifest.sh` and make sure it passes.

## Ground rules

- **No personal data.** No real names (other than authorship), emails, employer/project names,
  ticket IDs, internal URLs, or machine-specific absolute paths.
- **Keep it terse.** `CLAUDE.md` content is re-read every turn; every line should earn its place.
- **`shellcheck` must pass** on every shell script in the repo. Run it locally:
  `shellcheck $(git ls-files '*.sh')`.
- **A hook change comes with a fixture case.** Run the whole suite with
  `bash .agents/hooks/run-fixtures.sh`; CI runs it too.
- **Test `setup.sh` in a sandbox**, never against your real `~/.claude` — the built-in flag does
  it for you (copies the repo + points `HOME` at throwaway dirs):
  ```bash
  ./setup.sh --sandbox --yes --name Test --role Tester --agents claude,codex
  ```

## Regenerating the demo GIF

`assets/setup-demo.gif` is produced from `demo/demo.tape` with
[vhs](https://github.com/charmbracelet/vhs):

```bash
vhs demo/demo.tape   # writes assets/setup-demo.gif
```

The tape runs `setup.sh` against a throwaway `HOME` with a sanitized prompt, so no personal
paths appear in the recording. Regenerate it if you change the setup flow.
