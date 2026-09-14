# Stacked PRs (`gh stack`)

Verified against `gh stack` v0.1.0.

You are here because the profile's PR shape row carries `gh stack for a multi-PR change` and this
run is a multi-PR change: Gate 1 item 3 split it into several PRs, or item 2 answered stacked. A
lone branch takes SKILL.md's plain items, because one PR is not a stack. This file replaces
SKILL.md's Step 4 items 1 (branch), 4 (push) and 5 (PR). Item 2's commits are unchanged, and so is everything before Gate 2 apart from P1, which
runs at Step 2 so Gate 2 can state the route. Under the split it also replaces
[split-path.md](split-path.md)'s per-concern forge half: branches and commits are still built once
per concern, but the stack is tracked once and submitted once, for the whole set.

- `gh stack submit` with no flag opens a full-screen editor and otherwise falls back to TTY
  detection, the same hazard as a bare `gh stack view`. `--auto` is **mandatory** here.
- `--auto` uses auto-generated PR titles and descriptions, and `submit` has **no `--title` and no
  `--body`**. What Gate 2 approved is applied afterwards, per PR, with `gh pr edit`, and nothing is
  marked ready or handed on before that pass finishes.
- `gh stack add -A` / `-u` / `-m` commits for you, as **one** commit. The atomic split is this
  skill's whole output, so those three flags never appear here.

## P1 — Pre-flight (read-only, runs at Step 2)

In this order, because the first two checks decide whether any `gh stack` command may run at all.
Nothing here mutates: a question this section asks is recorded for Gate 2, and the command it
picks runs at P2 or P3.

- **A paused cascade** — `test -e "$(git rev-parse --git-common-dir)/gh-stack-rebase-state"` ⇒
  HEAD is detached and every `gh stack` read fails with `not on any branch`. Stop, before any
  commit: report the paused cascade and say the rebase capability resolves it first. Nothing has
  been committed, so there is nothing to unwind.
- **A linked worktree** — `git rev-parse --git-common-dir` differs from `git rev-parse --git-dir`
  ⇒ `gh stack` reports the current branch "is not part of a stack" even when the metadata lists
  it, so no answer it gives here can be trusted. Take the **degraded route** without running any
  `gh stack` command, and say plainly that a stack needs the main worktree. Reading "not part of a
  stack" from a worktree and calling `init` would chain a branch that is already in a stack.
- **The version** — `gh extension list`. Anything other than v0.1.0 ⇒ say so and read
  `gh stack <cmd> --help` for every command below before the first one that mutates. The flags in
  this file are v0.1.0's.
- **The remote, `<rem>`** — a single remote, `gh-stack.remote`, or `remote.pushDefault`, asking
  when none of those settles it. `gh stack`'s auto-detection stops on a multi-remote repo
  (`multiple remotes configured; set remote.pushDefault or use an interactive terminal`), and
  `init`, `add` and `view` take no `--remote` at all — so a multi-remote repo that config does not
  settle takes the **degraded route** rather than a prompt this run cannot answer.
- **The stack** — `gh stack view --json`, the non-blocking form; the bare command opens a TUI that
  never returns. Read the actual keys: the names are `gh-stack`'s, not this skill's. Branch on the
  outcome, and note that "not part of a stack" and "belongs to multiple stacks" come back as
  errors on stderr rather than as fields:
  - **Succeeds** ⇒ a stack already tracks the current branch. Take its member order (bottom to
    top), which branch is current, and **which members already carry an open PR**. Current branch
    is the **top** member ⇒ the `add` route. Current branch is **not** the top ⇒ **ask**, because
    `gh stack add` adds to the top of the **stack**, not on top of the current branch: add above
    the top member `<name>`, saying plainly that the new branch's parent is that member and not the
    branch the user is standing on · stop, so the user can `gh stack top` or restructure with
    `gh stack modify` themselves · the degraded route. Never guess: the answer decides which
    commits the new branch sits on.
  - **Not part of a stack** ⇒ the `init` route. The worktree check above is what makes this answer
    trustworthy.
  - **Belongs to several stacks** ⇒ **ask which** (its stack number), and record it. The
    `gh stack checkout <stack-number>` that makes it active runs at the top of the route it picks,
    after Gate 2, because it **moves the worktree** and Step 0's changes are still uncommitted:
    stash first as the `add` route does. Gate 2 names that checkout, or the user takes the
    degraded route instead.
  - **Any other failure** — auth, a rate limit, `timed out waiting for stack lock`,
    `Stacked PRs are not enabled for this repository`, `unknown command "stack"` — ⇒ report it
    verbatim and take the degraded route. None of those means this branch is in no stack.
- **The mutation set** — one `gh stack submit` pushes **every** active branch in the stack and
  retargets the base of **every** PR that already exists, so the run owns more than the branches
  it creates. Record, per branch that submit will push — every branch this run creates, every
  existing member on the `add` route, and `<bottom>` on the `init` route where Gate 1 answered
  stacked — its unpushed commits (`git rev-list --count <rem>/<b>..<b>`) and whether its PR's base
  will move. Gate 2 must name that whole set, not only the new branches' own PRs, because
  approving the plan approves publishing all of it. `<bottom>` routinely carries commits of its own: Step 0's branch lead is exactly that set.

Done when the route is `init`, `add` or degraded, `<rem>` is resolved on the first two, the
existing members and the mutation set are recorded, nothing has been created, and both reach Gate
2 — or the paused-cascade stop has fired.

## P2 — The `init` route

The current branch is in no stack. `git checkout -b` and `git commit` carry an uncommitted tree
safely, while `gh stack init` is untested against a dirty tree, so every branch is cut and every
commit made with plain git first and the stack is tracked afterwards, over branches that already
exist. `init` adopts existing branches by name, which is what makes this order work.

1. One concern: `git checkout -b <name> <pr-base>`, then Step 4 item 2's commits, unchanged.
2. Several concerns, bottom to top in the order the user chose: for each,
   `git checkout -b <name_i> <pr-base_i>` — `<pr-base_1>` as Gate 1 bound it, `<pr-base_i>` =
   `<name_(i-1)>` above it — then that concern's commits, then on to the next. The remaining
   concerns ride the working tree across each checkout, as they already do on the plain split.
3. `gh stack init --base <base> [<bottom>] <name_1> [<name_2> …]`, bottom to top. `--base <base>`
   is the trunk, the profile's Default branch row, and this is the one place `<base>` belongs on
   this path. `<bottom>` is the branch the user was on, included **only** where Gate 1 item 2's
   answer was stacked: existing branches are adopted, so naming it is what makes the current branch
   the stack's bottom member and its PR the stack's first.
4. Confirm, before anything is published: `gh stack view --json` lists every branch this run
   created, in the planned order, on the planned trunk. A missing or misordered member ⇒ stop and
   report. The commits are safe on their branches and nothing is on the remote, so this is the last
   cheap bail.

Done when every planned branch exists with its planned commits, the view lists the whole intended
stack in order, and `git status --porcelain` matches what Step 0 recorded minus what was committed
— or the stop has fired.

## P3 — The `add` route

A stack already tracks the current branch, which is its top member. Nothing here calls `init`, and
the existing membership is preserved.

`gh stack add` creates the branch itself, so it runs against the live working tree: `add` documents
no way to adopt an existing branch, `init` adopts only while creating a stack, and `gh stack modify`
is a TUI this run cannot drive. That is why the stash below is unavoidable rather than merely
cautious.

Where P1 asked which of several stacks to use, this is where its answer runs: stash as step 1
below does, then `gh stack checkout <stack-number>`, then apply the stash back. Gate 2 named that
checkout, so the worktree move is one the user has already approved.

Per concern, bottom to top:

1. `git stash push --include-untracked`, then record `git rev-parse refs/stash`.
2. `gh stack add <name_i>` — never `-A`, `-u` or `-m`.
3. `git stash apply <sha>`, leaving the entry in place until the user confirms it applied. An
   uncommitted edit destroyed by a per-branch checkout exists in no stage, no ref and no reflog.
4. That concern's commits, as Step 4 item 2 makes them.

Then confirm with `gh stack view --json`, exactly as the `init` route's step 4 does.

Done when every planned branch exists with its planned commits, every stash taken has been applied
and reported, the view lists the whole stack in order, and the members that were there before are
still in it.

## P4 — Submit

```
gh stack submit --auto --remote <rem>
```

`--auto` and nothing else, whatever the PR shape row says about drafts:

- **Draft-first** ⇒ `--auto` alone is already right: it creates every new PR as a draft.
- **Not draft-first** ⇒ still `--auto` alone, and `gh pr ready <n>` per PR **this run created**
  after P5, never before it. `--open` marks new **and existing** PRs ready for review, so on a
  stack that already carried a deliberately-draft member it promotes a PR this run never touched.

One command pushes every branch, creates a PR for each branch without one, retargets the bases of
the PRs that already had one, and creates or updates the stack on GitHub. A PR that already existed
keeps its body; only its base may move.

Then map branch to PR number from `gh stack view --json`, and check every branch this run created
has one. A branch with no PR ⇒ report it as unsubmitted, and do not reach for a `gh pr create` of
your own: its base belongs to the stack now.

**A refusal is not proof that nothing happened.** `submit` pushes, creates PRs and moves bases
before it establishes the stack on GitHub, so a late failure — `Stacked PRs are not enabled for
this repository` is the one to expect — can leave branches pushed and PRs open. Reconcile before
falling back: `git fetch <rem>`, then `gh pr list --head <b> --state open --json number,baseRefName`
per branch this run created. Then create only the PRs that are missing, with the degraded route's
`gh pr create --base <pr-base>`, keep every edit P5 already applied, and say whether the local
metadata was kept or removed with `gh stack unstack --local`.

Done when the submit has run, every created branch has a PR number recorded, any branch without one
is named, and a refusal has been reconciled rather than assumed clean.

## P5 — Titles and bodies

Per PR this run created, bottom to top, with the title and description Gate 2 approved for that
concern:

```
gh pr edit <n> --title "<title>" --body-file -
```

Heredoc the body, exactly as Step 4 item 5 does. Until this runs the stack carries auto-generated
titles and bodies, so Gate 2 says in one line that the PRs hold temporary text until this pass
finishes. Nothing is marked ready and nothing is handed to the CI watch before it, because the push
hook fires on the submit and a reviewer reading first would read text the user never approved.

A PR the run did not create keeps its body: the run drafted no description for it, and a
hand-written body is the user's to keep unless Gate 2 surfaced it and the user approved the
replacement.

Done when every created PR carries its planned title and body, the PRs that kept their own body are
named, and only then any `gh pr ready` has run.

## P6 — Verify and report

- `gh stack push` is **not atomic** and `submit` publishes through the same path, so verify rather
  than trusting its exit: `git fetch <rem>`, then `git rev-parse <b>` ==
  `git rev-parse --verify --quiet <rem>/<b>` for every branch in P1's mutation set — the branches
  this run created and the existing members the submit pushed. One submit publishes the whole set,
  so an existing member left half-published fails the same way a new one does. A mismatch ⇒
  report a **partial publish**: name which branches landed and which did not, say that the
  un-landed branches' PRs now run CI against a base the remote does not have, and offer
  `gh stack push --remote <rem>` to finish.
- Report the stack bottom to top: each branch, its PR number, its draft state, its base. Say that
  the PRs are a stack on GitHub and that the review runs bottom-up.
- Then Step 4's closing line, unchanged: with a CI watcher in the profile a hook hands off to the
  CI watch, which watches every member of the stack and advances the bottom open one; with `none`,
  say plainly that no CI watch follows and the stack is the user's to advance.

Done when every branch in the mutation set is verified against its remote, the stack is reported
bottom to top, and the hand-off is named.

## The degraded route

P1 sends you here from a linked worktree, an unsettled multi-remote repo, a missing extension, or
any `gh stack view` failure that is not one of the two membership answers. P4 sends you here for
the PRs a refused submit left missing.

Run Step 4's items 1, 4 and 5 as written, with `<pr-base>` as Gate 1 bound it: the branches still
chain and each PR still opens against its parent, so the result is a correct chain of PRs that
simply is not a stack on GitHub. Say that in the report, name why, and name the one command that
would make it one once the blocker is gone — `gh stack link <pr-url> <pr-url> …`, bottom to top,
which builds the stack on GitHub from the PRs without writing local tracking state. Do not run it
here: it pushes branches and mutates PRs, and the blocker that sent you here is the reason not to.

Done when the chain exists with each PR against its parent, the report says it is not a stack and
why, and the `link` command is named rather than run.
