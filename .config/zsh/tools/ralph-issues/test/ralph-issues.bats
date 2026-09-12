#!/usr/bin/env bats

setup() {
  RALPH_ISSUES_BIN="${BATS_TEST_DIRNAME}/../bin/ralph-issues"

  export GIT_FIXTURE_DIR
  GIT_FIXTURE_DIR="$(mktemp -d)"
  git -C "${GIT_FIXTURE_DIR}" init -q
  git -C "${GIT_FIXTURE_DIR}" remote add origin "git@github.com:some-owner/some-repo.git"
}

teardown() {
  rm -rf "${GIT_FIXTURE_DIR}"
}

@test "fails with usage when no parent issue number is given" {
  run "${RALPH_ISSUES_BIN}"

  [ "$status" -ne 0 ]
  [[ "$output" == *"usage"* || "$output" == *"Usage"* ]]
}

@test "fails when the parent issue number is not a positive integer" {
  cd "${GIT_FIXTURE_DIR}"
  run "${RALPH_ISSUES_BIN}" not-a-number

  [ "$status" -ne 0 ]
  [[ "$output" == *"parent issue number"* ]]
}

@test "echoes the parent issue number and infers the repo from git remote" {
  cd "${GIT_FIXTURE_DIR}"
  run "${RALPH_ISSUES_BIN}" 2

  [ "$status" -eq 0 ]
  [[ "$output" == *"Parent issue: 2"* ]]
  [[ "$output" == *"Target repo: some-owner/some-repo"* ]]
}

@test "infers the repo from an https git remote" {
  cd "${GIT_FIXTURE_DIR}"
  git remote set-url origin "https://github.com/some-owner/some-repo.git"
  run "${RALPH_ISSUES_BIN}" 7

  [ "$status" -eq 0 ]
  [[ "$output" == *"Target repo: some-owner/some-repo"* ]]
}

@test "accepts a --repo override instead of inferring from git remote" {
  cd "${GIT_FIXTURE_DIR}"
  run "${RALPH_ISSUES_BIN}" 2 --repo other-owner/other-repo

  [ "$status" -eq 0 ]
  [[ "$output" == *"Parent issue: 2"* ]]
  [[ "$output" == *"Target repo: other-owner/other-repo"* ]]
}

@test "rejects a malformed --repo override" {
  cd "${GIT_FIXTURE_DIR}"
  run "${RALPH_ISSUES_BIN}" 2 --repo not-a-valid-repo

  [ "$status" -ne 0 ]
  [[ "$output" == *"--repo"* ]]
}

@test "fails when no --repo override is given and the cwd has no git remote to infer from" {
  local bare_dir
  bare_dir="$(mktemp -d)"
  git -C "${bare_dir}" init -q
  cd "${bare_dir}"

  run "${RALPH_ISSUES_BIN}" 2

  [ "$status" -ne 0 ]
  [[ "$output" == *"repo"* ]]

  rm -rf "${bare_dir}"
}
