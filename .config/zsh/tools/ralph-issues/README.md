# ralph-issues

Unattended sub-issue-by-sub-issue Claude Code runner for a parent GitHub issue.
See issue #1 in this repo for the full design.

This currently covers scaffolding (issue #2), the frontier-query ordering
function (issue #3), the GitHub tracker adapter + "what's next" vertical
slice (issue #4), per-sub-issue git worktree + claim (issue #5), the
headless implement-attempt invocation (issue #6), the read-only
confirmation pass (issue #7), the single sub-issue retry/verify-gated
close/escalate pipeline (issue #8), the outer loop over a parent issue's
full run with a whole-run wall-clock ceiling and progress visibility
(issue #9), the adapter selection seam (`--tracker` flag +
`TRACKER_ADAPTER` override), the Forge tracker adapter (issue #30), and the
end-to-end forge run wiring that skips GitHub remote inference and derives
the on-screen scope from `forge project` under `--tracker forge` (issue
#31). The final single pull request covering a whole run doesn't exist yet.

## Usage

```sh
ralph-issues <parent-issue-number> [--repo <owner/repo>] [--tracker <github|forge>] [--max-attempts <n>] [--max-minutes <n>]
```

`--repo` defaults to the current checkout's repo, inferred from `git remote -v`.

`--tracker <name>` (default `github`) selects which tracker adapter the run
uses. Both `bin/ralph-issues` and `lib/sub-issue-pipeline` resolve the
adapter to invoke through a single `TRACKER_ADAPTER` variable, overridable
like `SUB_ISSUE_PIPELINE` below, defaulting to `lib/<tracker>-adapter`.
`bin/ralph-issues` exports it so the pipeline it spawns resolves the same
adapter rather than re-deriving it from a `--tracker` flag it never sees.
`--tracker forge` resolves to `lib/forge-adapter` (below); an adapter
missing from `lib/` for any other tracker name fails fast with a clear
error rather than a generic "command not found".

Under `--tracker forge`, `bin/ralph-issues` skips `infer_repo_from_git_remote`
entirely — a forge run in a repo with no `origin` git remote succeeds
instead of failing — and instead runs `forge project` for the on-screen
scope shown in `Now working:` / `No ready sub-issue for parent ...` lines.
This requires a `forge` CLI version providing `forge project`, which prints
the derived project name on one line to stdout (exit 0), falling back to
the current directory's basename outside a git repo. That value is passed
through as the adapter's scope-token argument, though `lib/forge-adapter`
ignores it (forge derives its own project scope internally). `--tracker
github` (or no `--tracker` flag) is unaffected and continues to infer the
GitHub repo exactly as before.
The tool loops: it recomputes the frontier, works the next ready sub-issue
(the first one with no open blocker, no assignee, and a `ready-for-agent`
label) to completion, then
recomputes the frontier again -- repeating until the frontier query returns
no further ready sub-issue, or the whole-run ceiling is hit. Sub-issues are
always processed strictly one at a time, in frontier order, never in
parallel. For each ready sub-issue, it creates a dedicated, disposable git
worktree and branch scoped to that sub-issue (`lib/worktree`, below) and
claims it via the adapter, so an in-progress or abandoned attempt on one
sub-issue can never contaminate another's starting state. Running the tool
again while a sub-issue is still assigned does not re-claim it or create a
second worktree — the frontier query skips assigned issues. Immediately
after claiming, the outer loop defensively strips both `ready-for-agent` and
`ready-for-human` from the sub-issue, so it never sits claimed alongside a
stale pole left over from a previous run. It then hands the sub-issue off to
`lib/sub-issue-pipeline` (below), which runs the implement/confirm retry
loop and closes, merges, or escalates it, before the outer loop moves on to
recomputing the frontier for the next one -- including after an escalation,
so one stuck sub-issue never stalls the rest of the run. After each
sub-issue that's confirmed and merged, the next sub-issue's worktree is
branched from the run's integration branch (rather than the commit the run
started at), so later sub-issues build on top of already-completed work
instead of diverging from stale starting state.

On any non-zero exit from `lib/sub-issue-pipeline` -- including a crash
before the pipeline's own escalation code ever runs -- the outer loop
backstops the sub-issue to the same parked-for-human state the pipeline's
own give-up path sets: unassigned, `ready-for-agent` removed,
`ready-for-human` added. Every one of those adapter calls is already
idempotent, so re-running them after a pipeline that *did* escalate cleanly
on its own is a harmless no-op -- the guarantee is that no open issue is
ever left claimed but not parked, regardless of how the pipeline fails.

Before starting each sub-issue, a whole-run wall-clock ceiling is checked --
between attempts only, never in the middle of one:

- `--max-minutes <n>` (default 240) -- wall-clock time elapsed since the
  run started.

The ceiling stops the run cleanly (the in-progress sub-issue, if any, has
already finished) rather than mid-attempt. It has a safe built-in default
so a first run with no flags still behaves safely.

While running, the tool prints a `Processed so far:` list of every
sub-issue already finished in this run and its outcome
(confirmed-and-closed or escalated) at the start of every iteration --
including the one about to work the next sub-issue, printed right before
`Now working: #<n> <title>` -- so an unattended run's progress up to and
including whatever's in flight is visible on screen throughout, without
digging through logs.

`--max-attempts <n>` (default 3) sets the per-sub-issue retry ceiling passed
through to `lib/sub-issue-pipeline`.

## `lib/implement-attempt`

The only place `claude` is invoked from ralph-issues.

```sh
implement-attempt prompt <issue-number> <issue-title>            # -> the prompt `run` sends, no side effects
implement-attempt run <worktree-dir> <issue-number> <issue-title>  # -> invokes headless Claude Code
```

`run` invokes a completely fresh, memory-less headless Claude Code session
(`claude -p --dangerously-skip-permissions --output-format json`) in
`<worktree-dir>`, prompting it to implement the sub-issue via the
`implement` skill's slash-command form. No session id, `--resume`, or
`--continue` is ever passed, so every call is a wholly new session with no
memory of any prior attempt beyond what's already committed or present in
the worktree. Permission checks are fully bypassed so an unattended run
never stalls waiting on an approval. `--output-format json` is requested
solely to expose the session's top-level `usage` object. On success, `run`
prints the session's final response followed by a `CONTEXT_TOKENS=<n>` line
— the sum of `usage.input_tokens`, `usage.cache_read_input_tokens`, and
`usage.cache_creation_input_tokens`, an approximation of how full the
context window got on the session's final turn — which `lib/sub-issue-pipeline`
ignores. This is purely informational: never summed across attempts, never
enforced. Exits with the invoked session's exit status, though
`lib/sub-issue-pipeline` never treats that status as a verdict — retrying a
failed attempt, verifying its result, and closing the sub-issue are its
job, not this script's.

## `lib/confirmation-attempt`

A second, independent headless Claude Code invocation in the same worktree,
with no ability to edit or write any file — the implementing attempt can
never grade its own homework.

```sh
confirmation-attempt prompt <base-ref> <issue-number> <issue-title>            # -> the prompt `run` sends, no side effects
confirmation-attempt run <worktree-dir> <base-ref> <issue-number> <issue-title>  # -> invokes headless Claude Code, prints the verdict
```

`run` invokes a fresh headless Claude Code session
(`claude -p --tools Bash,Read,Grep,Glob,Agent,Skill --dangerously-skip-permissions --json-schema ... --output-format json`)
in `<worktree-dir>`. `--tools` is a hard restriction — Edit, Write, and
NotebookEdit are never available to the model, regardless of the permission
bypass, so it cannot mutate the worktree no matter what it decides to do.
The session discovers and runs the target repo's own test/typecheck
commands itself (no per-repo configuration), then invokes the `code-review`
skill's Standards+Spec review against `git diff <base-ref>...HEAD`. Its
final answer is constrained by `--json-schema` to
`{"verdict": "pass"|"fail", "reason": "..."}`; `--output-format json` wraps
that in the session's full result envelope, which is what exposes both the
schema-constrained `structured_output` and the top-level `usage` object.
`run` parses that envelope and prints `Confirmation: PASS -- <reason>` or
`Confirmation: FAIL -- <reason>` followed by a `CONTEXT_TOKENS=<n>` line —
the sum of `usage.input_tokens`, `usage.cache_read_input_tokens`, and
`usage.cache_creation_input_tokens` — on both pass and fail, which
`lib/sub-issue-pipeline` strips before quoting the output into a comment
(below). Exits 0 only on a "pass" verdict; a reported "fail", a session
that errors out, or output that doesn't parse as a verdict all exit
non-zero — every non-pass outcome is treated as "not confirmed". Retrying,
escalating, and closing the sub-issue based on this verdict are
`lib/sub-issue-pipeline`'s job (below), not this script's.

## `lib/sub-issue-pipeline`

Wires `lib/implement-attempt` and `lib/confirmation-attempt` into a single
sub-issue's retry loop, and decides what happens to that sub-issue once the
loop ends. This is the piece that actually closes, merges, or escalates a
sub-issue — orchestration code should call this rather than the implement
and confirmation scripts directly.

```
sub-issue-pipeline run <repo-root> <worktree-dir> <base-ref> <repo> <parent-issue> <issue-number> <issue-title> [<max-attempts>]
```

`run` repeats implement-then-confirm in `<worktree-dir>` (reusing the same
worktree across retries — nothing is recreated between attempts) up to
`<max-attempts>` times (default 3). The implementing attempt's own exit
status is never treated as a verdict; only the confirmation attempt's
pass/fail decides the outcome, so the implementing attempt can never grade
its own homework.

On a passing confirmation: merges the sub-issue's branch into
`<parent-issue>`'s shared integration branch (`ralph-issues/parent-<n>-integration`,
created via `lib/worktree`'s `create-integration` if it doesn't exist yet),
discards the sub-issue's worktree (`lib/worktree discard`), and only then
closes the sub-issue via the adapter with a summary comment — in that order,
so a merge conflict is caught before anything is closed or discarded.

Both terminal give-up paths — exhausting `<max-attempts>` without a pass, and
a merge conflict against the integration branch — release the sub-issue and
park it for a human the same way: post a comment, remove the
`ready-for-agent` label, add `ready-for-human`, and unassign it via the
adapter, leaving its worktree and branch in place rather than discarding
them. Exits non-zero.

The implementing attempt streams directly to the terminal. The confirmation
attempt's output is captured so it can be quoted into the closing or
escalation comment, with any `CONTEXT_TOKENS=<n>` bookkeeping line stripped
out first.

## `lib/worktree`

The only place `git worktree` and `wt` are invoked from ralph-issues.

```sh
worktree create <repo-root> <issue-number> [<base-ref>]  # -> worktree path
worktree path <repo-root> <issue-number>                  # -> worktree path, no side effects
worktree branch-name <issue-number>                       # -> branch name, no side effects
worktree discard <repo-root> <issue-number>               # removes the worktree, leaves the branch
worktree integration-branch-name <parent-issue>           # -> integration branch name, no side effects
worktree integration-path <repo-root> <parent-issue>      # -> integration worktree path, no side effects
worktree create-integration <repo-root> <parent-issue> [<base-ref>]  # -> integration worktree path
```

`create` branches a new `ralph-issues/issue-<n>` branch off `<base-ref>`
(default: `HEAD`) into a disposable worktree at
`<repo-root's parent>/<repo-root's basename>.ralph-worktrees/issue-<n>`, sibling
to the repo so it's outside version control. If a worktree already exists at
that path, it's reused rather than recreated. `discard` removes that
worktree once a sub-issue is done with it (via `git worktree remove`), but
never touches the branch itself.

`create-integration` is the same idea for the run's shared integration
branch (`ralph-issues/parent-<n>-integration`, in a persistent sibling
worktree at `...ralph-worktrees/parent-<n>-integration`) that
`lib/sub-issue-pipeline` merges each verified sub-issue's branch into.

All five subcommands above route through an internal backend seam selected
by `RALPH_WORKTREE_BACKEND` (`git`, `wt`, or `auto`; default `auto`). `auto`
selects the `wt` backend when `wt` is on `PATH`, falling back to the `git`
backend described above otherwise.

The `wt` backend behaves exactly as an interactive `wt` user would, with one
deliberate carve-out for `discard`:

- `create` / `create-integration` check whether the target branch already
  exists (via `wt list --branches --format json`). If it doesn't, `wt switch
  --create <branch> --base <base-ref> --no-cd --format json` creates it; if
  it does, a plain `wt switch <branch> --no-cd --format json` reuses its
  worktree (or creates one for the existing, worktree-less branch), ignoring
  `<base-ref>`. The worktree path is read from `.path` in `wt`'s JSON on
  stdout — `wt` owns the path via its own template, `lib/worktree` only
  reports it.
- `discard` runs `wt remove --no-delete-branch --foreground` — the one
  carve-out from default `wt remove` behavior, so a just-merged branch
  survives and removal stays synchronous, while `wt`'s `pre-remove`/
  `post-remove` hooks still run. A no-op when no worktree exists for the
  branch.
- `path` / `integration-path` error clearly under the `wt` backend, since
  the path isn't predictable before creation.
- `wt` is never invoked with `--yes`, so its approval prompts surface to the
  user. `wt switch` additionally always passes `--no-cd`, so no caller's cwd
  is disturbed (`WORKTRUNK_DIRECTIVE_CD_FILE` is never set); `wt list` and
  `wt remove` never change the shell's cwd regardless.

## `lib/github-adapter`

The only place `gh` is invoked from ralph-issues. Orchestration code (the
`ralph-issues` CLI's outer loop, and `lib/sub-issue-pipeline`'s inner loop)
calls only this adapter's subcommand interface, never `gh` directly — a
future non-GitHub tracker could be added as a sibling adapter behind the
same interface without touching orchestration logic.

```sh
github-adapter frontier-input <owner/repo> <parent-issue>   # -> lib/frontier-query's input JSON
github-adapter title <owner/repo> <issue>                   # -> issue title
github-adapter claim <owner/repo> <issue>                    # assign to @me
github-adapter unclaim <owner/repo> <issue>                  # remove @me's assignment
github-adapter comment <owner/repo> <issue> <body>           # post a comment
github-adapter close <owner/repo> <issue> [<closing-comment>]
github-adapter label <owner/repo> <issue> <label>            # e.g. flag for human follow-up; creates the label if missing
github-adapter unlabel <owner/repo> <issue> <label>          # remove a label (no-op if absent)
```

`frontier-input` lists a parent's open sub-issues in tracker-native order and
resolves each one's blocked/assigned state, in the shape `lib/frontier-query`
expects. It uses GitHub's native sub-issue/dependency data when the parent
has any populated; otherwise it reconstructs the same shape from the parent
body's checklist plus each candidate's `Part of #<parent>` marker (and a
`Blocked by: #<n>, #<n>` line for dependency edges), per this repo's
`docs/agents/issue-tracker.md` wayfinder convention.

## `lib/forge-adapter`

The sole place `forge` is invoked from ralph-issues, exposing the identical
8-subcommand interface `lib/github-adapter` does, mapped onto
`forge task ...` instead of `gh`. Selected via `--tracker forge`.

```sh
forge-adapter frontier-input <scope> <parent>   # -> lib/frontier-query's input JSON
forge-adapter title <scope> <id>                # -> task title
forge-adapter claim <scope> <id>                 # claim for the current user
forge-adapter unclaim <scope> <id>               # release the assignee
forge-adapter comment <scope> <id> <body>        # post a comment
forge-adapter close <scope> <id> [<closing-comment>]
forge-adapter label <scope> <id> <label>         # creates the label if missing
forge-adapter unlabel <scope> <id> <label>       # remove a label (no-op if absent)
```

`<scope>` is accepted for interface parity with `github-adapter` but
ignored — `forge` derives its own project scope from the current checkout,
so there's no `owner/repo`-equivalent value to pass through.

`frontier-input` issues a single `forge task list --parent <parent>
--json=id,title,status,labels,assignee,blocked_by` and always emits the
native shape — Forge always has task-native parent/child and
blocked-by data, so there's no checklist fallback to reconstruct. Each open
child's `blocked_by` array (which lists every blocker regardless of state)
is collapsed to an open-blocker count, and its `assignee` scalar
(`null` or a single name) is normalized to the `assignees` array
`lib/frontier-query` expects.

`claim` maps to `forge task claim <id>` with no `--force`, so it never
steals an assignment from someone else. `close` runs `forge task comment`
(when a closing comment is given) before `forge task update --status
closed`, in that order — the same "comment, then close" sequencing
`github-adapter` uses.

## `lib/frontier-query`

A pure, tracker-agnostic function (not on `PATH`) that decides which
sub-issue to work on next. It reads a JSON decision input on stdin and
prints `{"next": <issue-number-or-null>}`. It makes no `gh`, `git`, or
Claude Code calls — callers (the future orchestrator) are responsible for
fetching tracker state and shaping it into one of two input shapes:

- `"shape": "native"` — a `sub_issues` array in tracker-native order, each
  with a `blocked_by` open-blocker count, an `assignees` array, and a
  `labels` array, for parents using GitHub's native sub-issue/dependency
  data.
- `"shape": "checklist"` — a `checklist_order` array of issue numbers, an
  `issues` map keyed by issue number (each with a `blocked_by` array of
  blocker issue numbers, an `assignees` array, and a `labels` array), and an
  `open_issues` array of currently-open issue numbers, for parents predating
  native sub-issues that instead use a checklist body plus a
  `Part of #<parent>` marker.

In both shapes the decision is the same: the first issue, in the given
order, with no open blocker, no assignee, and a `ready-for-agent` label;
`null` if none qualify.

## Running tests

Requires [bats-core](https://github.com/bats-core/bats-core) (`brew install bats-core`)
and [`jq`](https://jqlang.org/) (`brew install jq`).

```sh
bats .config/zsh/tools/ralph-issues/test
```
