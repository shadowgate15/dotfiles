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
  [ "$output" = "Next: #7 Do the thing" ]
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
  [ "$output" = "Next: #9 Another thing" ]
}

@test "accepts a --repo override instead of inferring from git remote" {
  cd "${GIT_FIXTURE_DIR}"
  setup_fake_gh "other-owner/other-repo" 2 \
    '[{"number":3,"state":"open","blocked_by":0,"assignees":[]}]' \
    3 "Third thing"

  run "${RALPH_ISSUES_BIN}" 2 --repo other-owner/other-repo
  rm -rf "${FAKE_GH_DIR}"

  [ "$status" -eq 0 ]
  [ "$output" = "Next: #3 Third thing" ]
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
