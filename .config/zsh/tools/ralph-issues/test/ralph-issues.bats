#!/usr/bin/env bats

setup() {
  RALPH_ISSUES_BIN="${BATS_TEST_DIRNAME}/../bin/ralph-issues"

  export GIT_FIXTURE_DIR
  # Resolve to the physical path (pwd -P) so it matches what
  # `git rev-parse --show-toplevel` returns inside the tool — on macOS
  # mktemp's path is a symlink (/var -> /private/var) that git resolves.
  GIT_FIXTURE_DIR="$(cd "$(mktemp -d)" && pwd -P)"
  git -C "${GIT_FIXTURE_DIR}" init -q
  git -C "${GIT_FIXTURE_DIR}" remote add origin "git@github.com:some-owner/some-repo.git"
  git -C "${GIT_FIXTURE_DIR}" config user.email "test@example.com"
  git -C "${GIT_FIXTURE_DIR}" config user.name "Test"
  git -C "${GIT_FIXTURE_DIR}" commit -q --allow-empty -m "initial commit"
}

teardown() {
  # Worktrees created by the tool live as a sibling directory to the fixture
  # repo, outside version control — clean those up alongside the repo itself.
  rm -rf "${GIT_FIXTURE_DIR}" "${GIT_FIXTURE_DIR}.ralph-worktrees"
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

setup_fake_gh() {
  # $1: repo, $2: parent issue, $3: sub_issues JSON (native shape), $4: next issue number, $5: next title
  FAKE_GH_DIR="$(mktemp -d)"
  cat >"${FAKE_GH_DIR}/gh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
case "\$*" in
  "api repos/${1}/issues/${2}/sub_issues --jq"*)
    echo '${3}'
    ;;
  "issue view ${4} --repo ${1} --json title --jq .title")
    echo "${5}"
    ;;
  "issue edit ${4} --repo ${1} --add-assignee @me")
    ;;
  *)
    echo "fake gh: unhandled invocation: \$*" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "${FAKE_GH_DIR}/gh"
  PATH="${FAKE_GH_DIR}:${PATH}"
}

@test "prints the next ready sub-issue's number and title, inferring the repo from git remote" {
  cd "${GIT_FIXTURE_DIR}"
  setup_fake_gh "some-owner/some-repo" 2 \
    '[{"number":7,"state":"open","blocked_by":0,"assignees":[]}]' \
    7 "Do the thing"

  run "${RALPH_ISSUES_BIN}" 2
  rm -rf "${FAKE_GH_DIR}"

  [ "$status" -eq 0 ]
  [[ "$output" == "Next: #7 Do the thing"* ]]
  [[ "$output" == *"Worktree: ${GIT_FIXTURE_DIR}.ralph-worktrees/issue-7 (branch ralph-issues/issue-7)"* ]]
  [[ "$output" == *"Claimed #7"* ]]
  [ -d "${GIT_FIXTURE_DIR}.ralph-worktrees/issue-7" ]
}

@test "infers the repo from an https git remote" {
  cd "${GIT_FIXTURE_DIR}"
  git remote set-url origin "https://github.com/some-owner/some-repo.git"
  setup_fake_gh "some-owner/some-repo" 7 \
    '[{"number":9,"state":"open","blocked_by":0,"assignees":[]}]' \
    9 "Another thing"

  run "${RALPH_ISSUES_BIN}" 7
  rm -rf "${FAKE_GH_DIR}"

  [ "$status" -eq 0 ]
  [[ "$output" == "Next: #9 Another thing"* ]]
  [ -d "${GIT_FIXTURE_DIR}.ralph-worktrees/issue-9" ]
}

@test "accepts a --repo override instead of inferring from git remote" {
  cd "${GIT_FIXTURE_DIR}"
  setup_fake_gh "other-owner/other-repo" 2 \
    '[{"number":3,"state":"open","blocked_by":0,"assignees":[]}]' \
    3 "Third thing"

  run "${RALPH_ISSUES_BIN}" 2 --repo other-owner/other-repo
  rm -rf "${FAKE_GH_DIR}"

  [ "$status" -eq 0 ]
  [[ "$output" == "Next: #3 Third thing"* ]]
  [ -d "${GIT_FIXTURE_DIR}.ralph-worktrees/issue-3" ]
}

@test "running again while the sub-issue is still assigned does not re-claim or create a second worktree" {
  cd "${GIT_FIXTURE_DIR}"
  # Simulates a second run's frontier-input: gh now reports the sub-issue as
  # already assigned, so it must never reach `title`, worktree creation, or
  # `claim` (the fake gh below has no case for any of those and would fail
  # the test if called).
  FAKE_GH_DIR="$(mktemp -d)"
  cat >"${FAKE_GH_DIR}/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  "api repos/some-owner/some-repo/issues/2/sub_issues --jq"*)
    echo '[{"number":7,"state":"open","blocked_by":0,"assignees":["some-owner"]}]'
    ;;
  *)
    echo "fake gh: unhandled invocation: $*" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "${FAKE_GH_DIR}/gh"
  PATH="${FAKE_GH_DIR}:${PATH}"

  run "${RALPH_ISSUES_BIN}" 2
  rm -rf "${FAKE_GH_DIR}"

  [ "$status" -eq 0 ]
  [ "$output" = "No ready sub-issue for parent #2 in some-owner/some-repo (all sub-issues are blocked, assigned, or none exist)." ]
  [ ! -d "${GIT_FIXTURE_DIR}.ralph-worktrees/issue-7" ]
}

@test "prints a clear message when no sub-issue is ready" {
  cd "${GIT_FIXTURE_DIR}"
  FAKE_GH_DIR="$(mktemp -d)"
  cat >"${FAKE_GH_DIR}/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  "api repos/some-owner/some-repo/issues/2/sub_issues --jq"*)
    echo '[{"number":7,"state":"open","blocked_by":1,"assignees":[]}]'
    ;;
  *)
    echo "fake gh: unhandled invocation: $*" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "${FAKE_GH_DIR}/gh"
  PATH="${FAKE_GH_DIR}:${PATH}"

  run "${RALPH_ISSUES_BIN}" 2
  rm -rf "${FAKE_GH_DIR}"

  [ "$status" -eq 0 ]
  [ "$output" = "No ready sub-issue for parent #2 in some-owner/some-repo (all sub-issues are blocked, assigned, or none exist)." ]
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
