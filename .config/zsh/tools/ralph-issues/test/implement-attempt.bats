#!/usr/bin/env bats

setup() {
  IMPLEMENT_ATTEMPT="${BATS_TEST_DIRNAME}/../lib/implement-attempt"
}

# Pure helper: no `claude` call involved, sourced directly.

@test "build_prompt: names the issue, its title, and the slash-command form" {
  run bash -c 'source "$1"; build_prompt "$2" "$3"' _ "${IMPLEMENT_ATTEMPT}" 42 "Add the frobnicator"

  [ "$status" -eq 0 ]
  [ "$output" = '/implement Implement issue #42: "Add the frobnicator". You are already inside the dedicated git worktree and branch for this issue -- do not create a new branch. Do not close the issue when you are done; a separate verification step will handle that.' ]
}

# prompt subcommand: gives orchestration code a way to preview the exact
# prompt without invoking `claude`.

@test "prompt: prints the same prompt build_prompt would, without invoking claude" {
  run "${IMPLEMENT_ATTEMPT}" prompt 42 "Add the frobnicator"

  [ "$status" -eq 0 ]
  [ "$output" = '/implement Implement issue #42: "Add the frobnicator". You are already inside the dedicated git worktree and branch for this issue -- do not create a new branch. Do not close the issue when you are done; a separate verification step will handle that.' ]
}

@test "prompt: rejects a non-numeric issue number" {
  run "${IMPLEMENT_ATTEMPT}" prompt not-a-number "Some title"

  [ "$status" -ne 0 ]
  [[ "$output" == *"issue number"* ]]
}

# run subcommand: asserts the exact `claude` invocation, cwd, and prompt —
# `claude` itself is faked so no real headless session is started.

@test "run: invokes claude in the worktree dir, print mode, permissions bypassed, with the built prompt" {
  local worktree_dir
  worktree_dir="$(cd "$(mktemp -d)" && pwd -P)"

  FAKE_CLAUDE_DIR="$(mktemp -d)"
  cat >"${FAKE_CLAUDE_DIR}/claude" <<'EOF'
#!/usr/bin/env bash
echo "cwd=$(pwd -P)" >&2
echo "args=$*" >&2
jq -n --arg args "$*" '{is_error: false, total_cost_usd: 0.1234, usage: {}, result: ("cwd=" + $args)}'
EOF
  chmod +x "${FAKE_CLAUDE_DIR}/claude"

  PATH="${FAKE_CLAUDE_DIR}:${PATH}" run "${IMPLEMENT_ATTEMPT}" run "${worktree_dir}" 42 "Add the frobnicator"
  rm -rf "${FAKE_CLAUDE_DIR}" "${worktree_dir}"

  [ "$status" -eq 0 ]
  [[ "$output" == *"cwd=${worktree_dir}"* ]]
  [[ "$output" == *"args=-p --dangerously-skip-permissions --output-format json /implement Implement issue #42:"* ]]
  [[ "$output" == *"do not create a new branch"* ]]
}

@test "run: prints the session's final result followed by a COST_USD line" {
  local worktree_dir
  worktree_dir="$(mktemp -d)"

  FAKE_CLAUDE_DIR="$(mktemp -d)"
  cat >"${FAKE_CLAUDE_DIR}/claude" <<'EOF'
#!/usr/bin/env bash
jq -n '{is_error: false, total_cost_usd: 0.0852231, usage: {}, result: "implemented the frobnicator"}'
EOF
  chmod +x "${FAKE_CLAUDE_DIR}/claude"

  PATH="${FAKE_CLAUDE_DIR}:${PATH}" run "${IMPLEMENT_ATTEMPT}" run "${worktree_dir}" 42 "Add the frobnicator"
  rm -rf "${FAKE_CLAUDE_DIR}" "${worktree_dir}"

  [ "$status" -eq 0 ]
  [[ "$output" == *"implemented the frobnicator"* ]]
  [[ "$output" == *"COST_USD=0.0852231"* ]]
}

@test "run: propagates claude's exit status" {
  local worktree_dir
  worktree_dir="$(cd "$(mktemp -d)" && pwd -P)"

  FAKE_CLAUDE_DIR="$(mktemp -d)"
  cat >"${FAKE_CLAUDE_DIR}/claude" <<'EOF'
#!/usr/bin/env bash
exit 17
EOF
  chmod +x "${FAKE_CLAUDE_DIR}/claude"

  PATH="${FAKE_CLAUDE_DIR}:${PATH}" run "${IMPLEMENT_ATTEMPT}" run "${worktree_dir}" 42 "Add the frobnicator"
  rm -rf "${FAKE_CLAUDE_DIR}" "${worktree_dir}"

  [ "$status" -eq 17 ]
}

@test "run: fails clearly when the worktree directory does not exist" {
  run "${IMPLEMENT_ATTEMPT}" run /no/such/worktree-dir 42 "Add the frobnicator"

  [ "$status" -ne 0 ]
  [[ "$output" == *"worktree directory"* ]]
}

@test "run: rejects a non-numeric issue number" {
  local worktree_dir
  worktree_dir="$(mktemp -d)"

  run "${IMPLEMENT_ATTEMPT}" run "${worktree_dir}" not-a-number "Some title"
  rm -rf "${worktree_dir}"

  [ "$status" -ne 0 ]
  [[ "$output" == *"issue number"* ]]
}

@test "rejects an unknown subcommand" {
  run "${IMPLEMENT_ATTEMPT}" bogus 42 "Some title"

  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown subcommand"* ]]
}

@test "fails clearly when the claude CLI is not on PATH" {
  # A minimal PATH with just enough (env, bash, coreutils) to exec the
  # script itself, but no `claude` anywhere on it.
  PATH="/usr/bin:/bin" run "${IMPLEMENT_ATTEMPT}" prompt 42 "Some title"

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

  PATH="${FAKE_CLAUDE_DIR}:/bin" run "${IMPLEMENT_ATTEMPT}" prompt 42 "Some title"
  rm -rf "${FAKE_CLAUDE_DIR}"

  [ "$status" -ne 0 ]
  [[ "$output" == *"jq"*"not found on PATH"* ]]
}
