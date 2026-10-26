# Stacked PRs (`gh stack`)

Verified against `gh stack` v0.1.0.

You are here because the profile's PR shape row carries `gh stack for a multi-PR change` and this
run is a multi-PR change: Gate 1 item 3 split it into several PRs, or item 2 answered stacked. A
lone branch takes SKILL.md's plain items, because one PR is not a stack. P1 runs at Step 2 so
Gate 2 can state the route. P2 onwards replaces Step 4's items 1, 4 and 5, as SKILL.md says.
Under the split it also replaces [split-path.md](split-path.md)'s per-concern forge half. Branches
and commits are still built once per concern, but the stack is tracked once and submitted once.

- `gh stack submit` with no flag opens a full-screen editor and otherwise falls back to TTY
  detection, the same hazard as a bare `gh stack view`. `--auto` is mandatory here.
- `--auto` uses auto-generated PR titles and descriptions, and `submit` has no `--title` and no
  `--body`. What Gate 2 approved is applied afterwards, per PR, with `gh pr edit`, and nothing is
  marked ready or handed on before that pass finishes.
- `gh stack add -A` / `-u` / `-m` commits for you, as one commit. The atomic split is this
  skill's whole output, so those three flags never appear here.

## P1. Pre-flight (read-only, runs at Step 2)

Run these in order, because the first two checks decide whether any `gh stack` command may run at
all. Nothing here mutates. Record any question this section asks for Gate 2; the command it picks
runs at P2 or P3.

- A paused cascade. When `test -e "$(git rev-parse --git-common-dir)/gh-stack-rebase-state"`
  succeeds, HEAD is detached and every `gh stack` read fails with `not on any branch`. Stop, before any
  commit: report the paused cascade and say the rebase capability resolves it first. Nothing has
  been committed, so there is nothing to unwind.
- The stack, from the metadata. Run
  `bash ~/.agents/skills/workflow-profile/scripts/gh-stack-lookup.sh --branch "$(git branch --show-current)"`.
  It reads `gh stack`'s file from the git common dir, so it answers from a linked worktree. Exit
  0 is present: one line per stack listing this branch, members bottom to top (on two lines,
  ask which). Exit 3 or 4 is absent. Exit 5, 2 or 127 is unknown (on 127, say the profile helper
  scripts are missing). On unknown, report it and ask whether to try the stack route or take the
  degraded route. Unknown never routes as absent.
- A linked worktree. The worktree is linked when
  `git rev-parse --path-format=absolute --git-common-dir` differs from
  `git rev-parse --path-format=absolute --git-dir`. Both flags take `--path-format=absolute`:
  a relative common dir (`../.git` from a subdirectory) against an absolute git dir reads the
  main worktree as linked. From a linked worktree, `gh stack` reports the current branch "is not
  part of a stack" even when the metadata lists it, because it resolves its file per worktree.
  No answer it gives there can be trusted. Then branch on the lookup:
  - Absent: take the degraded route without running any `gh stack` command, and say plainly that
    a stack needs the main worktree.
  - Present: the branch is already in a stack, so the degraded route would open PRs outside it.
    Record adopt-first for P3 instead: stash, `gh stack checkout <pr-url>` on a still-open member
    the lookup's line names, stash apply, then the `add` route. The sequence was observed from the
    main worktree only, and Gate 2 says so and names the checkout.
  - Present, checkout limits: when the target branch is checked out in another worktree
    (`git worktree list`), stop before the checkout. When the checkout fails, stop and name the
    main worktree. Never run `gh stack unstack --local` on this route.
  - Present, members: the lookup's line is the member list. When the current branch is not the
    line's last member, ask the same three-way question as the `view` success case below. The
    mutation set takes its existing members from the line.
  - Unknown: take the degraded route. Ask the unknown question above only in the main worktree,
    because a `view` answer here cannot settle it.
- The version. Run `gh extension list`. On anything other than v0.1.0, say so and read
  `gh stack <cmd> --help` for every command below before the first one that mutates. The flags in
  this file are v0.1.0's.
- The remote, `<rem>`. Take a single remote, `gh-stack.remote`, or `remote.pushDefault`, and
  ask when none of those settles it. `gh stack`'s auto-detection stops on a multi-remote repo
  (`multiple remotes configured; set remote.pushDefault or use an interactive terminal`), and
  `init`, `add` and `view` take no `--remote` at all. A multi-remote repo that config does not
  settle therefore takes the degraded route rather than a prompt this run cannot answer.
- The stack. Run `gh stack view --json`, the non-blocking form; the bare command opens a TUI that
  never returns. Skip this read on the adopt-first route (linked worktree, membership
  present): from there it answers "not part of a stack" for a listed branch, so the member order
  comes from the lookup's line and the PR states from `gh pr view` per member, and P3 runs the
  view after the checkout instead. Read the actual keys, because the names are `gh-stack`'s, not
  this skill's. "Not part of a stack" and "belongs to multiple stacks" come back as errors on
  stderr, not as fields. Branch on the outcome:
  - Succeeds. A stack already tracks the current branch. Take its member order (bottom to
    top), which branch is current, and which members already carry an open PR. When the
    current branch is the top member, take the `add` route. When it is not the top,
    ask, because
    `gh stack add` adds to the top of the stack, not on top of the current branch. Offer three
    options. Add above the top member `<name>`, saying plainly that the new branch's parent is that
    member and not the branch the user is standing on. Stop, so the user can `gh stack top` or
    restructure with `gh stack modify` themselves. Or take the degraded route. Never guess: the answer decides which
    commits the new branch sits on.
  - Not part of a stack, and the lookup absent. Take the `init` route. The worktree check
    above makes this answer trustworthy.
  - Not part of a stack, and the lookup present. This is a contradiction in the main
    worktree. Stop and report both readings. No `init` runs on a branch the metadata lists.
  - Belongs to several stacks. Ask which one (its stack number), and record it. The
    `gh stack checkout <stack-number>` that makes it active runs at the top of the route it picks,
    after Gate 2, because it moves the worktree and Step 0's changes are still uncommitted:
    stash first as the `add` route does. Gate 2 names that checkout, or the user takes the
    degraded route instead.
  - Any other failure. Examples are auth, a rate limit, `timed out waiting for stack lock`,
    `Stacked PRs are not enabled for this repository` and `unknown command "stack"`. Report it
    verbatim and take the degraded route, or stop with it named when the lookup listed the
    branch (see the degraded route). None of those means this branch is in no stack.
- The mutation set. One `gh stack submit` pushes every active branch in the stack and
  retargets the base of every PR that already exists, so the run owns more than the branches
  it creates. The branches that submit will push are every branch this run creates, every
  existing member on the `add` route, and `<bottom>` on the `init` route where Gate 1 answered
  stacked. Record, per such branch, its unpushed commits (`git rev-list --count <rem>/<b>..<b>`)
  and whether its PR's base will move. Gate 2 must name that whole set, not only the new branches' own PRs, because
  approving the plan approves publishing all of it. `<bottom>` often carries commits of its own,
  which are Step 0's branch lead.

Done when the lookup's state is recorded, the route is `init`, `add` (adopt-first noted where it
applies) or degraded, `<rem>` is resolved on the first two, the existing members and the mutation
set are recorded, nothing has been created, and both reach Gate 2, or the paused-cascade stop
has fired.

## P2. The `init` route

The current branch is in no stack. `git checkout -b` and `git commit` carry an uncommitted tree
safely, while `gh stack init` is untested against a dirty tree. So cut every branch and make every
commit with plain git first, then track the stack over branches that already exist. `gh stack init` adopts existing branches by name, which is what makes this order work.

1. One concern: `git checkout -b <name> <pr-base>`, then Step 4 item 2's commits, unchanged.
2. Several concerns, bottom to top in the order the user chose: for each,
   `git checkout -b <name_i> <pr-base_i>`, where `<pr-base_1>` is what Gate 1 bound and each later
   `<pr-base_i>` is `<name_(i-1)>`, then make that concern's commits and move to the next. The remaining
   concerns stay in the working tree across each checkout, as they already do on the plain split.
3. `gh stack init --base <base> [<bottom>] <name_1> [<name_2> …]`, bottom to top. `--base <base>`
   is the trunk, the profile's Default branch row, and this is the one place `<base>` belongs on
   this path. `<bottom>` is the branch the user was on, included only where Gate 1 item 2's
   answer was stacked. `gh stack init` adopts existing branches by name, so naming it makes the
   current branch the stack's bottom member and its PR the stack's first.
4. Confirm, before anything is published: `gh stack view --json` lists every branch this run
   created, in the planned order, on the planned trunk. On a missing or misordered member, stop and
   report. HEAD stays where P2 left it. The commits are safe on their branches and nothing is on
   the remote.

Done when every planned branch exists with its planned commits, the view lists the whole intended
stack in order, and `git status --porcelain -uall` matches what Step 0 recorded minus what was committed,
or the stop has fired.

## P3. The `add` route

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
2. `gh stack add <name_i>`, never with `-A`, `-u` or `-m`.
3. `git stash apply <sha>`, leaving the entry in place until the user confirms it applied. An
   uncommitted edit destroyed by a per-branch checkout exists in no stage, no ref and no reflog.
4. That concern's commits, as Step 4 item 2 makes them.

Then confirm with `gh stack view --json`, exactly as the `init` route's step 4 does.

Done when every planned branch exists with its planned commits, every stash taken has been applied
and reported, the view lists the whole stack in order, and the members that were there before are
still in it.

## P3b. Verify each branch (before any push)

Runs after P2 or P3, before P4. Only this route verifies before the push: one submit publishes
every branch together, so a bad one would publish the whole set. The other routes push branch by
branch and skip this step. It asks the user nothing.

Record HEAD at the start. It is a stack member, because P2 or P3 left it on a created branch. Every
exit has the session, not a worker, restore exactly that: success, skip and stop. P4 needs HEAD on
a stack member, which this restores. When the restore is refused because a check modified tracked
files, report that and leave HEAD where it is. Never stash.

- Scope: only the branches this run created or committed to, bottom to top. Existing members and
  the user's own `<bottom>` commits are not re-verified, on purpose, yet the same submit publishes
  any unpushed commits they carry.
- Profile row: when `resolve-profile.sh --verify-commands` prints nothing, skip P3b. Gate 2 says so, and the P6 report
  states the skip.
- Delegation: one worker per branch, one at a time, bottom to top, because they share one
  worktree. Pick the tier from the shape of the work in `~/.agents/workflow-models/tiers.md`: running
  a fixed set of commands and reading their output is its deterministic-command shape. The worker checks out its branch
  and runs every command of the row, saving each command's output to a file and reading only its
  failing lines. Each command gets a 10-minute timeout, and a timeout counts as a failing check that stops the run.
  To allow longer, the user runs the commands themselves, then re-runs the skill.
  The report is at most 15 lines: each failing command's lines only.
- Row: the commands are the lines of
  `bash ~/.agents/skills/workflow-profile/scripts/resolve-profile.sh --verify-commands`, as
  `<dir><TAB><command>`. Never split the row yourself. A non-empty dir binds every command. The
  worker runs `cd <repo root>/<dir>`, skipped only when the session cwd already is that dir. Each
  command runs as one shell command, so `;`, `|`, `&&` and `$(...)` inside it are fine. The
  worker runs every command and reports each failure.
- Tree: report, never ask. The session itself, not a worker, takes `git status --porcelain -uall -z`
  before each branch check and after it, and compares the first one to what Step 0 recorded minus
  what was committed. Dirt Step 0 recorded is ignored. The worker only runs the checkout and the
  commands. The session parses paths from the `-z` output, so names with spaces or special
  characters survive, and deletes only paths that are `??` in the after-snapshot but not in the
  before-snapshot, never with `git clean`, and never deletes or resets a tracked path. A tracked
  file a check modified (a `--fix` run) is a stop that reports it, and so is any untracked dirt
  left after that cleanup.
- Stop: on a failing check or leftover dirt, name the branch and the failing lines or files, and
  push nothing. The commits live only on the run's branches, so do not delete them. Tell the user
  to `git checkout <failing branch>` first. HEAD is on the recorded branch, the one from
  P3b start. If the restore was refused, the report says where HEAD is. Then fix there and commit.
  If the recorded branch is not the top member `<top>`, run
  `gh stack rebase --upstack --no-trunk --remote <rem>` from it. The members above then carry the
  fix, so run `gh stack submit --auto --remote <rem>` yourself. The pushed
  PRs keep their generated titles and bodies unless the user runs the P5 pass. The run offers no
  resume and does not re-invoke the skill.
- Success: the P6 report states the result per branch.

Done when every in-scope branch has passed, or the skip is stated, or the stop has fired, and HEAD
is back on the branch recorded at the start, except when the restore was refused because a check
modified tracked files, where HEAD stays and the report says where.

## P4. Submit

```
touch "$(git rev-parse --path-format=absolute --git-common-dir)/push-nudge-hold"
gh stack submit --auto --remote <rem>
```

The hold file keeps the push hook quiet until P5 has run. The hook ignores a hold older than 30
minutes, so a crashed run cannot mute it for good.

`--auto` and nothing else, whatever the PR shape row says about drafts:

- Draft-first. `--auto` alone is already right, because it creates every new PR as a draft.
- Not draft-first. Still run `--auto` alone, then `gh pr ready <n>` per PR this run
  created, after P5 and never before it. `--open` marks new and existing PRs ready for
  review, so on a stack that already carried a member kept in draft on purpose it promotes a PR
  this run never touched.

One command pushes every branch, creates a PR for each branch without one, retargets the bases of
the PRs that already had one, and creates or updates the stack on GitHub. A PR that already existed
keeps its body; only its base may move.

Then map branch to PR number from `gh stack view --json`, and check every branch this run created
has one. Report a branch with no PR as unsubmitted, and do not run `gh pr create`; `gh stack` sets the bases.

A failed `submit` can leave pushed branches and open PRs. `submit` pushes, creates PRs and moves bases
before it establishes the stack on GitHub, so a late failure can leave branches pushed and PRs
open. The one to expect is `Stacked PRs are not enabled for this repository`. Reconcile before
falling back: `git fetch <rem>`, then `gh pr list --head <b> --state open --json number,baseRefName`
per branch this run created. Then create only the PRs that are missing, with the degraded route's
`gh pr create --base <pr-base>`, keep every edit P5 already applied, and say whether the local
metadata was kept or removed with `gh stack unstack --local`.

Done when the submit has run, every created branch has a PR number recorded, any branch without one
is named, and a refusal has been reconciled rather than assumed clean.

## P5. Titles and bodies

Per PR this run created, bottom to top, with the title and description Gate 2 approved for that
concern:

```
gh pr edit <n> --title "<title>" --body-file -
```

Heredoc the body, exactly as Step 4 item 5 does. Until this runs the stack carries auto-generated
titles and bodies, so Gate 2 says in one line that the PRs hold temporary text until this pass
finishes. Nothing is marked ready and nothing is handed to the CI watch before it, because a
reviewer reading first would read text the user never approved.

A PR the run did not create keeps its body: the run drafted no description for it, and a
hand-written body is the user's to keep unless Gate 2 surfaced it and the user approved the
replacement.

Then remove the hold: `rm -f "$(git rev-parse --path-format=absolute --git-common-dir)/push-nudge-hold"`.

Done when every created PR carries its planned title and body, the PRs that kept their own body are
named, only then any `gh pr ready` has run, and the hold is removed.

## P6. Verify and report

- `gh stack push` is not atomic and `submit` publishes through the same path, so verify rather
  than trusting its exit. Run `git fetch <rem>`, then check that `git rev-parse <b>` equals
  `git rev-parse --verify --quiet <rem>/<b>` for every branch in P1's mutation set, meaning the
  branches this run created and the existing members the submit pushed. One submit publishes the whole set,
  so an existing member left half-published fails the same way a new one does. On a mismatch,
  report a partial publish: name which branches landed and which did not, say that the
  un-landed branches' PRs now run CI against a base the remote does not have, and offer
  `gh stack push --remote <rem>` to finish.
- Report the P3b result per branch: passed, or skipped, or the stop's branch, failing lines and
  next step.
- Report the stack bottom to top: each branch, its PR number, its draft state, its base. Say that
  the PRs are a stack on GitHub.
- Then hand off. The hold kept the push hook quiet, so with a CI watcher in the profile run the CI
  watch yourself now, which watches every member of the stack and advances all of them once green;
  with `none`, say plainly that no CI watch follows and the stack is the user's to advance.

Done when every branch in the mutation set is verified against its remote, the P3b report is made,
the stack is reported bottom to top, and the hand-off is named.

## The degraded route

P1 sends you here from a linked worktree whose branch the lookup did not list, an unsettled
multi-remote repo, a missing extension, or any `gh stack view` failure that is not one of the two
membership answers. A branch the lookup lists never takes this route: on present membership each
of those blockers stops the run with the blocker named, because a PR opened here would sit
outside the existing stack. P4 sends you here for the PRs a refused submit left missing.

Run Step 4's items 1, 4 and 5 as written, with `<pr-base>` as Gate 1 bound it: the branches still
chain and each PR still opens against its parent, so the result is a correct chain of PRs that is
not a stack on GitHub. Say that in the report, name why, and name the one command that would make
it one once the blocker is gone: `gh stack link <pr-url> <pr-url> …`, bottom to top,
which builds the stack on GitHub from the PRs without writing local tracking state. That hint
applies only after an absent lookup: on a listed branch it would build a second, overlapping
stack. Do not run it here: it pushes branches and mutates PRs, and the blocker that sent you here
is the reason not to.

Done when the chain exists with each PR against its parent, the report says it is not a stack and
why, and the `link` command is named rather than run.
