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
  "issue edit ${4} --repo ${1} --remove-label ready-for-agent")
    ;;
  "issue edit ${4} --repo ${1} --remove-label ready-for-human")
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
    '[{"number":7,"state":"open","blocked_by":0,"assignees":[],"labels":["ready-for-agent"]}]' \
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
    '[{"number":9,"state":"open","blocked_by":0,"assignees":[],"labels":["ready-for-agent"]}]' \
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
    '[{"number":3,"state":"open","blocked_by":0,"assignees":[],"labels":["ready-for-agent"]}]' \
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
    '[{"number":7,"state":"open","blocked_by":0,"assignees":[],"labels":["ready-for-agent"]}]' \
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
      0) echo '[{"number":7,"state":"open","blocked_by":0,"assignees":[],"labels":["ready-for-agent"]},{"number":8,"state":"open","blocked_by":0,"assignees":[],"labels":["ready-for-agent"]}]' ;;
      1) echo '[{"number":7,"state":"closed","blocked_by":0,"assignees":[],"labels":["ready-for-agent"]},{"number":8,"state":"open","blocked_by":0,"assignees":[],"labels":["ready-for-agent"]}]' ;;
      *) echo '[{"number":7,"state":"closed","blocked_by":0,"assignees":[],"labels":["ready-for-agent"]},{"number":8,"state":"closed","blocked_by":0,"assignees":[],"labels":["ready-for-agent"]}]' ;;
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
  "issue edit 7 --repo some-owner/some-repo --remove-label ready-for-agent") ;;
  "issue edit 8 --repo some-owner/some-repo --remove-label ready-for-agent") ;;
  "issue edit 7 --repo some-owner/some-repo --remove-label ready-for-human") ;;
  "issue edit 8 --repo some-owner/some-repo --remove-label ready-for-human") ;;
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

# Claim strips both poles, and the outer loop backstops any non-zero
# pipeline exit -- including a stubbed crash before the pipeline's own
# escalation code runs -- to unassigned + ready-for-human.

# $1: repo, $2: parent issue, $3: next issue number, $4: next title,
# $5: log file every matched gh invocation is appended to.
#
# Stateful: the sub_issues response reflects whatever assignment/labels have
# actually been applied so far, rather than a static fixture -- otherwise
# the outer loop would see the same "still ready" issue forever and loop.
setup_fake_gh_logging() {
  FAKE_GH_DIR="$(mktemp -d)"
  local assignee_file="${FAKE_GH_DIR}/assignee" labels_file="${FAKE_GH_DIR}/labels"
  : >"$5"
  : >"${assignee_file}"
  echo "ready-for-agent" >"${labels_file}"
  cat >"${FAKE_GH_DIR}/gh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
echo "gh \$*" >>"$5"
case "\$*" in
  "api repos/${1}/issues/${2}/sub_issues --jq"*)
    assignees_json="[]"
    [[ -s "${assignee_file}" ]] && assignees_json='["some-owner"]'
    labels_json="\$(jq -R -s -c 'split("\n") | map(select(length > 0))' <"${labels_file}")"
    jq -n --argjson assignees "\${assignees_json}" --argjson labels "\${labels_json}" \
      '[{number: ${3}, state: "open", blocked_by: 0, assignees: \$assignees, labels: \$labels}]'
    ;;
  "issue view ${3} --repo ${1} --json title --jq .title")
    echo "${4}"
    ;;
  "issue edit ${3} --repo ${1} --add-assignee @me")
    echo "assigned" >"${assignee_file}"
    ;;
  "issue edit ${3} --repo ${1} --remove-assignee @me")
    : >"${assignee_file}"
    ;;
  "issue edit ${3} --repo ${1} --remove-label ready-for-agent")
    grep -v '^ready-for-agent\$' "${labels_file}" >"${labels_file}.tmp" || true
    mv "${labels_file}.tmp" "${labels_file}"
    ;;
  "issue edit ${3} --repo ${1} --remove-label ready-for-human")
    grep -v '^ready-for-human\$' "${labels_file}" >"${labels_file}.tmp" || true
    mv "${labels_file}.tmp" "${labels_file}"
    ;;
  "label create ready-for-human --repo ${1} --force") ;;
  "issue edit ${3} --repo ${1} --add-label ready-for-human")
    echo "ready-for-human" >>"${labels_file}"
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

@test "claim defensively strips both ready-for-agent and ready-for-human right after assigning" {
  cd "${GIT_FIXTURE_DIR}"
  local gh_log="${BATS_TEST_TMPDIR}/gh.log"
  setup_fake_gh_logging "some-owner/some-repo" 2 7 "Do the thing" "${gh_log}"
  install_fake_claude "${FAKE_GH_DIR}"

  local assign_line strip_agent_line strip_human_line
  # The claim-strip happens unconditionally, before the pipeline is even
  # invoked -- a stub that immediately fails is enough to isolate that
  # ordering from the separate give-up backstop covered below, without
  # needing to fake a real merge into an integration branch.
  cat >"${BATS_TEST_TMPDIR}/stub-pipeline" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "${BATS_TEST_TMPDIR}/stub-pipeline"

  SUB_ISSUE_PIPELINE="${BATS_TEST_TMPDIR}/stub-pipeline" run "${RALPH_ISSUES_BIN}" 2
  rm -rf "${FAKE_GH_DIR}"

  [ "$status" -eq 0 ]

  assign_line="$(grep -n "issue edit 7 --repo some-owner/some-repo --add-assignee @me" "${gh_log}" | head -n1 | cut -d: -f1)"
  strip_agent_line="$(grep -n "issue edit 7 --repo some-owner/some-repo --remove-label ready-for-agent" "${gh_log}" | head -n1 | cut -d: -f1)"
  strip_human_line="$(grep -n "issue edit 7 --repo some-owner/some-repo --remove-label ready-for-human" "${gh_log}" | head -n1 | cut -d: -f1)"

  [ -n "${assign_line}" ]
  [ -n "${strip_agent_line}" ]
  [ -n "${strip_human_line}" ]
  [ "${assign_line}" -lt "${strip_agent_line}" ]
  [ "${assign_line}" -lt "${strip_human_line}" ]
}

@test "a successful pipeline run never triggers the give-up backstop" {
  cd "${GIT_FIXTURE_DIR}"
  local gh_log="${BATS_TEST_TMPDIR}/gh.log"
  setup_fake_gh_logging "some-owner/some-repo" 2 7 "Do the thing" "${gh_log}"
  install_fake_claude "${FAKE_GH_DIR}"

  # A stub pipeline that succeeds without ever calling `gh close` -- the
  # fake gh's strict catch-all (exit 1 on any unhandled invocation) would
  # fail this test outright if the backstop fired and tried to unclaim or
  # relabel on a successful run. It still has to create the integration
  # branch itself (via the real lib/worktree), matching what the real
  # pipeline does on a pass, since the outer loop reads that branch
  # afterwards regardless of what stubbed it.
  local worktree_bin="${BATS_TEST_DIRNAME}/../lib/worktree"
  # Args, per bin/ralph-issues's invocation: run repo-root worktree-dir
  # base-ref repo parent-issue issue-number title [max-attempts].
  cat >"${BATS_TEST_TMPDIR}/stub-pipeline" <<EOF
#!/usr/bin/env bash
set -euo pipefail
"${worktree_bin}" create-integration "\${2}" "\${6}" "\${4}" >/dev/null
exit 0
EOF
  chmod +x "${BATS_TEST_TMPDIR}/stub-pipeline"

  SUB_ISSUE_PIPELINE="${BATS_TEST_TMPDIR}/stub-pipeline" run "${RALPH_ISSUES_BIN}" 2
  rm -rf "${FAKE_GH_DIR}"

  [ "$status" -eq 0 ]
  ! grep -q "remove-assignee" "${gh_log}"
  ! grep -q "add-label ready-for-human" "${gh_log}"
}

@test "any non-zero pipeline exit backstops to unassigned + ready-for-human, even a pipeline stubbed to crash before its own escalation code" {
  cd "${GIT_FIXTURE_DIR}"
  local gh_log="${BATS_TEST_TMPDIR}/gh.log"
  setup_fake_gh_logging "some-owner/some-repo" 2 7 "Do the thing" "${gh_log}"
  install_fake_claude "${FAKE_GH_DIR}"

  # Simulates a crash before the pipeline's own escalation path (comment,
  # unlabel/label, unclaim) ever runs -- it does nothing but exit non-zero.
  cat >"${BATS_TEST_TMPDIR}/crashing-pipeline" <<'EOF'
#!/usr/bin/env bash
echo "boom: simulated crash before escalation code" >&2
exit 1
EOF
  chmod +x "${BATS_TEST_TMPDIR}/crashing-pipeline"

  SUB_ISSUE_PIPELINE="${BATS_TEST_TMPDIR}/crashing-pipeline" run "${RALPH_ISSUES_BIN}" 2
  rm -rf "${FAKE_GH_DIR}"

  [ "$status" -eq 0 ]
  [[ "$output" == *"escalated for human follow-up"* ]]

  grep -q "issue edit 7 --repo some-owner/some-repo --remove-assignee @me" "${gh_log}"
  grep -q "issue edit 7 --repo some-owner/some-repo --add-label ready-for-human" "${gh_log}"

  # Never closed -- the crash happened before any confirmation could pass.
  ! grep -q "issue close" "${gh_log}"
}
