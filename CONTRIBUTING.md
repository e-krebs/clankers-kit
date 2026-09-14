# Contributing to clankers-kit

Thanks for wanting to help. clankers-kit is a **starter people fork and own**, so the bar for
what ships here is "would this help a stranger, out of the box, without leaking my life into
it?" A few kinds of contribution are especially welcome:

## Ports to other agents

The kit wires **Claude Code** and **Codex** (`~/.claude`, `~/.codex`, and the shared `~/.agents`),
but the ideas are agent-agnostic. If you've translated a hook, the `AGENTS.md` shape, the memory
setup, or a skill to another coding agent (Cursor, Windsurf, Aider, Gemini CLI, …), open a PR.
An agent that reads `~/.agents` already gets the skills and the workflow profiles; the
instructions file and the hook wiring are per-agent links, so a new agent needs an `agent` on
the link rows of `kit.json`, a branch in `setup.sh`'s agent detection, and its own composer
output when it runs hooks. Keep ports clearly separated so each tool's setup stays turnkey.

## Adding a skill

Skills are held to a **"refined enough to represent you publicly"** bar — generic, self-contained,
and genuinely useful, not tuned to one company's stack.

1. Add `.agents/skills/<name>/SKILL.md` (plus any scripts it needs, and an optional `hooks/` dir:
   a script with a `# codex:` header, its `hooks.json` fragment whose commands read
   `${CLAUDE_PLUGIN_ROOT}/skills/<name>/hooks/<script>.sh`, and a `fixtures/<name>/run.sh`
   suite that `bash .agents/hooks/run-fixtures.sh` picks up).
2. Make it **portable**: no employer/project names, no hard-coded personal paths, no assumptions
   about a specific issue tracker or repo layout. Where an integration is unavoidable, make it
   opt-in and document it.
3. Add a `skill` row to `kit.json`: `requires` for a sibling the skill cannot run without,
   `soft` for one it only reads when present, `agents` when it is Claude- or Codex-only. Run
   `bash .agents/lint-manifest.sh`, then add the row to the catalog in
   `.agents/skills/README.md`.
4. Note in the PR how you verified it runs standalone.

A skill that reads the workflow profile must still run, and say so, when no profile resolves;
a skill with a `soft` edge must say so when the sibling is absent.

## Presets and hooks

- **Setting presets** live in `.claude/settings/<preset>.json`, allowlist-style, and are applied
  additively by `.claude/settings/merge.jq` (arrays union, a scalar is set only when absent,
  nothing removed). Add a fragment + a `settings` row in `kit.json`.
- **Hooks** are a script under `.agents/hooks/` with a `# codex: yes|no|yes args=<string>`
  header, its `hooks.json` fragment (every command a bare
  `${CLAUDE_PLUGIN_ROOT}/hooks/<script>.sh`, no arguments), a `fixtures/<name>/run.sh` suite,
  and a `hooks` row in `kit.json`. A hook that triggers or guards one skill lives in that
  skill's `hooks/` dir instead and rides the `skill trigger hooks` toggle. Keep every hook
  **fail-open** (a hook error must never block the user) and cross-platform where practical
  (see `play-sound.sh` for the pattern). Run the whole fixture suite with
  `bash .agents/hooks/run-fixtures.sh`. Don't hand-edit the composed hook entries in
  `.claude/settings.json` or `.codex/user-hooks.json`: `setup.sh` rewrites them from the
  fragments on every run (a hook you add yourself is left alone). Change the fragment instead.

## Manifest

A new preset, skill, hook, or link needs a row in `kit.json`: `id`, `group`, `kind`, `label`,
a `description` (a skill row takes it from its SKILL.md), `default` when it starts off,
`requires` (hard edges, checked as a closure), `soft` (advisory, shown in the picker), `agents`
and `needs` when it applies only to some agents or tools. Run `bash .agents/lint-manifest.sh`
and make sure it passes; CI runs it too.

## Ground rules

- **No personal data.** No real names (other than authorship), emails, employer/project names,
  ticket IDs, internal URLs, or machine-specific absolute paths.
- **Keep it terse.** `AGENTS.md` content is re-read every turn; every line should earn its place.
- **`shellcheck` must pass** on every shell script in the repo. Run it locally:
  `shellcheck $(git ls-files '*.sh')`. CI runs an older shellcheck than Homebrew ships, so a
  clean local run can still fail there on `A && B || C` (SC2015); write the `if` instead.
- **A hook change comes with a fixture case.** Run the whole suite with
  `bash .agents/hooks/run-fixtures.sh`; CI runs it too.
- **A `setup.sh` change comes with a smoke case** in `.github/smoke.sh`, which CI runs on
  ubuntu and macOS against a throwaway `HOME`. Run it locally with `bash .github/smoke.sh`.
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
paths appear in the recording, and passes `--agents claude,codex` so the agents question never
shows. The tools on the recording machine still decide which rows and prompts appear, so the
tape requires `claude`, `npx`, `gh`, `jq` and `git` on `PATH` and stops when one is missing. Its
key presses follow the prompt sequence: the grouped picker, the `AGENTS.md` questions, the recap.
Regenerate it if you change that flow or the picker's rows.
