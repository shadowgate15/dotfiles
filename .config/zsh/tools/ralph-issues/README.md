# ralph-issues

Unattended sub-issue-by-sub-issue Claude Code runner for a parent GitHub issue.
See issue #1 in this repo for the full design.

This currently covers scaffolding (issue #2), the frontier-query ordering
function (issue #3), and the GitHub tracker adapter + "what's next" vertical
slice (issue #4). Git worktree lifecycle and Claude Code invocation logic
don't exist yet.

## Usage

```sh
ralph-issues <parent-issue-number> [--repo <owner/repo>]
```

`--repo` defaults to the current checkout's repo, inferred from `git remote -v`.
It prints the next ready sub-issue (the first one with no open blocker and no
assignee), or says clearly that none are ready.

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
