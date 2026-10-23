# Plan: add a `--quiet` flag to the fixture script

Source: request in one line, to add a quiet flag to the execute-plan eval fixture script. The user decided the scope.
Ticket: none, fixture plan for the execute-plan evals.
Repo: /path/to/repo.
Size: small.

## Summary

The execute-plan evals need a plan to run. This fixture plan adds a `quiet-flag.sh` script that prints `progress` by default and prints nothing under `--quiet`. Three routine rows build it, and a final check confirms the default output. The plan has no review or hand-off rows, because it exists only to exercise the run rules.

## Decisions

- The script prints one fixed word, so the rows test the flag and nothing else (agent)

<details><summary>Your decisions (0)</summary>

</details>

## Steps

| State | # | Task | Tier | After | Done when | Files |
| --- | --- | --- | --- | --- | --- | --- |
| ➖ | S1 | Create `quiet-flag.sh`, which prints `progress` unless `--quiet` is passed | routine | — | `bash -n .agents/skills/execute-plan/evals/fixtures/quiet-flag.sh` | `.agents/skills/execute-plan/evals/fixtures/quiet-flag.sh` |
| ➖ | S2 | Print nothing under `--quiet` | focused | S1 | `test -z "$(bash .agents/skills/execute-plan/evals/fixtures/quiet-flag.sh --quiet)"` | `.agents/skills/execute-plan/evals/fixtures/quiet-flag.sh` |
| ➖ | S3 | Gates: the default run prints `progress` | routine | S2 | `test "$(bash .agents/skills/execute-plan/evals/fixtures/quiet-flag.sh)" = progress` | — |

## Run

The run tier of this fixture, on model claude-opus-4-7 at high effort.
In a new terminal:

```
claude --model claude-opus-4-7 --effort high "Execute the plan at ~/.agents/skills/execute-plan/evals/fixtures/quiet-flag.md"
```

Run rules: `~/.agents/skills/execute-plan/references/run-rules.md`. The running session reads that file before the first row.

## Plan review

None. This fixture plan has not been reviewed by an agent.

## Briefs

Briefs: ~/.agents/skills/execute-plan/evals/fixtures/quiet-flag.briefs/, one file S<n>.md per delegated row.
