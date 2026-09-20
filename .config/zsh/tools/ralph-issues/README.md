# ralph-issues

Unattended sub-issue-by-sub-issue Claude Code runner for a parent GitHub issue.
See issue #1 in this repo for the full design.

This currently covers scaffolding (issue #2), the frontier-query ordering
function (issue #3), the GitHub tracker adapter + "what's next" vertical
slice (issue #4), per-sub-issue git worktree + claim (issue #5), the
headless implement-attempt invocation (issue #6), and the read-only
confirmation pass (issue #7). The retry/escalate loop and outer-loop
ceilings don't exist yet.

## Usage

```sh
ralph-issues <parent-issue-number> [--repo <owner/repo>]
```

`--repo` defaults to the current checkout's repo, inferred from `git remote -v`.
It finds the next ready sub-issue (the first one with no open blocker and no
assignee), or says clearly that none are ready. When one is ready, it creates
a dedicated, disposable git worktree and branch scoped to that sub-issue
(`<lib/worktree>`, below) and claims it via the adapter, so an in-progress or
abandoned attempt on one sub-issue can never contaminate another's starting
state. Running the tool again while that sub-issue is still assigned does
not re-claim it or create a second worktree — the frontier query skips
assigned issues. It then invokes a single headless implement attempt
(`<lib/implement-attempt>`, below) in that worktree.

## `lib/implement-attempt`

The only place `claude` is invoked from ralph-issues.

```sh
implement-attempt prompt <issue-number> <issue-title>            # -> the prompt `run` sends, no side effects
implement-attempt run <worktree-dir> <issue-number> <issue-title>  # -> invokes headless Claude Code
```

`run` invokes a completely fresh, memory-less headless Claude Code session
(`claude -p --dangerously-skip-permissions`) in `<worktree-dir>`, prompting
it to implement the sub-issue via the `implement` skill's slash-command
form. No session id, `--resume`, or `--continue` is ever passed, so every
call is a wholly new session with no memory of any prior attempt beyond
what's already committed or present in the worktree. Permission checks are
fully bypassed so an unattended run never stalls waiting on an approval.
Exits with the invoked session's exit status. Retrying a failed attempt,
verifying its result, and closing the sub-issue are not this script's job —
see issues #7 and #8.

## `lib/confirmation-attempt`

A second, independent headless Claude Code invocation in the same worktree,
with no ability to edit or write any file — the implementing attempt can
never grade its own homework.

```sh
confirmation-attempt prompt <base-ref> <issue-number> <issue-title>            # -> the prompt `run` sends, no side effects
confirmation-attempt run <worktree-dir> <base-ref> <issue-number> <issue-title>  # -> invokes headless Claude Code, prints the verdict
```

`run` invokes a fresh headless Claude Code session
(`claude -p --tools Bash,Read,Grep,Glob,Agent,Skill --dangerously-skip-permissions`)
in `<worktree-dir>`. `--tools` is a hard restriction — Edit, Write, and
NotebookEdit are never available to the model, regardless of the permission
bypass, so it cannot mutate the worktree no matter what it decides to do.
The session discovers and runs the target repo's own test/typecheck
commands itself (no per-repo configuration), then invokes the `code-review`
skill's Standards+Spec review against `git diff <base-ref>...HEAD`. Its
final answer is constrained by `--json-schema` to
`{"verdict": "pass"|"fail", "reason": "..."}`, which `run` parses and prints
as `Confirmation: PASS -- <reason>` or `Confirmation: FAIL -- <reason>`.
Exits 0 only on a "pass" verdict; a reported "fail", a session that errors
out, or output that doesn't parse as a verdict all exit non-zero — every
non-pass outcome is treated as "not confirmed". Retrying, escalating, and
closing the sub-issue based on this verdict are not this script's job — see
issue #8.

## `lib/worktree`

The only place `git worktree` is invoked from ralph-issues.

```sh
worktree create <repo-root> <issue-number> [<base-ref>]  # -> worktree path
worktree path <repo-root> <issue-number>                  # -> worktree path, no side effects
worktree branch-name <issue-number>                       # -> branch name, no side effects
```

`create` branches a new `ralph-issues/issue-<n>` branch off `<base-ref>`
(default: `HEAD`) into a disposable worktree at
`<repo-root's parent>/<repo-root's basename>.ralph-worktrees/issue-<n>`, sibling
to the repo so it's outside version control. If a worktree already exists at
that path, it's reused rather than recreated.

## `lib/github-adapter`

The only place `gh` is invoked from ralph-issues. Orchestration code (the
`ralph-issues` CLI, and future outer/inner-loop logic) calls only this
adapter's subcommand interface, never `gh` directly — a future non-GitHub
tracker could be added as a sibling adapter behind the same interface without
touching orchestration logic.

```sh
github-adapter frontier-input <owner/repo> <parent-issue>   # -> lib/frontier-query's input JSON
github-adapter title <owner/repo> <issue>                   # -> issue title
github-adapter claim <owner/repo> <issue>                    # assign to @me
github-adapter comment <owner/repo> <issue> <body>           # post a comment
github-adapter close <owner/repo> <issue> [<closing-comment>]
github-adapter label <owner/repo> <issue> <label>             # e.g. flag for human follow-up
```

`frontier-input` lists a parent's open sub-issues in tracker-native order and
resolves each one's blocked/assigned state, in the shape `lib/frontier-query`
expects. It uses GitHub's native sub-issue/dependency data when the parent
has any populated; otherwise it reconstructs the same shape from the parent
body's checklist plus each candidate's `Part of #<parent>` marker (and a
`Blocked by: #<n>, #<n>` line for dependency edges), per this repo's
`docs/agents/issue-tracker.md` wayfinder convention.

## `lib/frontier-query`

A pure, tracker-agnostic function (not on `PATH`) that decides which
sub-issue to work on next. It reads a JSON decision input on stdin and
prints `{"next": <issue-number-or-null>}`. It makes no `gh`, `git`, or
Claude Code calls — callers (the future orchestrator) are responsible for
fetching tracker state and shaping it into one of two input shapes:

- `"shape": "native"` — a `sub_issues` array in tracker-native order, each
  with a `blocked_by` open-blocker count and an `assignees` array, for
  parents using GitHub's native sub-issue/dependency data.
- `"shape": "checklist"` — a `checklist_order` array of issue numbers, an
  `issues` map keyed by issue number (each with a `blocked_by` array of
  blocker issue numbers and an `assignees` array), and an `open_issues`
  array of currently-open issue numbers, for parents predating native
  sub-issues that instead use a checklist body plus a `Part of #<parent>`
  marker.

In both shapes the decision is the same: the first issue, in the given
order, with no open blocker and no assignee; `null` if none qualify.

## Running tests

Requires [bats-core](https://github.com/bats-core/bats-core) (`brew install bats-core`)
and [`jq`](https://jqlang.org/) (`brew install jq`).

```sh
bats .config/zsh/tools/ralph-issues/test
```
