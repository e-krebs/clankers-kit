# Setup

`./setup.sh` composes three homes from this repo, and it asks before it turns on any row.

## Requirements

- macOS or Linux. WSL is fine. Native Windows is not supported, because the kit is bash and
  POSIX symlinks.
- Required: `bash`, `git` and [`jq`](https://jqlang.github.io/jq/). `setup.sh` checks for these
  and stops if one is missing.
- Recommended. Each one unlocks a feature, and `setup.sh` offers to install a missing one with
  `brew`, `apt`, `dnf` or `pacman`, or links you to the download.
  - [`claude`](https://docs.anthropic.com/en/docs/claude-code), the Claude Code CLI you are
    configuring.
  - [`gh`](https://cli.github.com/), which lets setup offer to keep your fork private.
  - [Node.js](https://nodejs.org/) for `npx`, which installs the chrome-devtools MCP preset and
    the upstream skill row.
- Optional: [`codex`](https://github.com/openai/codex), the Codex CLI. When `codex` is on your
  `PATH`, or you pass `--agents codex`, setup wires `~/.codex` too. A first run without it
  writes nothing for Codex. A fork that once wired Codex keeps that wiring in sync on every
  re-run.

## The run

`setup.sh` detects the agents on your `PATH`, Claude Code and Codex, and asks only when it finds
none. It then shows one grouped picker: layout, instructions, output style, settings presets,
workflow skills, review skills, other skills, and hooks. The skill trigger hooks stay off by
default, and every other row is on, so uncheck what you do not want. The detail pane describes
the row under the cursor and names the rows it works better with. Unchecking a row that another
checked row needs re-checks it, with a note naming the dependant, and checking a row checks
everything it needs.

Next come a few short `AGENTS.md` questions about your name, your role, and how you work. If the
`claude` CLI is installed, setup instead offers to let Claude interview you and draft the whole
file at the very end.

Then it shows a recap of what it will do, including any existing `~/.claude` content it will
merge, and it waits for one confirmation before it touches anything. It will:

- write your `AGENTS.md` from the template, or adopt the `CLAUDE.md` or `AGENTS.md` you already
  have;
- symlink settings, `AGENTS.md`, hooks, memories and workflow profiles into `~/.claude`,
  `~/.agents` and `~/.codex` as each row needs. Setup adopts an existing file and never
  overwrites it, so your current config survives;
- symlink each activated skill into both `~/.claude/skills/` and `~/.agents/skills/`, and
  compose the hook wiring for each agent you run;
- offer to make your repo private.

`./setup.sh --sandbox` runs the whole thing against a throwaway `HOME` and a copy of the repo,
so setup never touches your real `~/.claude`. It prints where to inspect the result, and how to
delete it, when it finishes. Sandbox mode skips the Claude interview, because a throwaway `HOME`
is not logged in.

Re-run `./setup.sh` any time. It leaves a linked path alone, seeds the picker from what is on
disk, and lets you activate more rows.

## Flags

`./setup.sh --help` lists the flags for a scripted run: `--agents`, `--without <rows>`,
`--components <rows>`, `--skills`, `--presets`, `--name`, `--role`, `--no-private`, `--yes` and
`--sandbox`.

## Layout

- `~/.claude` holds the Claude-only config: `settings.json` and the project memories.
- `~/.agents` holds what the agents share: the skills and the workflow profiles.
- `~/.codex` holds the Codex-only config: the hook wiring and the `AGENTS.md` link.

One source file, `.agents/AGENTS.md` in the repo, is linked per agent, as `~/.claude/CLAUDE.md`
and `~/.codex/AGENTS.md`.

A codex-only run still wires `~/.claude`, because every composed hook path resolves through
`~/.claude/hooks`. The manifest decides which rows go where. A row with `agents` applies only
when you run that agent, and a link row names the agent its link belongs to.

## Keeping your fork current

Your fork is a normal git repo. Commit `.agents/AGENTS.md`, `.claude/settings.json`, your hooks,
your workflow profiles and your memories as they change. Pull from upstream when you want new
rows. Your personal files stay yours, because `setup.sh` never overwrites an existing
`AGENTS.md` or `settings.json`, and a preset only adds to them.

Pulling upstream and re-running `./setup.sh` also migrates an older fork's `.claude/` layout, a
`CLAUDE.md`, `hooks/` and `skills/`, into `.agents/` in place. The migration is idempotent, safe
to run twice. It backs up a colliding `hooks/` or `skills/` file as `<name>.clankers-bak`, and
it leaves a `CLAUDE.md` that differs from an existing `AGENTS.md` for you to merge by hand.

## Uninstall

`./uninstall.sh` replaces every symlink in `~/.claude`, `~/.agents` and `~/.codex` that points
into this repo with a real copy of its content, and it deactivates the skills you activated from
the catalog, so your three homes keep working on their own. It loses no content, and it leaves
the repo copy intact, so delete that separately when you are done with it. It does not touch
your own files, a foreign symlink, or your GitHub repo's visibility, and it offers to remove the
chrome-devtools MCP if setup added it.
