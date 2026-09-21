#!/usr/bin/env bats

setup() {
  GITHUB_ADAPTER="${BATS_TEST_DIRNAME}/../lib/github-adapter"
}

# Pure parsing helpers: no `gh` call involved, sourced directly.

@test "checklist_candidate_numbers: extracts issue numbers from checklist lines in order, deduped" {
  run bash -c 'source "$1"; checklist_candidate_numbers "$2"' _ "${GITHUB_ADAPTER}" \
'Some intro text, not a checklist line, mentions #99.

- [ ] #7 do the thing
- [x] Some title #5
- [ ] #7 duplicate
'

  [ "$status" -eq 0 ]
  [ "$output" = $'7\n5' ]
}

@test "checklist_candidate_numbers: returns nothing for a body with no checklist lines" {
  run bash -c 'source "$1"; checklist_candidate_numbers "$2"' _ "${GITHUB_ADAPTER}" \
'Just a description, no checklist here. #3 is mentioned but not in a checklist item.'

  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "blocked_by_numbers_from_body: extracts blocker numbers from a 'Blocked by:' line" {
  run bash -c 'source "$1"; blocked_by_numbers_from_body "$2"' _ "${GITHUB_ADAPTER}" \
'Part of #11
Blocked by: #4, #6

Body text.'

  [ "$status" -eq 0 ]
  [ "$output" = $'4\n6' ]
}

@test "blocked_by_numbers_from_body: returns nothing when there is no 'Blocked by:' line" {
  run bash -c 'source "$1"; blocked_by_numbers_from_body "$2"' _ "${GITHUB_ADAPTER}" \
'Part of #11

Body text with no blockers.'

  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

# frontier-input: native shape, gh mocked.

@test "frontier-input: builds the native shape from gh sub_issues data" {
  FAKE_GH_DIR="$(mktemp -d)"
  cat >"${FAKE_GH_DIR}/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  "api repos/some-owner/some-repo/issues/11/sub_issues --jq"*)
    echo '[{"number":5,"state":"closed","blocked_by":0,"assignees":[],"labels":[]},{"number":6,"state":"open","blocked_by":1,"assignees":[],"labels":["ready-for-agent"]},{"number":7,"state":"open","blocked_by":0,"assignees":[],"labels":[]}]'
    ;;
  *)
    echo "fake gh: unhandled invocation: $*" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "${FAKE_GH_DIR}/gh"

  PATH="${FAKE_GH_DIR}:${PATH}" run "${GITHUB_ADAPTER}" frontier-input some-owner/some-repo 11
  rm -rf "${FAKE_GH_DIR}"

  [ "$status" -eq 0 ]
  [ "$output" = '{"shape":"native","sub_issues":[{"number":6,"blocked_by":1,"assignees":[],"labels":["ready-for-agent"]},{"number":7,"blocked_by":0,"assignees":[],"labels":[]}]}' ]
}

# frontier-input: checklist fallback shape, gh mocked.

@test "frontier-input: falls back to the checklist shape when no native sub-issues exist" {
  FAKE_GH_DIR="$(mktemp -d)"
  cat >"${FAKE_GH_DIR}/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  "api repos/some-owner/some-repo/issues/11/sub_issues --jq"*)
    echo '[]'
    ;;
  "issue view 11 --repo some-owner/some-repo --json body --jq"*)
    printf '%s\n' '- [ ] #13' '- [ ] #12'
    ;;
  "issue view 13 --repo some-owner/some-repo --json body,state,assignees,labels --jq"*)
    echo '{"body":"Part of #11\nBlocked by: #12","state":"OPEN","assignees":[],"labels":["ready-for-agent"]}'
    ;;
  "issue view 12 --repo some-owner/some-repo --json body,state,assignees,labels --jq"*)
    echo '{"body":"Part of #11","state":"OPEN","assignees":[],"labels":[]}'
    ;;
  *)
    echo "fake gh: unhandled invocation: $*" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "${FAKE_GH_DIR}/gh"

  PATH="${FAKE_GH_DIR}:${PATH}" run "${GITHUB_ADAPTER}" frontier-input some-owner/some-repo 11
  rm -rf "${FAKE_GH_DIR}"

  [ "$status" -eq 0 ]
  [ "$output" = '{"shape":"checklist","checklist_order":[13,12],"issues":{"13":{"blocked_by":[12],"assignees":[],"labels":["ready-for-agent"]},"12":{"blocked_by":[],"assignees":[],"labels":[]}},"open_issues":[13,12]}' ]
}

@test "frontier-input: a closed checklist candidate is excluded from checklist_order" {
  FAKE_GH_DIR="$(mktemp -d)"
  cat >"${FAKE_GH_DIR}/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  "api repos/some-owner/some-repo/issues/11/sub_issues --jq"*)
    echo '[]'
    ;;
  "issue view 11 --repo some-owner/some-repo --json body --jq"*)
    printf '%s\n' '- [ ] #13' '- [ ] #12'
    ;;
  "issue view 13 --repo some-owner/some-repo --json body,state,assignees,labels --jq"*)
    echo '{"body":"Part of #11","state":"CLOSED","assignees":[],"labels":[]}'
    ;;
  "issue view 12 --repo some-owner/some-repo --json body,state,assignees,labels --jq"*)
    echo '{"body":"Part of #11","state":"OPEN","assignees":[],"labels":["ready-for-agent"]}'
    ;;
  *)
    echo "fake gh: unhandled invocation: $*" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "${FAKE_GH_DIR}/gh"

  PATH="${FAKE_GH_DIR}:${PATH}" run "${GITHUB_ADAPTER}" frontier-input some-owner/some-repo 11
  rm -rf "${FAKE_GH_DIR}"

  [ "$status" -eq 0 ]
  [ "$output" = '{"shape":"checklist","checklist_order":[12],"issues":{"12":{"blocked_by":[],"assignees":[],"labels":["ready-for-agent"]}},"open_issues":[12]}' ]
}

@test "frontier-input: a checklist candidate missing the 'Part of #<parent>' marker is excluded" {
  FAKE_GH_DIR="$(mktemp -d)"
  cat >"${FAKE_GH_DIR}/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  "api repos/some-owner/some-repo/issues/11/sub_issues --jq"*)
    echo '[]'
    ;;
  "issue view 11 --repo some-owner/some-repo --json body --jq"*)
    printf '%s\n' '- [ ] #99' '- [ ] #12'
    ;;
  "issue view 99 --repo some-owner/some-repo --json body,state,assignees,labels --jq"*)
    echo '{"body":"Not part of this parent at all.","state":"OPEN","assignees":[],"labels":[]}'
    ;;
  "issue view 12 --repo some-owner/some-repo --json body,state,assignees,labels --jq"*)
    echo '{"body":"Part of #11","state":"OPEN","assignees":[],"labels":["ready-for-agent"]}'
    ;;
  *)
    echo "fake gh: unhandled invocation: $*" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "${FAKE_GH_DIR}/gh"

  PATH="${FAKE_GH_DIR}:${PATH}" run "${GITHUB_ADAPTER}" frontier-input some-owner/some-repo 11
  rm -rf "${FAKE_GH_DIR}"

  [ "$status" -eq 0 ]
  [ "$output" = '{"shape":"checklist","checklist_order":[12],"issues":{"12":{"blocked_by":[],"assignees":[],"labels":["ready-for-agent"]}},"open_issues":[12]}' ]
}

# Remaining operations: assert the exact `gh` invocation each one shells out to.

@test "claim shells out to gh issue edit --add-assignee @me" {
  FAKE_GH_DIR="$(mktemp -d)"
  cat >"${FAKE_GH_DIR}/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $*"
EOF
  chmod +x "${FAKE_GH_DIR}/gh"

  PATH="${FAKE_GH_DIR}:${PATH}" run "${GITHUB_ADAPTER}" claim some-owner/some-repo 4
  rm -rf "${FAKE_GH_DIR}"

  [ "$status" -eq 0 ]
  [ "$output" = "gh issue edit 4 --repo some-owner/some-repo --add-assignee @me" ]
}

@test "comment shells out to gh issue comment --body" {
  FAKE_GH_DIR="$(mktemp -d)"
  cat >"${FAKE_GH_DIR}/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $*"
EOF
  chmod +x "${FAKE_GH_DIR}/gh"

  PATH="${FAKE_GH_DIR}:${PATH}" run "${GITHUB_ADAPTER}" comment some-owner/some-repo 4 "done"
  rm -rf "${FAKE_GH_DIR}"

  [ "$status" -eq 0 ]
  [ "$output" = "gh issue comment 4 --repo some-owner/some-repo --body done" ]
}

@test "close without a comment shells out to gh issue close" {
  FAKE_GH_DIR="$(mktemp -d)"
  cat >"${FAKE_GH_DIR}/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $*"
EOF
  chmod +x "${FAKE_GH_DIR}/gh"

  PATH="${FAKE_GH_DIR}:${PATH}" run "${GITHUB_ADAPTER}" close some-owner/some-repo 4
  rm -rf "${FAKE_GH_DIR}"

  [ "$status" -eq 0 ]
  [ "$output" = "gh issue close 4 --repo some-owner/some-repo" ]
}

@test "close with a comment shells out to gh issue close --comment" {
  FAKE_GH_DIR="$(mktemp -d)"
  cat >"${FAKE_GH_DIR}/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $*"
EOF
  chmod +x "${FAKE_GH_DIR}/gh"

  PATH="${FAKE_GH_DIR}:${PATH}" run "${GITHUB_ADAPTER}" close some-owner/some-repo 4 "all done"
  rm -rf "${FAKE_GH_DIR}"

  [ "$status" -eq 0 ]
  [ "$output" = "gh issue close 4 --repo some-owner/some-repo --comment all done" ]
}

@test "label shells out to gh issue edit --add-label" {
  FAKE_GH_DIR="$(mktemp -d)"
  cat >"${FAKE_GH_DIR}/gh" <<'EOF'
#!/usr/bin/env bash
echo "gh $*"
EOF
  chmod +x "${FAKE_GH_DIR}/gh"

  PATH="${FAKE_GH_DIR}:${PATH}" run "${GITHUB_ADAPTER}" label some-owner/some-repo 4 needs-human
  rm -rf "${FAKE_GH_DIR}"

  [ "$status" -eq 0 ]
  [ "$output" = "gh issue edit 4 --repo some-owner/some-repo --add-label needs-human" ]
}

@test "rejects an unknown subcommand" {
  run "${GITHUB_ADAPTER}" bogus some-owner/some-repo 4

  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown subcommand"* ]]
}
