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

# `claude` is invoked twice per sub-issue: once by implement-attempt (plain
# args) and once by confirmation-attempt (`--json-schema` present) -- the
# latter must report a passing verdict for the pipeline to reach `close`.
# Both invocations request `--output-format json`, so the fake must answer
# with a full result envelope (`total_cost_usd`, and either `result` or
# `structured_output`) for implement-attempt/confirmation-attempt to parse.
# $1: directory to install the fake into
install_fake_claude() {
  cat >"$1/claude" <<'EOF'
#!/usr/bin/env bash
if [[ "$*" == *"--json-schema"* ]]; then
  jq -n '{is_error: false, total_cost_usd: 0.05, usage: {}, structured_output: {verdict: "pass", reason: "fake confirmation pass"}, result: "{\"verdict\":\"pass\",\"reason\":\"fake confirmation pass\"}"}'
else
  jq -n --arg args "$*" '{is_error: false, total_cost_usd: 0.10, usage: {}, result: ("fake claude: " + $args)}'
fi
EOF
  chmod +x "$1/claude"
}

setup_fake_gh() {
  # $1: repo, $2: parent issue, $3: sub_issues JSON while open (native
  #     shape), $4: next issue number, $5: next title
  #
  # Stateful: once `issue close <4>` is called, subsequent `sub_issues`
  # queries report the same entry with state "closed" instead -- mimicking
  # how the real API keeps a closed sub-issue listed (just no longer
  # "open") rather than dropping it, so a single ready sub-issue naturally
  # ends the run on the following iteration instead of being "next" forever.
  FAKE_GH_DIR="$(mktemp -d)"
  local state_file="${FAKE_GH_DIR}/state"
  echo "open" >"${state_file}"
  cat >"${FAKE_GH_DIR}/gh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
case "\$*" in
  "api repos/${1}/issues/${2}/sub_issues --jq"*)
    if [[ "\$(cat "${state_file}")" == "closed" ]]; then
      jq -c 'map(.state = "closed")' <<<'${3}'
    else
      echo '${3}'
    fi
    ;;
  "issue view ${4} --repo ${1} --json title --jq .title")
    echo "${5}"
    ;;
  "issue edit ${4} --repo ${1} --add-assignee @me")
    ;;
  "issue close ${4} --repo ${1} --comment"*)
    echo "closed" >"${state_file}"
    ;;
  *)
    echo "fake gh: unhandled invocation: \$*" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "${FAKE_GH_DIR}/gh"
  install_fake_claude "${FAKE_GH_DIR}"
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
  [[ "$output" == "Now working: #7 Do the thing"* ]]
  [[ "$output" == *"Worktree: ${GIT_FIXTURE_DIR}.ralph-worktrees/issue-7 (branch ralph-issues/issue-7)"* ]]
  [[ "$output" == *"Claimed #7"* ]]
  [[ "$output" == *"fake claude: -p --dangerously-skip-permissions --output-format json /implement Implement issue #7:"* ]]
  [[ "$output" == *"confirmed and closed"* ]]
  [ ! -d "${GIT_FIXTURE_DIR}.ralph-worktrees/issue-7" ]

  # The outer loop recomputes the frontier after #7 closes, finds nothing
  # further ready, and terminates naturally with the run's progress summary.
  [[ "$output" == *"Processed so far:"* ]]
  [[ "$output" == *"#7 Do the thing -- confirmed and closed"* ]]
  [[ "$output" == *"No ready sub-issue for parent #2 in some-owner/some-repo"* ]]
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
  [[ "$output" == "Now working: #9 Another thing"* ]]
  [[ "$output" == *"confirmed and closed"* ]]
}

@test "accepts a --repo override instead of inferring from git remote" {
  cd "${GIT_FIXTURE_DIR}"
  setup_fake_gh "other-owner/other-repo" 2 \
    '[{"number":3,"state":"open","blocked_by":0,"assignees":[]}]' \
    3 "Third thing"

  run "${RALPH_ISSUES_BIN}" 2 --repo other-owner/other-repo
  rm -rf "${FAKE_GH_DIR}"

  [ "$status" -eq 0 ]
  [[ "$output" == "Now working: #3 Third thing"* ]]
  [[ "$output" == *"confirmed and closed"* ]]
}

@test "accepts a --max-attempts override and threads it into the pipeline" {
  cd "${GIT_FIXTURE_DIR}"
  setup_fake_gh "some-owner/some-repo" 2 \
    '[{"number":7,"state":"open","blocked_by":0,"assignees":[]}]' \
    7 "Do the thing"

  run "${RALPH_ISSUES_BIN}" 2 --max-attempts 1

  [ "$status" -eq 0 ]
  [[ "$output" == *"attempt 1/1"* ]]
  [[ "$output" == *"confirmed and closed"* ]]

  rm -rf "${FAKE_GH_DIR}"
}

# $1: phase-tracking file. Two independent, unblocked sub-issues (#7, #8) --
# the fake's `sub_issues` response depends on how many have been closed so
# far (matching the real API, which keeps closed sub-issues listed with
# state "closed" rather than dropping them), so the outer loop's second and
# third frontier-query calls see real state changes instead of the same
# static response forever.
setup_fake_gh_two_sub_issues() {
  FAKE_GH_DIR="$(mktemp -d)"
  local phase_file="${FAKE_GH_DIR}/phase"
  echo 0 >"${phase_file}"
  cat >"${FAKE_GH_DIR}/gh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
phase="\$(cat "${phase_file}")"
case "\$*" in
  "api repos/some-owner/some-repo/issues/2/sub_issues --jq"*)
    case "\${phase}" in
      0) echo '[{"number":7,"state":"open","blocked_by":0,"assignees":[]},{"number":8,"state":"open","blocked_by":0,"assignees":[]}]' ;;
      1) echo '[{"number":7,"state":"closed","blocked_by":0,"assignees":[]},{"number":8,"state":"open","blocked_by":0,"assignees":[]}]' ;;
      *) echo '[{"number":7,"state":"closed","blocked_by":0,"assignees":[]},{"number":8,"state":"closed","blocked_by":0,"assignees":[]}]' ;;
    esac
    ;;
  "issue view 7 --repo some-owner/some-repo --json title --jq .title")
    echo "First thing"
    ;;
  "issue view 8 --repo some-owner/some-repo --json title --jq .title")
    echo "Second thing"
    ;;
  "issue edit 7 --repo some-owner/some-repo --add-assignee @me") ;;
  "issue edit 8 --repo some-owner/some-repo --add-assignee @me") ;;
  "issue close 7 --repo some-owner/some-repo --comment"*)
    echo 1 >"${phase_file}"
    ;;
  "issue close 8 --repo some-owner/some-repo --comment"*)
    echo 2 >"${phase_file}"
    ;;
  *)
    echo "fake gh: unhandled invocation: \$*" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "${FAKE_GH_DIR}/gh"
  install_fake_claude "${FAKE_GH_DIR}"
  PATH="${FAKE_GH_DIR}:${PATH}"
}

@test "processes two ready sub-issues one at a time, in frontier order, then terminates naturally" {
  cd "${GIT_FIXTURE_DIR}"
  setup_fake_gh_two_sub_issues

  run "${RALPH_ISSUES_BIN}" 2
  rm -rf "${FAKE_GH_DIR}"

  [ "$status" -eq 0 ]

  # #7 fully processed (worked, closed) strictly before #8 is ever claimed.
  local first_claimed second_claimed
  first_claimed="$(grep -n "Claimed #7" <<<"${output}" | head -n1 | cut -d: -f1)"
  second_claimed="$(grep -n "Claimed #8" <<<"${output}" | head -n1 | cut -d: -f1)"
  [ -n "${first_claimed}" ]
  [ -n "${second_claimed}" ]
  [ "${first_claimed}" -lt "${second_claimed}" ]

  [[ "$output" == *"Now working: #7 First thing"* ]]
  [[ "$output" == *"Now working: #8 Second thing"* ]]
  [[ "$output" == *"Processed so far:"* ]]
  [[ "$output" == *"#7 First thing -- confirmed and closed"* ]]
  [[ "$output" == *"#8 Second thing -- confirmed and closed"* ]]
  [[ "$output" == *"No ready sub-issue for parent #2 in some-owner/some-repo"* ]]

  [ ! -d "${GIT_FIXTURE_DIR}.ralph-worktrees/issue-7" ]
  [ ! -d "${GIT_FIXTURE_DIR}.ralph-worktrees/issue-8" ]
}

@test "stops cleanly between sub-issues once the wall-clock ceiling is reached" {
  cd "${GIT_FIXTURE_DIR}"
  setup_fake_gh_two_sub_issues

  run "${RALPH_ISSUES_BIN}" 2 --max-minutes 0
  rm -rf "${FAKE_GH_DIR}"

  [ "$status" -eq 0 ]
  [[ "$output" == *"stopping -- whole-run wall-clock ceiling of 0 minute(s) reached"* ]]
  # Ceiling is checked before starting *any* sub-issue -- never mid-attempt.
  [[ "$output" != *"Claimed #7"* ]]
  [[ "$output" != *"Claimed #8"* ]]
}

@test "rejects a non-numeric --max-minutes value" {
  cd "${GIT_FIXTURE_DIR}"
  run "${RALPH_ISSUES_BIN}" 2 --max-minutes not-a-number

  [ "$status" -ne 0 ]
  [[ "$output" == *"max-minutes"* ]]
}

@test "rejects a --max-minutes value with a leading zero" {
  cd "${GIT_FIXTURE_DIR}"
  # A leading-zero literal (e.g. "010") is octal in bash arithmetic, which
  # would silently misinterpret this ceiling (or, for a digit like 8/9,
  # abort with an uncaught "value too great for base" error) -- reject it
  # at validation instead.
  run "${RALPH_ISSUES_BIN}" 2 --max-minutes 010

  [ "$status" -ne 0 ]
  [[ "$output" == *"max-minutes"* ]]
}

@test "rejects --max-budget-usd as an unknown option" {
  cd "${GIT_FIXTURE_DIR}"
  run "${RALPH_ISSUES_BIN}" 2 --max-budget-usd 20

  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown option"* ]]
}

@test "rejects a non-numeric --max-attempts value" {
  cd "${GIT_FIXTURE_DIR}"
  run "${RALPH_ISSUES_BIN}" 2 --max-attempts not-a-number

  [ "$status" -ne 0 ]
  [[ "$output" == *"max-attempts"* ]]
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
