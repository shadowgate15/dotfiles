#!/usr/bin/env bats

setup() {
  CONFIRMATION_ATTEMPT="${BATS_TEST_DIRNAME}/../lib/confirmation-attempt"
}

# Pure helper: no `claude` call involved, sourced directly.

@test "build_prompt: names the issue, its title, the base ref, and read-only + discovery + code-review instructions" {
  run bash -c 'source "$1"; build_prompt "$2" "$3" "$4"' _ "${CONFIRMATION_ATTEMPT}" main 42 "Add the frobnicator"

  [ "$status" -eq 0 ]
  [[ "$output" == *"issue #42"* ]]
  [[ "$output" == *"Add the frobnicator"* ]]
  [[ "$output" == *"no ability to edit or write any file"* ]]
  [[ "$output" == *"Discover and run this repo's own test suite"* ]]
  [[ "$output" == *"code-review"* ]]
  [[ "$output" == *"diff between main and the current HEAD"* ]]
  [[ "$output" == *"git diff main...HEAD"* ]]
}

# prompt subcommand: gives orchestration code a way to preview the exact
# prompt without invoking `claude`.

@test "prompt: prints the same prompt build_prompt would, without invoking claude" {
  run "${CONFIRMATION_ATTEMPT}" prompt main 42 "Add the frobnicator"

  [ "$status" -eq 0 ]
  [[ "$output" == *"issue #42"* ]]
  [[ "$output" == *"git diff main...HEAD"* ]]
}

@test "prompt: rejects a non-numeric issue number" {
  run "${CONFIRMATION_ATTEMPT}" prompt main not-a-number "Some title"

  [ "$status" -ne 0 ]
  [[ "$output" == *"issue number"* ]]
}

@test "prompt: rejects missing arguments" {
  run "${CONFIRMATION_ATTEMPT}" prompt main 42

  [ "$status" -ne 0 ]
  [[ "$output" == *"base-ref"* ]]
}

# run subcommand: asserts the exact `claude` invocation, cwd, tool
# restriction, and verdict parsing -- `claude` itself is faked so no real
# headless session is started.

fake_claude_reporting() {
  # $1: verdict json body to echo on stdout
  FAKE_CLAUDE_DIR="$(mktemp -d)"
  cat >"${FAKE_CLAUDE_DIR}/claude" <<EOF
#!/usr/bin/env bash
echo "cwd=\$(pwd -P)" >&2
echo "args=\$*" >&2
echo '$1'
EOF
  chmod +x "${FAKE_CLAUDE_DIR}/claude"
}

@test "run: invokes claude with a hard-restricted read-only toolset, permissions bypassed, and a json-schema for the verdict" {
  local worktree_dir
  worktree_dir="$(cd "$(mktemp -d)" && pwd -P)"
  fake_claude_reporting '{"verdict":"pass","reason":"all good"}'

  PATH="${FAKE_CLAUDE_DIR}:${PATH}" run "${CONFIRMATION_ATTEMPT}" run "${worktree_dir}" main 42 "Add the frobnicator"
  rm -rf "${FAKE_CLAUDE_DIR}" "${worktree_dir}"

  [ "$status" -eq 0 ]
  [[ "$output" == *"cwd=${worktree_dir}"* ]]
  [[ "$output" == *"args=-p --tools Bash,Read,Grep,Glob,Agent,Skill --dangerously-skip-permissions --json-schema"* ]]
  [[ "$output" == *'"enum":["pass","fail"]'* ]]
  [[ "$output" == *"--output-format text"* ]]
  [[ "$output" != *"Edit"* ]]
  [[ "$output" != *"Write"* ]]
}

@test "run: reports PASS and exits 0 on a passing verdict" {
  local worktree_dir
  worktree_dir="$(mktemp -d)"
  fake_claude_reporting '{"verdict":"pass","reason":"tests and typecheck green, no hard findings"}'

  PATH="${FAKE_CLAUDE_DIR}:${PATH}" run "${CONFIRMATION_ATTEMPT}" run "${worktree_dir}" main 42 "Add the frobnicator"
  rm -rf "${FAKE_CLAUDE_DIR}" "${worktree_dir}"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Confirmation: PASS -- tests and typecheck green, no hard findings"* ]]
}

@test "run: reports FAIL and exits non-zero on a failing verdict" {
  local worktree_dir
  worktree_dir="$(mktemp -d)"
  fake_claude_reporting '{"verdict":"fail","reason":"one test is failing"}'

  PATH="${FAKE_CLAUDE_DIR}:${PATH}" run "${CONFIRMATION_ATTEMPT}" run "${worktree_dir}" main 42 "Add the frobnicator"
  rm -rf "${FAKE_CLAUDE_DIR}" "${worktree_dir}"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Confirmation: FAIL -- one test is failing"* ]]
}

@test "run: fails clearly when claude's output cannot be parsed as a verdict" {
  local worktree_dir
  worktree_dir="$(mktemp -d)"
  fake_claude_reporting 'not json at all'

  PATH="${FAKE_CLAUDE_DIR}:${PATH}" run "${CONFIRMATION_ATTEMPT}" run "${worktree_dir}" main 42 "Add the frobnicator"
  rm -rf "${FAKE_CLAUDE_DIR}" "${worktree_dir}"

  [ "$status" -ne 0 ]
  [[ "$output" == *"could not parse a verdict"* ]]
}

@test "run: fails clearly when claude itself exits with an error" {
  local worktree_dir
  worktree_dir="$(mktemp -d)"
  FAKE_CLAUDE_DIR="$(mktemp -d)"
  cat >"${FAKE_CLAUDE_DIR}/claude" <<'EOF'
#!/usr/bin/env bash
echo "boom" >&2
exit 3
EOF
  chmod +x "${FAKE_CLAUDE_DIR}/claude"

  PATH="${FAKE_CLAUDE_DIR}:${PATH}" run "${CONFIRMATION_ATTEMPT}" run "${worktree_dir}" main 42 "Add the frobnicator"
  rm -rf "${FAKE_CLAUDE_DIR}" "${worktree_dir}"

  [ "$status" -ne 0 ]
  [[ "$output" == *"confirmation session exited with an error"* ]]
}

@test "run: fails clearly when the worktree directory does not exist" {
  run "${CONFIRMATION_ATTEMPT}" run /no/such/worktree-dir main 42 "Some title"

  [ "$status" -ne 0 ]
  [[ "$output" == *"worktree directory"* ]]
}

@test "run: rejects a non-numeric issue number" {
  local worktree_dir
  worktree_dir="$(mktemp -d)"

  run "${CONFIRMATION_ATTEMPT}" run "${worktree_dir}" main not-a-number "Some title"
  rm -rf "${worktree_dir}"

  [ "$status" -ne 0 ]
  [[ "$output" == *"issue number"* ]]
}

@test "rejects an unknown subcommand" {
  run "${CONFIRMATION_ATTEMPT}" bogus main 42 "Some title"

  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown subcommand"* ]]
}

@test "fails clearly when the claude CLI is not on PATH" {
  # macOS ships a system /usr/bin/jq and /bin/bash, but `claude` only lives
  # under the homebrew prefix -- so /usr/bin:/bin has jq and a shell to run
  # the script with, but no `claude` anywhere on it.
  PATH="/usr/bin:/bin" run "${CONFIRMATION_ATTEMPT}" prompt main 42 "Some title"

  [ "$status" -ne 0 ]
  [[ "$output" == *"claude"*"not found on PATH"* ]]
}

@test "fails clearly when jq is not on PATH" {
  # `claude` faked in, but neither /usr/bin (system jq) nor the homebrew
  # prefix (real jq/claude) is on PATH.
  FAKE_CLAUDE_DIR="$(mktemp -d)"
  cat >"${FAKE_CLAUDE_DIR}/claude" <<'EOF'
#!/usr/bin/env bash
EOF
  chmod +x "${FAKE_CLAUDE_DIR}/claude"

  PATH="${FAKE_CLAUDE_DIR}:/bin" run "${CONFIRMATION_ATTEMPT}" prompt main 42 "Some title"
  rm -rf "${FAKE_CLAUDE_DIR}"

  [ "$status" -ne 0 ]
  [[ "$output" == *"jq"*"not found on PATH"* ]]
}
