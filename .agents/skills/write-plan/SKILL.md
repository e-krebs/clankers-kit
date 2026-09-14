---
name: write-plan
description: >-
  Write the plan file for a piece of work: explore, interview, pick the model, run the plan
  review, then leave plan mode. Use when a task needs a plan, or before starting non-trivial
  work. Not for carrying a plan out, or for reviewing code.
---

# write-plan

Entry: `/write-plan <brief path | ticket key | text>`.

The plan file is the contract between the interview and the build: it survives a fresh session,
a model switch and a cleared context, so everything the builder needs lives in the file rather
than in the transcript. This skill owns writing it. Enter plan mode first when the session is
not in it already.

## Steps

1. Ground in the workflow profile. The session-start hook injects the resolved rows as context;
   when context carries none, run
   `bash ~/.agents/skills/workflow-profile/scripts/resolve-profile.sh --rows` and read its
   table. The input is read here too — a brief path, a ticket key, or the request as typed.
   Done when Ticket system, Commit policy, CI watcher, Reviewers and the repo facts are in hand
   and the input is read.
2. Explore with delegated read-only workers, one per question, in parallel. The codebase
   answers a question before the user does: every fact an agent can read is a fact you never
   ask about. Done when every file the approach touches is named, and no open question is one
   the repo could have settled.
3. Interview what is left. Ask in batched rounds — the harness's question tool when it has
   one, else numbered questions in prose — each question carrying your recommended answer.
   Done when every decision in the plan is the user's, each one recorded for the Decisions
   section, and nothing is silently assumed.
4. Write the file to the plans directory the harness uses (`~/.claude/plans/` in Claude Code),
   or the path the user named, following
   [references/plan-template.md](references/plan-template.md), loaded now: ten `## ` headings
   in that order. The plan names the skills it uses by name, in every section: it runs on this
   machine, in this session or a sibling one. Done when all ten headings hold content, `n/a`
   appearing under Ticket, Deferred kickoff actions and Verification only.
5. Pick the model from [references/model-tiers.md](references/model-tiers.md), loaded now.
   Done when Model pick names a tier, one model from that table for the provider running the
   session, a one-line rationale and the exact switch command, with no placeholder left.
6. List the review skills this session can reach — the personal ones and any the repo ships —
   and name in Closing steps which one reviews what. Done when Closing steps pairs each
   reviewer with its target, at judgment tier, in the count the size rule prescribes.
7. Run that review on the plan itself before leaving plan mode: dispatch judgment-tier
   reviewers, read-only, sharing the tree, and fold in the findings you accept. Done when Plan
   review names every agent that reviewed and states what changed.
8. Weigh the HTML rendering against the three criteria in
   [references/html-rendering.md](references/html-rendering.md), loaded when the plan has an
   audience, carries figures or diffs, or the user said "plan doc". Offer it when one holds.
   On a yes, the HTML becomes the plan: render it from the scaffold and shrink the markdown
   file to the stub the reference describes. Done when the offer was made, or no criterion
   held.
9. Call `ExitPlanMode` with the plan markdown as the approval text — the gate parses that text
   first, follows a `Source:` pointer to the HTML, and falls back to the file — quoting the
   saved path. When the plan asks for a model switch or a cleared context, state the exact
   command on one line afterwards and hold: no step runs before the user says they ran it.
   Done when the plan is approved and, where one was asked for, the command is confirmed.

## Size rule

Objective, so no run talks itself out of the flow:

| Size | Test | Reviewers |
| --- | --- | --- |
| small | Approach + Files lists at most 3 files, the recommended commit split is one commit, and no file is a hook, a skill or a config | 1 |
| medium | anything larger that stays routine | 2 |
| large or risky | broad, coupled, or a mistake is expensive | every agent in the profile's Reviewers row |

A small plan still writes all ten headings. Size moves the review line, nothing else. With one
review agent installed, every size gets that one.

## Gotchas

- A hook parses the plan's `## ` lines, so the template's headings and their order are the
  contract. With an HTML plan it parses the `<h2>` texts instead, so those stay identical.
- Deferred kickoff actions fire on approval, not while writing: a ticket created during the
  interview is a mutation the user never approved.
- An edited plan is a new plan: after any edit past the review, re-run the plan review for
  consistency and update Plan review.
