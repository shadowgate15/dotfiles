#!/usr/bin/env bats

setup() {
  PIPELINE="${BATS_TEST_DIRNAME}/../lib/sub-issue-pipeline"
  WORKTREE="${BATS_TEST_DIRNAME}/../lib/worktree"

  GIT_FIXTURE_DIR="$(cd "$(mktemp -d)" && pwd -P)/some-repo"
  mkdir -p "${GIT_FIXTURE_DIR}"
  git -C "${GIT_FIXTURE_DIR}" init -q
  git -C "${GIT_FIXTURE_DIR}" config user.email "test@example.com"
  git -C "${GIT_FIXTURE_DIR}" config user.name "Test"
  echo "base" >"${GIT_FIXTURE_DIR}/file.txt"
  git -C "${GIT_FIXTURE_DIR}" add file.txt
  git -C "${GIT_FIXTURE_DIR}" commit -q -m "initial commit"
  BASE_REF="$(git -C "${GIT_FIXTURE_DIR}" rev-parse HEAD)"
}

teardown() {
  git -C "${GIT_FIXTURE_DIR}" worktree list --porcelain 2>/dev/null \
    | awk '/^worktree /{print $2}' \
    | tail -n +2 \
    | xargs -I{} rm -rf {}
  rm -rf "$(dirname "${GIT_FIXTURE_DIR}")"
}

# Pure helpers: no claude/gh/git call involved, sourced directly.

@test "build_close_comment: names the attempt count and includes the confirmation output" {
  run bash -c 'source "$1"; build_close_comment "$2" "$3" "$4"' _ "${PIPELINE}" 2 3 "Confirmation: PASS -- all good"

  [ "$status" -eq 0 ]
  [[ "$output" == *"attempt 2/3"* ]]
  [[ "$output" == *"Confirmation: PASS -- all good"* ]]
}

@test "build_escalation_comment: names the attempt ceiling and includes the last verdict" {
  run bash -c 'source "$1"; build_escalation_comment "$2" "$3" "$4"' _ "${PIPELINE}" 7 3 "Confirmation: FAIL -- one test failing"

  [ "$status" -eq 0 ]
  [[ "$output" == *"exhausted 3 attempt(s)"* ]]
  [[ "$output" == *"Confirmation: FAIL -- one test failing"* ]]
  [[ "$output" == *"left in place for human follow-up"* ]]
}

@test "extract_cost: pulls the last COST_USD line out of attempt output, defaulting to 0" {
  run bash -c 'source "$1"; extract_cost "$2"' _ "${PIPELINE}" "$(printf 'some text\nCOST_USD=0.1234\nmore text')"
  [ "$status" -eq 0 ]
  [ "$output" = "0.1234" ]

  run bash -c 'source "$1"; extract_cost "$2"' _ "${PIPELINE}" "no cost line here"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "strip_cost_line: removes COST_USD lines, leaving the rest intact" {
  run bash -c 'source "$1"; strip_cost_line "$2"' _ "${PIPELINE}" "$(printf 'Confirmation: PASS -- all good\nCOST_USD=0.05')"
  [ "$status" -eq 0 ]
  [ "$output" = "Confirmation: PASS -- all good" ]
}

@test "sum_costs: adds dollar amounts together" {
  run bash -c 'source "$1"; sum_costs "$2" "$3" "$4"' _ "${PIPELINE}" 0.1 0.02 0.003
  [ "$status" -eq 0 ]
  [ "$output" = "0.123000" ]
}

# Integration-shaped tests: real git worktrees/branches, faked `claude` and
# `gh` so no real headless session or tracker call happens.

# $1: dir to write the fakes into
# $2: newline-separated confirmation verdict JSON bodies, one per attempt
setup_fakes() {
  local fakes_dir="$1" verdicts="$2"
  mkdir -p "${fakes_dir}"

  printf '%s\n' "${verdicts}" >"${fakes_dir}/verdicts.txt"
  : >"${fakes_dir}/confirm-count.txt"
  : >"${fakes_dir}/gh.log"

  cat >"${fakes_dir}/claude" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\$*" == *"--json-schema"* ]]; then
  n=\$(( \$(cat "${fakes_dir}/confirm-count.txt") + 1 ))
  echo "\${n}" >"${fakes_dir}/confirm-count.txt"
  structured="\$(sed -n "\${n}p" "${fakes_dir}/verdicts.txt")"
  jq -n --argjson structured_output "\${structured}" \
    '{is_error: false, total_cost_usd: 0.05, usage: {}, structured_output: \$structured_output, result: (\$structured_output | tojson)}'
else
  echo "implemented" >>file.txt
  git add -A
  git commit -q -m "implement attempt commit"
  jq -n '{is_error: false, total_cost_usd: 0.10, usage: {}, result: "implemented"}'
fi
EOF
  chmod +x "${fakes_dir}/claude"

  cat >"${fakes_dir}/gh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
echo "gh \$*" >>"${fakes_dir}/gh.log"
case "\$*" in
  "issue close "*"--comment"*) ;;
  "issue comment "*"--body"*) ;;
  "issue edit "*"--add-label"*) ;;
  *)
    echo "fake gh: unhandled invocation: \$*" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "${fakes_dir}/gh"
}

@test "run: pass on the first attempt merges into the integration branch, discards the worktree, and closes with a comment" {
  local worktree_dir
  worktree_dir="$("${WORKTREE}" create "${GIT_FIXTURE_DIR}" 7 "${BASE_REF}")"

  FAKES_DIR="$(mktemp -d)"
  setup_fakes "${FAKES_DIR}" '{"verdict":"pass","reason":"tests and typecheck green"}'

  PATH="${FAKES_DIR}:${PATH}" run "${PIPELINE}" run "${GIT_FIXTURE_DIR}" "${worktree_dir}" "${BASE_REF}" \
    some-owner/some-repo 1 7 "Add the frobnicator" 3

  [ "$status" -eq 0 ]
  [[ "$output" == *"attempt 1/3"* ]]
  [[ "$output" == *"confirmed and closed"* ]]
  [[ "$output" == *"ralph-issues/parent-1-integration"* ]]
  [[ "$output" == *"SUBISSUE_COST_USD=0.150000"* ]]

  # Worktree discarded, branch left alone.
  [ ! -d "${worktree_dir}" ]
  run git -C "${GIT_FIXTURE_DIR}" show-ref --verify --quiet "refs/heads/ralph-issues/issue-7"
  [ "$status" -eq 0 ]

  # Merged into the integration branch.
  local integration_path
  integration_path="$("${WORKTREE}" integration-path "${GIT_FIXTURE_DIR}" 1)"
  [ -d "${integration_path}" ]
  [ "$(cat "${integration_path}/file.txt" | tail -n1)" = "implemented" ]

  # Closed via the adapter with a comment, never before this point.
  grep -q "issue close 7 --repo some-owner/some-repo --comment" "${FAKES_DIR}/gh.log"

  rm -rf "${FAKES_DIR}"
}

@test "run: a failing first attempt retries in the same worktree and succeeds on the second" {
  local worktree_dir
  worktree_dir="$("${WORKTREE}" create "${GIT_FIXTURE_DIR}" 8 "${BASE_REF}")"

  FAKES_DIR="$(mktemp -d)"
  setup_fakes "${FAKES_DIR}" "$(printf '%s\n%s' \
    '{"verdict":"fail","reason":"one test failing"}' \
    '{"verdict":"pass","reason":"now green"}')"

  PATH="${FAKES_DIR}:${PATH}" run "${PIPELINE}" run "${GIT_FIXTURE_DIR}" "${worktree_dir}" "${BASE_REF}" \
    some-owner/some-repo 1 8 "Add the frobnicator" 3

  [ "$status" -eq 0 ]
  [[ "$output" == *"attempt 1/3"* ]]
  [[ "$output" == *"attempt 2/3"* ]]
  [[ "$output" == *"Confirmation: FAIL -- one test failing"* ]]
  [[ "$output" == *"confirmed and closed"* ]]
  [[ "$output" == *"SUBISSUE_COST_USD=0.300000"* ]]

  # Two implement commits landed in the same, reused worktree branch.
  [ "$(git -C "${GIT_FIXTURE_DIR}" log --oneline "ralph-issues/issue-8" | grep -c "implement attempt commit")" -eq 2 ]

  grep -q "issue close 8" "${FAKES_DIR}/gh.log"
  ! grep -q "add-label" "${FAKES_DIR}/gh.log"

  rm -rf "${FAKES_DIR}"
}

@test "run: exhausting the retry ceiling labels for human follow-up and preserves the worktree and branch" {
  local worktree_dir
  worktree_dir="$("${WORKTREE}" create "${GIT_FIXTURE_DIR}" 9 "${BASE_REF}")"

  FAKES_DIR="$(mktemp -d)"
  setup_fakes "${FAKES_DIR}" "$(printf '%s\n%s\n%s' \
    '{"verdict":"fail","reason":"still broken 1"}' \
    '{"verdict":"fail","reason":"still broken 2"}' \
    '{"verdict":"fail","reason":"still broken 3"}')"

  PATH="${FAKES_DIR}:${PATH}" run "${PIPELINE}" run "${GIT_FIXTURE_DIR}" "${worktree_dir}" "${BASE_REF}" \
    some-owner/some-repo 1 9 "Add the frobnicator" 3

  [ "$status" -eq 1 ]
  [[ "$output" == *"attempt 1/3"* ]]
  [[ "$output" == *"attempt 2/3"* ]]
  [[ "$output" == *"attempt 3/3"* ]]
  [[ "$output" == *"escalated for human follow-up after 3 attempt(s)"* ]]
  [[ "$output" == *"SUBISSUE_COST_USD=0.450000"* ]]

  # Worktree and branch both preserved.
  [ -d "${worktree_dir}" ]
  run git -C "${GIT_FIXTURE_DIR}" show-ref --verify --quiet "refs/heads/ralph-issues/issue-9"
  [ "$status" -eq 0 ]

  # Never closed, never merged -- labeled and commented instead.
  ! grep -q "issue close" "${FAKES_DIR}/gh.log"
  grep -q "issue comment 9 --repo some-owner/some-repo --body" "${FAKES_DIR}/gh.log"
  grep -q "issue edit 9 --repo some-owner/some-repo --add-label needs-human" "${FAKES_DIR}/gh.log"

  local integration_path
  integration_path="$("${WORKTREE}" integration-path "${GIT_FIXTURE_DIR}" 1)"
  [ ! -d "${integration_path}" ]

  rm -rf "${FAKES_DIR}"
}

@test "run: a merge conflict against the integration branch fails loudly without closing or discarding" {
  local worktree_dir
  worktree_dir="$("${WORKTREE}" create "${GIT_FIXTURE_DIR}" 10 "${BASE_REF}")"

  local integration_path
  integration_path="$("${WORKTREE}" create-integration "${GIT_FIXTURE_DIR}" 1 "${BASE_REF}")"
  echo "integration-side edit" >"${integration_path}/file.txt"
  git -C "${integration_path}" commit -aqm "integration edit"

  FAKES_DIR="$(mktemp -d)"
  setup_fakes "${FAKES_DIR}" '{"verdict":"pass","reason":"looks good"}'
  # Conflict with the integration branch's edit to the same line, instead of
  # the fake's default append-only change.
  cat >"${FAKES_DIR}/claude" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\$*" == *"--json-schema"* ]]; then
  n=\$(( \$(cat "${FAKES_DIR}/confirm-count.txt") + 1 ))
  echo "\${n}" >"${FAKES_DIR}/confirm-count.txt"
  structured="\$(sed -n "\${n}p" "${FAKES_DIR}/verdicts.txt")"
  jq -n --argjson structured_output "\${structured}" \
    '{is_error: false, total_cost_usd: 0.05, usage: {}, structured_output: \$structured_output, result: (\$structured_output | tojson)}'
else
  echo "sub-issue-side edit" >file.txt
  git commit -aqm "implement attempt commit"
  jq -n '{is_error: false, total_cost_usd: 0.10, usage: {}, result: "implemented"}'
fi
EOF
  chmod +x "${FAKES_DIR}/claude"

  PATH="${FAKES_DIR}:${PATH}" run "${PIPELINE}" run "${GIT_FIXTURE_DIR}" "${worktree_dir}" "${BASE_REF}" \
    some-owner/some-repo 1 10 "Add the frobnicator" 3

  [ "$status" -ne 0 ]
  [[ "$output" == *"merging"*"failed"* ]]

  # Left in place for manual resolution, never closed.
  [ -d "${worktree_dir}" ]
  ! grep -q "issue close" "${FAKES_DIR}/gh.log"

  git -C "${integration_path}" merge --abort 2>/dev/null || true
  rm -rf "${FAKES_DIR}"
}

@test "run: rejects a non-numeric max-attempts value" {
  local worktree_dir
  worktree_dir="$("${WORKTREE}" create "${GIT_FIXTURE_DIR}" 11 "${BASE_REF}")"

  run "${PIPELINE}" run "${GIT_FIXTURE_DIR}" "${worktree_dir}" "${BASE_REF}" some-owner/some-repo 1 11 "Some title" not-a-number

  [ "$status" -ne 0 ]
  [[ "$output" == *"max-attempts"* ]]
}

@test "run: fails clearly when the worktree directory does not exist" {
  run "${PIPELINE}" run "${GIT_FIXTURE_DIR}" /no/such/worktree-dir "${BASE_REF}" some-owner/some-repo 1 12 "Some title"

  [ "$status" -ne 0 ]
  [[ "$output" == *"worktree directory"* ]]
}

@test "rejects an unknown subcommand" {
  run "${PIPELINE}" bogus "${GIT_FIXTURE_DIR}" /tmp some-owner/some-repo 1 12 "Some title"

  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown subcommand"* ]]
}
