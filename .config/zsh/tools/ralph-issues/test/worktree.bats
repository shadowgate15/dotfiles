#!/usr/bin/env bats

setup() {
  WORKTREE="${BATS_TEST_DIRNAME}/../lib/worktree"

  REPO_DIR="$(cd "$(mktemp -d)" && pwd -P)/some-repo"
  mkdir -p "${REPO_DIR}"
  git -C "${REPO_DIR}" init -q
  git -C "${REPO_DIR}" config user.email "test@example.com"
  git -C "${REPO_DIR}" config user.name "Test"
  git -C "${REPO_DIR}" commit -q --allow-empty -m "initial commit"
}

teardown() {
  git -C "${REPO_DIR}" worktree list --porcelain 2>/dev/null \
    | awk '/^worktree /{print $2}' \
    | tail -n +2 \
    | xargs -I{} rm -rf {}
  rm -rf "$(dirname "${REPO_DIR}")"
}

# Pure helpers: no `git worktree` call involved, sourced directly.

@test "branch_name: builds the ralph-issues/issue-<n> convention" {
  run bash -c 'source "$1"; branch_name "$2"' _ "${WORKTREE}" 42

  [ "$status" -eq 0 ]
  [ "$output" = "ralph-issues/issue-42" ]
}

@test "worktree_path: builds the sibling .ralph-worktrees/issue-<n> convention" {
  run bash -c 'source "$1"; worktree_path "$2" "$3"' _ "${WORKTREE}" "${REPO_DIR}" 42

  [ "$status" -eq 0 ]
  [ "$output" = "$(dirname "${REPO_DIR}")/some-repo.ralph-worktrees/issue-42" ]
}

# branch-name subcommand: gives orchestration code a single source of truth
# for the naming convention instead of re-deriving the literal itself.

@test "branch-name: prints the branch name for an issue without creating anything" {
  run "${WORKTREE}" branch-name 42

  [ "$status" -eq 0 ]
  [ "$output" = "ralph-issues/issue-42" ]
}

@test "branch-name: rejects a non-numeric issue number" {
  run "${WORKTREE}" branch-name not-a-number

  [ "$status" -ne 0 ]
  [[ "$output" == *"issue number"* ]]
}

@test "path: prints the deterministic worktree path without creating anything" {
  run "${WORKTREE}" path "${REPO_DIR}" 42

  [ "$status" -eq 0 ]
  [ "$output" = "$(dirname "${REPO_DIR}")/some-repo.ralph-worktrees/issue-42" ]
  [ ! -e "$(dirname "${REPO_DIR}")/some-repo.ralph-worktrees" ]
}

@test "create: creates a new worktree and branch scoped to the issue" {
  run "${WORKTREE}" create "${REPO_DIR}" 42

  [ "$status" -eq 0 ]
  local expected_path
  expected_path="$(dirname "${REPO_DIR}")/some-repo.ralph-worktrees/issue-42"
  [ "$output" = "${expected_path}" ]
  [ -d "${expected_path}" ]

  run git -C "${REPO_DIR}" show-ref --verify --quiet "refs/heads/ralph-issues/issue-42"
  [ "$status" -eq 0 ]

  run git -C "${expected_path}" rev-parse --abbrev-ref HEAD
  [ "$output" = "ralph-issues/issue-42" ]
}

@test "create: a second call for the same issue reuses the existing worktree instead of erroring" {
  "${WORKTREE}" create "${REPO_DIR}" 42

  run "${WORKTREE}" create "${REPO_DIR}" 42

  [ "$status" -eq 0 ]
  [ "$output" = "$(dirname "${REPO_DIR}")/some-repo.ralph-worktrees/issue-42" ]

  run git -C "${REPO_DIR}" worktree list
  [ "$(echo "$output" | grep -c "issue-42")" -eq 1 ]
}

@test "create: two different issues get two independent worktrees and branches" {
  run "${WORKTREE}" create "${REPO_DIR}" 42
  local path42="$output"
  run "${WORKTREE}" create "${REPO_DIR}" 43
  local path43="$output"

  [ "${path42}" != "${path43}" ]
  [ -d "${path42}" ]
  [ -d "${path43}" ]

  run git -C "${REPO_DIR}" show-ref --verify --quiet "refs/heads/ralph-issues/issue-42"
  [ "$status" -eq 0 ]
  run git -C "${REPO_DIR}" show-ref --verify --quiet "refs/heads/ralph-issues/issue-43"
  [ "$status" -eq 0 ]
}

@test "create: rejects a non-numeric issue number" {
  run "${WORKTREE}" create "${REPO_DIR}" not-a-number

  [ "$status" -ne 0 ]
  [[ "$output" == *"issue number"* ]]
}

@test "rejects an unknown subcommand" {
  run "${WORKTREE}" bogus "${REPO_DIR}" 42

  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown subcommand"* ]]
}
