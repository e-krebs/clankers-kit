# Hooks

A hook is a script the agent's harness runs on an event, so a rule holds without the agent
choosing to follow it. Shared hooks live in [`.agents/hooks/`](../.agents/hooks/), and a skill's
own hooks live in `.agents/skills/<name>/hooks/`.

## Rows in the picker

The Hooks group has one row per shared fragment: enforcement, notification sounds, commit
subject gate, session cleanup, canonical memory, and the memory ask gate. It also has a
`skill trigger hooks` toggle, off by default. Turn that one on to compose the `hooks.json` of
every active skill too.

## Fragments

A fragment is plugin `hooks.json` content. It holds the usual events and matchers, but every
`command` is a bare script path with no arguments:

- `${CLAUDE_PLUGIN_ROOT}/hooks/<script>.sh` for a shared hook;
- `${CLAUDE_PLUGIN_ROOT}/skills/<name>/hooks/<script>.sh` for a skill's own.

An argument goes in the script's header instead. That header is one line, `# codex: yes`,
`# codex: no`, or `# codex: yes args=<string>`. `no` drops the hook from the Codex wiring, and
the composer appends `args` to the Codex command only.

## The composer

Every run of `setup.sh` composes both wiring files from the fragments of the checked Hooks rows:
`~/.claude/settings.json`, and `~/.codex/hooks.json` when Codex is one of your agents. The
composer runs with `--own root`. It replaces the entries it wrote, and a stale entry whose
script is gone, and it leaves every other entry alone, so a hook you added by hand survives a
re-run. For Codex, it also renames `Notification` to `PermissionRequest`, drops that matcher,
and caps a `SessionEnd` timeout at 3.

> [!WARNING]
> Codex hashes each hook definition and runs a hook only once you trust it. After `setup.sh`,
> and after any re-run that changes the wiring, open `codex` and run `/hooks` once. Until then,
> `codex exec` skips an untrusted hook silently.

## Asking from a gate

A gate cannot see what the agent asked you, so a gate that needs an ask denies once and records
it. `memory-ask-gate.sh` denies the first write that would create a memory file and lets the
retry through. `workflow-profile-nudge.sh` nudges once the same way, with its `.asked/` markers.

## Add a hook

A hook that triggers or guards one skill lives in that skill's own `hooks/` directory and
follows the `skill trigger hooks` toggle. Any other hook goes under `.agents/hooks/`. Either way
it needs a fixture case and a `kit.json` row, and
[CONTRIBUTING.md](../CONTRIBUTING.md) holds the contract.
