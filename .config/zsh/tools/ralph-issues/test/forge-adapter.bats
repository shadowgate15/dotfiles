#!/usr/bin/env bats

setup() {
  FORGE_ADAPTER="${BATS_TEST_DIRNAME}/../lib/forge-adapter"
  FRONTIER_QUERY="${BATS_TEST_DIRNAME}/../lib/frontier-query"
}

# frontier-input: native shape, forge mocked.

@test "frontier-input: builds the native shape from forge task list data" {
  FAKE_FORGE_DIR="$(mktemp -d)"
  cat >"${FAKE_FORGE_DIR}/forge" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  "task list --parent 11 --json=id,title,status,labels,assignee,blocked_by")
    echo '[
      {"id":5,"title":"closed one","status":"closed","labels":[],"assignee":null,"blocked_by":[]},
      {"id":6,"title":"blocked one","status":"open","labels":["ready-for-agent"],"assignee":null,"blocked_by":[{"id":9,"status":"open","title":"blocker"},{"id":10,"status":"closed","title":"old blocker"}]},
      {"id":7,"title":"ready one","status":"open","labels":[],"assignee":"alice","blocked_by":[]}
    ]'
    ;;
  *)
    echo "fake forge: unhandled invocation: $*" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "${FAKE_FORGE_DIR}/forge"

  PATH="${FAKE_FORGE_DIR}:${PATH}" run "${FORGE_ADAPTER}" frontier-input ignored-scope 11
  rm -rf "${FAKE_FORGE_DIR}"

  [ "$status" -eq 0 ]
  [ "$output" = '{"shape":"native","sub_issues":[{"number":6,"blocked_by":1,"assignees":[],"labels":["ready-for-agent"]},{"number":7,"blocked_by":0,"assignees":["alice"],"labels":[]}]}' ]
}

@test "frontier-input: composes with lib/frontier-query to pick the next ready sub-issue" {
  FAKE_FORGE_DIR="$(mktemp -d)"
  cat >"${FAKE_FORGE_DIR}/forge" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  "task list --parent 11 --json=id,title,status,labels,assignee,blocked_by")
    echo '[
      {"id":6,"title":"blocked one","status":"open","labels":["ready-for-agent"],"assignee":null,"blocked_by":[{"id":9,"status":"open","title":"blocker"}]},
      {"id":7,"title":"ready one","status":"open","labels":["ready-for-agent"],"assignee":null,"blocked_by":[]}
    ]'
    ;;
  *)
    echo "fake forge: unhandled invocation: $*" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "${FAKE_FORGE_DIR}/forge"

  PATH="${FAKE_FORGE_DIR}:${PATH}" run bash -c '"$1" frontier-input ignored-scope 11 | "$2"' _ "${FORGE_ADAPTER}" "${FRONTIER_QUERY}"
  rm -rf "${FAKE_FORGE_DIR}"

  [ "$status" -eq 0 ]
  [ "$output" = '{"next":7}' ]
}

# Remaining operations: assert the exact `forge` invocation each one shells out to.

@test "title prints a task's title via forge task view --json=title" {
  FAKE_FORGE_DIR="$(mktemp -d)"
  cat >"${FAKE_FORGE_DIR}/forge" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "task view 4 --json=title")
    echo '{"title":"Do the thing"}'
    ;;
  *)
    echo "fake forge: unhandled invocation: $*" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "${FAKE_FORGE_DIR}/forge"

  PATH="${FAKE_FORGE_DIR}:${PATH}" run "${FORGE_ADAPTER}" title ignored-scope 4
  rm -rf "${FAKE_FORGE_DIR}"

  [ "$status" -eq 0 ]
  [ "$output" = "Do the thing" ]
}

@test "claim shells out to forge task claim with no --force" {
  FAKE_FORGE_DIR="$(mktemp -d)"
  cat >"${FAKE_FORGE_DIR}/forge" <<'EOF'
#!/usr/bin/env bash
echo "forge $*"
EOF
  chmod +x "${FAKE_FORGE_DIR}/forge"

  PATH="${FAKE_FORGE_DIR}:${PATH}" run "${FORGE_ADAPTER}" claim ignored-scope 4
  rm -rf "${FAKE_FORGE_DIR}"

  [ "$status" -eq 0 ]
  [ "$output" = "forge task claim 4" ]
}

@test "unclaim shells out to forge task release" {
  FAKE_FORGE_DIR="$(mktemp -d)"
  cat >"${FAKE_FORGE_DIR}/forge" <<'EOF'
#!/usr/bin/env bash
echo "forge $*"
EOF
  chmod +x "${FAKE_FORGE_DIR}/forge"

  PATH="${FAKE_FORGE_DIR}:${PATH}" run "${FORGE_ADAPTER}" unclaim ignored-scope 4
  rm -rf "${FAKE_FORGE_DIR}"

  [ "$status" -eq 0 ]
  [ "$output" = "forge task release 4" ]
}

@test "comment shells out to forge task comment" {
  FAKE_FORGE_DIR="$(mktemp -d)"
  cat >"${FAKE_FORGE_DIR}/forge" <<'EOF'
#!/usr/bin/env bash
echo "forge $*"
EOF
  chmod +x "${FAKE_FORGE_DIR}/forge"

  PATH="${FAKE_FORGE_DIR}:${PATH}" run "${FORGE_ADAPTER}" comment ignored-scope 4 "done"
  rm -rf "${FAKE_FORGE_DIR}"

  [ "$status" -eq 0 ]
  [ "$output" = "forge task comment 4 done" ]
}

@test "close without a comment shells out only to forge task update --status closed" {
  FAKE_FORGE_DIR="$(mktemp -d)"
  cat >"${FAKE_FORGE_DIR}/forge" <<'EOF'
#!/usr/bin/env bash
echo "forge $*"
EOF
  chmod +x "${FAKE_FORGE_DIR}/forge"

  PATH="${FAKE_FORGE_DIR}:${PATH}" run "${FORGE_ADAPTER}" close ignored-scope 4
  rm -rf "${FAKE_FORGE_DIR}"

  [ "$status" -eq 0 ]
  [ "$output" = "forge task update 4 --status closed" ]
}

@test "close with a comment posts the comment then closes, in that order" {
  FAKE_FORGE_DIR="$(mktemp -d)"
  cat >"${FAKE_FORGE_DIR}/forge" <<'EOF'
#!/usr/bin/env bash
echo "forge $*"
EOF
  chmod +x "${FAKE_FORGE_DIR}/forge"

  PATH="${FAKE_FORGE_DIR}:${PATH}" run "${FORGE_ADAPTER}" close ignored-scope 4 "all done"
  rm -rf "${FAKE_FORGE_DIR}"

  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '%s\n%s' \
    "forge task comment 4 all done" \
    "forge task update 4 --status closed")" ]
}

@test "label shells out to forge task label" {
  FAKE_FORGE_DIR="$(mktemp -d)"
  cat >"${FAKE_FORGE_DIR}/forge" <<'EOF'
#!/usr/bin/env bash
echo "forge $*"
EOF
  chmod +x "${FAKE_FORGE_DIR}/forge"

  PATH="${FAKE_FORGE_DIR}:${PATH}" run "${FORGE_ADAPTER}" label ignored-scope 4 ready-for-human
  rm -rf "${FAKE_FORGE_DIR}"

  [ "$status" -eq 0 ]
  [ "$output" = "forge task label 4 ready-for-human" ]
}

@test "unlabel shells out to forge task unlabel" {
  FAKE_FORGE_DIR="$(mktemp -d)"
  cat >"${FAKE_FORGE_DIR}/forge" <<'EOF'
#!/usr/bin/env bash
echo "forge $*"
EOF
  chmod +x "${FAKE_FORGE_DIR}/forge"

  PATH="${FAKE_FORGE_DIR}:${PATH}" run "${FORGE_ADAPTER}" unlabel ignored-scope 4 ready-for-human
  rm -rf "${FAKE_FORGE_DIR}"

  [ "$status" -eq 0 ]
  [ "$output" = "forge task unlabel 4 ready-for-human" ]
}

@test "rejects an unknown subcommand" {
  run "${FORGE_ADAPTER}" bogus ignored-scope 4

  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown subcommand"* ]]
}
