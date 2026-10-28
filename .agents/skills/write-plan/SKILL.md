---
name: write-plan
description: >-
  Write the plan file for a piece of work. Use when a task needs a plan, the user asks to plan it
  or make a plan, or before starting non-trivial work. Not for carrying a plan out, or for
  reviewing code.
---

# write-plan

Entry: `/write-plan <brief path | ticket key | text>`.

The running session is the one that runs the approved plan, and the plan writer the one that writes it.
Their tiers are the rows of `~/.agents/workflow-models/tiers.md` marked for running and for writing a plan.
The skill writes `<tier of the running session>` for the running session tier's name, spelled as tiers.md does.

The plan file must hold everything the builder needs, because a fresh session with no chat
context runs it. The planning session ends on approval.

## Steps

1. Ground in the workflow profile. The session-start hook injects the resolved rows as context.
   When they are in context, read the Browser check row and the other facts from there. Only when
   the rows are absent, run `bash ~/.agents/skills/workflow-profile/scripts/resolve-profile.sh --rows`.
   Always read the Verify commands from
   `bash ~/.agents/skills/workflow-profile/scripts/resolve-profile.sh --verify-commands`: the script owns
   the row grammar and prints `<dir><TAB><command>` lines, nothing for `—`. A resolver that is missing
   (exit 127) stops the plan with the reason, before the interview. On exit 1 (no profile
   resolves), ask for the facts below (Verify commands and the rest) instead of stopping. Read the input too, whether a brief path, a ticket
   key, or the request as typed. Done when Ticket system, Commit policy, CI watcher, Reviewers,
   Verify commands, Browser check and the repo facts are in hand and the input is read, or the
   plan has stopped with its reason.
2. Ticket and base. When a ticket is in play and the profile has Tracker rules, move it to the
   started state inline, unless it is there already. With a tracker, no ticket and no outcome
   from an earlier kickoff, ask once whether to create one. On a yes, create it and move it.
   When plan mode refuses a tracker write, row S0 carries the write at Tier `<tier of the running
   session>`. Otherwise S0 refreshes the base branch when the profile has a remote. Pick its tier
   from tiers.md by the shape of the work. Send a long ticket or linked spec page to a worker. It
   returns at most 15 lines: the outcome, the constraints, what stays open. Done when the ticket is
   in its started state or S0 carries the write, and the input is digested.
3. Enter plan mode. In Claude Code, load the deferred tools with
   `ToolSearch select:EnterPlanMode,ExitPlanMode`, then call `EnterPlanMode` unless the session
   is in plan mode already. Skipping `EnterPlanMode` is wrong when the harness has it.
   The no-plan-mode fallback below is the only exception. On Codex, Plan mode is the user's toggle, so
   go on. Done when the session is in plan mode, or the harness offers no tool to enter it.
4. Explore with delegated read-only workers in parallel, one per code area. Pass paths and the
   questions, and ask each to return at most ~15 lines: answers with file:line evidence, then
   what stays open. Read only the files that are the subject of the design yourself, by line
   range when you can. Ask the user only what the repo cannot settle. Probe each mechanism a row
   would rely on that neither the docs nor the repo state, with a one-command test, or ask the user
   for the one reading only they can take. Done when every file the plan touches is named, no open
   question is one the repo could have settled, and every mechanism a row relies on is documented or
   probed.
5. Interview what is left. Ask in batched rounds, through the harness's question tool when it has
   one (context and links in a message first, the question one short phrase), else as numbered
   questions, each carrying your recommended answer. Make routine choices with one clear best option
   yourself, and record each with a reason instead of asking. Done when every consequential decision
   is the user's, and every decision sits in Decisions.
6. Write the file to the harness's plans directory (`~/.claude/plans/` in Claude Code,
   `~/.codex/plans/` on Codex, which keeps no plans folder of its own), or the path the user named,
   following [references/plan-template.md](references/plan-template.md), loaded now. Codex Plan mode
   forbids writes, so there name the path `~/.codex/plans/<slug>.md` with `~` expanded and do not
   create the file. A hook saves the approved plan there. Delegate every row unless the
   running-session test holds: an external write, a subagent fan-out or a user errand. Pick each
   row's tier from the shape of its work in `~/.agents/workflow-models/tiers.md`. Go down a tier
   when the brief is mechanical (a command, or exact edits that leave no decision). Go up when the
   work is interlinked or delicate. Give every delegated row a brief file, `<plan stem>.briefs/S<n>.md`,
   written with the plan, whose first line gives the reason for its tier.
   Give S0 and Gates a brief too. When two or more briefs would repeat the same steps, rules or test
   list, write it once as a markdown attachment, link it from each brief, and keep in each brief only
   what differs. Done when the six headings hold
   content, every row has a Tier and a Done when that is one backticked command with no `|` (the row parser splits cells on it; a pipeline goes in a script file the command runs) (Approval and Hand-off excepted), and every delegated row has a brief file.
7. Fill Run. The tier of the running session is fixed, so the plan never picks another tier for
   the session. Read the model and effort for that tier from `<provider>.md` in
   `~/.agents/workflow-models/`, for the provider running the session. In Claude Code the fence is
   the one line `claude --agent <tier of the running session> "/execute-plan <path>"`, and
   that tier's agent file carries the model and effort. On Codex the fence is one launch line,
   `codex -m <model> -c model_reasoning_effort=<effort> "Execute the plan at <path>"`, with the
   values from `codex.md`. When the folder is missing, name the tier, say the files were absent,
   and fill the model and effort with the session's current ones. The last line of Run names
   `references/run-rules.md` in the execute-plan skill folder by its absolute path. The plan copies
   none of the rules. When execute-plan is not installed the Run line still names the path, and the
   running session stops and reports the missing file. Done when Run names the tier and a reason, the fence holds the plan's absolute
   path, the run-rules line is there, and no placeholder is left.
8. Write the closing rows: Review, Gates, Approval and Hand-off. List the review skills this
   session can reach, personal and repo-shipped. The Review row names the review skill and
   `<tier> tier × <count>`. Pick the tier from tiers.md by the shape of the review work and write
   it by name. The Size rule gives the count. The Gates row's Done when is the profile's Verify
   commands, as printed by the resolver in step 1, never a shorter hand-picked list. The Gates brief tells the
   worker to read the profile's Browser check row (from context or via the resolver) and run its
   steps when the row is not `—`. Its form and brief follow
   the Gates block in [references/plan-template.md](references/plan-template.md). Write
   `gates.sh` here, with the row, because `bash "<path>"` fails when it is missing. On Codex Plan
   mode the template adds a build row for it before Review.
   Done when the four rows close Steps in that order, any gates script exists or a build row
   creates it, and no row commits or pushes.
9. Build the attachments by the rules in
   [references/html-rendering.md](references/html-rendering.md), loaded when the plan needs an
   attachment or has an audience beyond the user and the agent. A worker builds each HTML attachment. Pick its tier from tiers.md for
   a self-contained build, and ask it to return the path and one line, no file body. Offer the shareable copy when one of its criteria holds. Done when the offer
   was made or no criterion held, and each linked attachment exists or has a build row before
   every row that reads it. On Codex Plan mode, every attachment gets a build row.
10. Review the plan itself before leaving plan mode. Take the reviewers from the profile's
   Reviewers row, at the Size rule's plan-reviewer count. The first pick is the first entry from
   a provider other than the session's (codex in Claude Code, claude in Codex), and the rest
   follow in row order. With no other provider installed, take the row's first entry. Reviewers
   are read-only and share the tree. A claude reviewer is a subagent. A codex reviewer is
   `codex exec --sandbox read-only`. Pick either tier from `~/.agents/workflow-models/tiers.md`
   by the shape of the work, and read a codex reviewer's model and effort from that tier's row of
   `codex.md`. On Codex Plan mode, pass the plan text in each reviewer's prompt. A re-review after
   an edit uses the same count. At count 0, the running session re-reads the plan once instead,
   and Plan review names its own model. Each reviewer returns at most 15 lines of
   `severity · section · issue · fix` findings and nothing else. Reviewers also read every
   markdown attachment the plan links. Fold in the findings you accept. Done when Plan review
   names every agent that reviewed and states what changed.
11. Ask for approval. In Claude Code, call `ExitPlanMode` with the plan markdown as the approval
    text, quoting the saved path. Write no chat text in that message: the VSCode extension shows
    none of it and the transcript keeps none of it, so a print there reaches nobody. On Codex in
    Plan mode, present the whole plan, six headings included, in the harness's proposed-plan
    block, with the Run fence inside it naming the absolute plan path, never "the plan above".
    The harness's "Implement this plan?" choice is the approval. In a harness with no plan
    mode, present the saved path and ask for approval.
12. Reply with the Run block on approval. In Claude Code, plan-followthrough hands the block back
    as context, and plan-approved-guard denies every tool until the turn ends. It also blocks a
    stop whose reply lacks the launch line. So the reply is the block verbatim, the fence kept, then
    the turn ends. The block also holds the `/model`, `/effort` and `/execute-plan <path>` lines of the tier, in a code
    fence, for the VS Code extension, which has no `--agent` flag. Without the hooks, do the same by hand:
    print the Run fence, the line "In the VS Code extension, start a new session and type:" and those three lines in a code fence (the first two from `claude.md`), run no step. A fresh session runs the plan. Done
    when the plan is approved, the block is the last reply, and no step ran.

## Size rule

| Size | Test | Plan reviewers | Review row |
| --- | --- | --- | --- |
| small | the Files column lists at most 3 files, the recommended commit split is one commit, and no file is a hook, a skill or a config | 0 | 1 |
| medium | anything larger that stays simple | 1 | 1 |
| large or risky | broad, coupled, or a mistake is expensive | 2 | 2 |

A small plan still writes all six headings. Size changes the review counts only. When fewer
reviewers are installed than the count, every installed one runs.

## Gotchas

- A hook parses the `## ` lines outside fences, so the six headings, spelled exactly and in
  order, are the contract.
- A tracker write needs an existing ticket or the user's yes. A ticket created without the yes
  is a mutation the user never approved.
- An edit to scope, rows, a brief file or a Done when after the review counts as a new plan. Re-run
  the plan review and update Plan review. Folding in review findings, filling Plan review and
  building an attachment of unchanged content do not count.
- The markdown is the plan. An attachment is never the source of a row, the Run fence or a
  brief, because the hooks and the running session read only the markdown.
