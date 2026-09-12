# ralph-issues

Unattended sub-issue-by-sub-issue Claude Code runner for a parent GitHub issue.
See issue #1 in this repo for the full design.

This is currently scaffolding (issue #2) plus the frontier-query ordering
function (issue #3). No tracker, git worktree, or Claude Code invocation
logic exists yet.

## Usage

```sh
ralph-issues <parent-issue-number> [--repo <owner/repo>]
```

`--repo` defaults to the current checkout's repo, inferred from `git remote -v`.

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
