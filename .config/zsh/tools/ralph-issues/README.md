# ralph-issues

Unattended sub-issue-by-sub-issue Claude Code runner for a parent GitHub issue.
See issue #1 in this repo for the full design.

This is currently scaffolding only (issue #2): argument parsing and repo
inference, with no tracker, git worktree, or Claude Code invocation logic yet.

## Usage

```sh
ralph-issues <parent-issue-number> [--repo <owner/repo>]
```

`--repo` defaults to the current checkout's repo, inferred from `git remote -v`.

## Running tests

Requires [bats-core](https://github.com/bats-core/bats-core) (`brew install bats-core`).

```sh
bats .config/zsh/tools/ralph-issues/test
```
