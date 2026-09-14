---
name: changes-to-pr
description: Turn working-tree changes into a branch, atomic commits, and a draft PR, optionally an agent review first, and moving the linked issue to In Progress. Use when packaging uncommitted work into a reviewable draft PR ("open a PR", "cut a PR", "ship this"). Not for watching CI or merging.
---

# changes-to-pr

Transform the working tree into a branch + atomic commits + a draft PR with a ready
description — optionally running an **agent review** first, and offering to move the linked
issue to **In Progress**. On the GitHub side this skill's actions end at the **draft PR** — it
never promotes to ready, requests review, or merges; anything beyond the draft (CI watching,
promotion, review) is out of scope.

## Safety

- Nothing is committed, pushed, or sent to GitHub until the user approves the **Gate 2**
  consolidated plan. Pushing and PR creation are outward-facing — only proceed past Gate 2.
- Respect `.gitignore`. Never commit secrets, tokens, internal URLs, or credentials —
  surface anything suspicious in the Gate 2 plan.
- Reading the linked issue's status (Step 2) is read-only. Moving it to In Progress is
  outward-facing: it runs only after Gate 2 approval, **first** in Step 4 (before the git/PR
  steps). The move is a safety catch-up — "In Progress" reflects that the work has started, so it
  covers an issue that wasn't already moved; it shouldn't wait on push/PR success. Best-effort — a
  tracker error never blocks the commits/PR, and the move is silently skipped when none applies.
- The agent review (when run in Step 2) auto-applies only **high-confidence** fixes to the working
  tree; reported (uncertain) findings are summarized, not applied. Those fixes land in the Gate 2
  diff like any other change — nothing is committed or pushed before Gate 2.

## Step 0 — Inspect (no questions yet)

Run in parallel:

- Current branch: `git branch --show-current`.
- Base branch: `git symbolic-ref --quiet refs/remotes/origin/HEAD` → strip to leaf
  (e.g. `main`); fall back to `main` if unset.
- Changes: `git status --porcelain` → staged + unstaged + untracked (minus `.gitignore`).
- Full diff being committed: `git diff <base>` for tracked changes + the contents of
  untracked files. (Before any commits exist this is what `<base>...HEAD` will show after.)
- Branch lead: `git log --oneline <base>..HEAD` — commits unique to the current branch.

From the diff, analyze:

- **Concerns**: does the change span more than one distinct, separable concern?
- **Env vars**: new `process.env.*`, `import.meta.env.*`, `ENV["…"]`, `ENV.fetch(…)`, `.env*`.
- **Dependencies**: `package.json` / `Gemfile` dependency changes.

**Abort gracefully** if: working tree is clean (nothing to commit), or HEAD is detached.

## Step 1 — Gate 1 (single `AskUserQuestion` batch)

Ask only what's needed, batched into one call:

1. **Linked issue** (optional). Auto-detect an issue reference (e.g. `PROJ-123` or `#123`) in
   the branch name / `<base>..HEAD` commits; if found, ask to confirm. Otherwise offer:
   provide a reference · **draft a linked-issue description for me** · **"none"**. A confirmed
   reference gets appended to the PR description's "why" section at Gate 2 for autolinking.
   - If **draft a linked-issue description** is chosen: from the Step 0 analysis, draft a
     linked-issue description (title + body) and show it for confirm/edit. **Once that
     description is confirmed**, the user creates the issue in their tracker from the draft and
     pastes the resulting key back (or proceeds with "none"). Continue to Step 2 with the
     reference in hand — Gate 2's PR description will already carry it.
2. **If not on the base branch** — where should commits land?
   - Current branch
   - New branch based on current branch (stacked)
   - New branch based on `<base>` (independent) — **omit this option** if the working-tree
     changes clearly depend on commits unique to the current branch (`<base>..HEAD`)
     (i.e. they modify or reference code those commits introduced), since branching off
     base would drop those dependencies.
3. **If multiple concerns detected** — proceed as **one PR**, or **split** into one
   branch + commits + draft PR per concern? (Warn with the detected concerns.)
4. **Agent review** — only when **no** review summary is already in context (a plan-driven review
   usually ran just before this skill). Offer to run one first:
   `Run an independent agent review before the PR? [Yes / Skip]`.

## Step 2 — Build the plan

- **Agent review** (only if the user chose Yes at Step 1): run it in a **subagent**, not the main
  (implementing) agent — an independent review, not self-review. The subagent reviews the
  working-tree diff with whatever review capability best fits the change, at a suitable depth,
  applies **high-confidence** fixes, and returns the summary (coverage + findings + verdict + what
  it fixed) for the PR section. Auto-fixes change the diff,
  so re-read Step 0's `git diff` before the rest of Step 2 (commit split + PR description).
  (Plan-driven path: the review already ran before this skill — use that in-context summary,
  don't re-run.)
- **Branch name** (if creating): `type/desc` — `type` from the primary concern
  (`feat`/`fix`/`chore`/…), `desc` a short kebab summary. **No issue reference** in the name.
  Append `-2`, `-3`… if the name is taken.
- **Commit split**: group by concern at **file granularity**. Each commit message is
  conventional with scope: `type(scope): subject` — **no issue reference**. Pick the scope from
  the change's feature/area (e.g. `api`, `auth`, `ui`). Only drop to
  hunk-level (a file split across commits) when a single tracked file genuinely mixes
  concerns; new/untracked files go whole into one commit.
- **PR title**: the primary concern's `type(scope): subject` — **no issue reference**.
- **PR description**: read the repo's PR template at runtime
  (`.github/pull_request_template.md`, or the repo's configured location) and use **its**
  sections + inline hints as the structure. Draft from the full diff being committed,
  applying these repo-agnostic principles:
  - Be concise — a sentence or short bullets per section; describe key choices, not a code
    walkthrough.
  - Fill conditional sections (e.g. environment variables, dependencies) **only** when
    Step 0 detected them.
  - Append the linked-issue reference to the motivation/"why" section **only** (GitHub and most
    trackers autolink it); omit if the issue is "none".
  - Keep sections the template marks as always-present (e.g. screenshots/previews); omit
    other sections that have no content.
  - Honor any PR-description conventions already in context (the repo's CLAUDE.md, your
    memory) — e.g. what belongs in a Testing/QA section.
  - **Agent review section** — when a review ran (just now, or earlier this session), add a short
    "Agent review" section: what was **looked at / not assessed** (coverage), a summary of the
    findings + an overall **verdict**, and a one-line "N high-confidence issues auto-fixed" note.
    Omit it entirely when no review ran. On an existing PR, **replace** a prior "Agent review"
    section rather than stacking.
- **Issue move** (skip entirely if the issue is "none"): if an issue is linked and a tracker is
  available, read its current status and available transitions, and pick the transition whose
  **target status** (case-insensitive) is **In Progress** — match the target status, not the
  transition's display name (e.g. a transition called "Start Progress" lands on "In Progress").
  Outcomes to carry into Gate 2: a matched transition · the candidate list (when transitions exist
  but none target In Progress, for a picker) · nothing-applicable (already In Progress, or the
  tracker is unreachable — skip silently).

## Step 3 — Gate 2 (consolidated review)

Show one plan: **branch name + commit split (messages + files) + full PR description.**
Self-check before showing: no leftover template placeholder text remains, and the
template's primary "what" and "why" sections (whatever the repo names them) are filled. If updating an existing PR whose body is **non-template**, warn it will be
replaced and let the user keep it. User approves or edits. Nothing runs until approval.

When an **issue move** is applicable (from Step 2), ask it as a **dedicated question batched into
this same interaction** (not a separate prompt): `Move <ISSUE> (<current> → In Progress)?
[Yes / Skip]` — Yes recommended — or, when no transition targets In Progress, a picker of the
available transitions plus **Skip**. If no move is applicable (no issue / already In Progress /
no transition / tracker unreachable), ask nothing.

## Step 4 — Execute (after approval)

**Issue move first** (only if the user chose Yes at Gate 2): transition the linked issue to
In Progress via the resolved transition, then report it. Do this **before** the git steps —
"In Progress" reflects that the work has started, so this is a safety catch-up for an issue that
wasn't already moved; it shouldn't wait on (or be blocked by) push/PR success. Best-effort: on
error, report and carry on with the commits/PR.

1. **Branch**: if creating, `git checkout -b <name> <base-or-current>` (carries the working
   tree over). On the base branch with no choice asked, create off `<base>`.
2. **Commits**: `git reset` to unstage all, then per planned commit:
   - file-level: `git add <files>`
   - hunk-level: `git apply --cached` with a generated patch
   - `git commit -m "<message>"`
   - On a `git apply --cached` failure: **abort cleanly**, leave the working tree intact,
     report which commit failed. Do not push a partial result.
3. **Push**: `git push -u origin <branch>`.
4. **PR**:
   - new branch / no existing PR: `gh pr create --draft --base <base> --title "<title>"
--body-file -` (heredoc the body).
   - existing PR: push commits; update body with `gh pr edit <n> --body-file -` (only if the
     user approved replacing it at Gate 2 — otherwise leave untouched).

## Split path (if the user chose to split at Gate 1)

Run Steps 2–4 once **per concern**: each gets its own branch off the chosen base
(independent off `<base>`, or stacked on the previous concern's branch per the Gate-1
base choice), its own atomic commits, its own description, and its own draft PR.
Present all per-concern plans together at a single Gate 2. The issue move runs **once** for the
linked issue (up front, before the first concern's commits), not per concern — Gate 1 collects a
single issue.

## Gotchas

- **Clean tree or detached HEAD → abort.** Nothing to package if the working tree is clean, and
  a detached HEAD has no branch to commit onto — stop with a clear message rather than guessing.
- Never clobber a **hand-written PR body** — when updating an existing PR whose body isn't from
  the template, warn and let the user keep it rather than overwriting silently.
- **A failed `git apply --cached` aborts the whole run.** Leave the working tree intact and
  report which commit's patch failed; never push a partial split.
- Auto-fixes from the review **change the diff** — they land in the Gate 2 diff like any other
  edit, so re-read it before computing the commit split and PR description.
- The **draft PR is the end of scope** — this skill never promotes to ready, re-requests review,
  watches CI, or merges. Hand that off to a follow-up step.
