#!/usr/bin/env bats

setup() {
  WORKTREE="${BATS_TEST_DIRNAME}/../lib/worktree"
  # Pin the pre-existing suite to the git backend explicitly, since `auto`
  # now resolves to `wt` whenever `wt` happens to be on the dev machine's
  # PATH. Tests exercising `auto` or the `wt` backend override this.
  export RALPH_WORKTREE_BACKEND=git

  REPO_DIR="$(cd "$(mktemp -d)" && pwd -P)/some-repo"
  mkdir -p "${REPO_DIR}"
  git -C "${REPO_DIR}" init -q
  git -C "${REPO_DIR}" config user.email "test@example.com"
  git -C "${REPO_DIR}" config user.name "Test"
  git -C "${REPO_DIR}" commit -q --allow-empty -m "initial commit"
}

teardown() {
  git -C "${REPO_DIR}" worktree list --porcelain 2>/dev/null \
    | awk '/^worktree /{print $2}' \
    | tail -n +2 \
    | xargs -I{} rm -rf {}
  rm -rf "$(dirname "${REPO_DIR}")"
}

# Pure helpers: no `git worktree` call involved, sourced directly.

@test "branch_name: builds the ralph-issues/issue-<n> convention" {
  run bash -c 'source "$1"; branch_name "$2"' _ "${WORKTREE}" 42

  [ "$status" -eq 0 ]
  [ "$output" = "ralph-issues/issue-42" ]
}

@test "worktree_path: builds the sibling .ralph-worktrees/issue-<n> convention" {
  run bash -c 'source "$1"; worktree_path "$2" "$3"' _ "${WORKTREE}" "${REPO_DIR}" 42

  [ "$status" -eq 0 ]
  [ "$output" = "$(dirname "${REPO_DIR}")/some-repo.ralph-worktrees/issue-42" ]
}

# branch-name subcommand: gives orchestration code a single source of truth
# for the naming convention instead of re-deriving the literal itself.

@test "branch-name: prints the branch name for an issue without creating anything" {
  run "${WORKTREE}" branch-name 42

  [ "$status" -eq 0 ]
  [ "$output" = "ralph-issues/issue-42" ]
}

@test "branch-name: rejects a non-numeric issue number" {
  run "${WORKTREE}" branch-name not-a-number

  [ "$status" -ne 0 ]
  [[ "$output" == *"issue number"* ]]
}

@test "path: prints the deterministic worktree path without creating anything" {
  run "${WORKTREE}" path "${REPO_DIR}" 42

  [ "$status" -eq 0 ]
  [ "$output" = "$(dirname "${REPO_DIR}")/some-repo.ralph-worktrees/issue-42" ]
  [ ! -e "$(dirname "${REPO_DIR}")/some-repo.ralph-worktrees" ]
}

@test "create: creates a new worktree and branch scoped to the issue" {
  run "${WORKTREE}" create "${REPO_DIR}" 42

  [ "$status" -eq 0 ]
  local expected_path
  expected_path="$(dirname "${REPO_DIR}")/some-repo.ralph-worktrees/issue-42"
  [ "$output" = "${expected_path}" ]
  [ -d "${expected_path}" ]

  run git -C "${REPO_DIR}" show-ref --verify --quiet "refs/heads/ralph-issues/issue-42"
  [ "$status" -eq 0 ]

  run git -C "${expected_path}" rev-parse --abbrev-ref HEAD
  [ "$output" = "ralph-issues/issue-42" ]
}

@test "create: a second call for the same issue reuses the existing worktree instead of erroring" {
  "${WORKTREE}" create "${REPO_DIR}" 42

  run "${WORKTREE}" create "${REPO_DIR}" 42

  [ "$status" -eq 0 ]
  [ "$output" = "$(dirname "${REPO_DIR}")/some-repo.ralph-worktrees/issue-42" ]

  run git -C "${REPO_DIR}" worktree list
  [ "$(echo "$output" | grep -c "issue-42")" -eq 1 ]
}

@test "create: two different issues get two independent worktrees and branches" {
  run "${WORKTREE}" create "${REPO_DIR}" 42
  local path42="$output"
  run "${WORKTREE}" create "${REPO_DIR}" 43
  local path43="$output"

  [ "${path42}" != "${path43}" ]
  [ -d "${path42}" ]
  [ -d "${path43}" ]

  run git -C "${REPO_DIR}" show-ref --verify --quiet "refs/heads/ralph-issues/issue-42"
  [ "$status" -eq 0 ]
  run git -C "${REPO_DIR}" show-ref --verify --quiet "refs/heads/ralph-issues/issue-43"
  [ "$status" -eq 0 ]
}

@test "create: rejects a non-numeric issue number" {
  run "${WORKTREE}" create "${REPO_DIR}" not-a-number

  [ "$status" -ne 0 ]
  [[ "$output" == *"issue number"* ]]
}

@test "rejects an unknown subcommand" {
  run "${WORKTREE}" bogus "${REPO_DIR}" 42

  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown subcommand"* ]]
}

# discard: removes a sub-issue's worktree once its work is merged, without
# touching the branch itself.

@test "discard: removes an existing worktree, leaving the branch intact" {
  "${WORKTREE}" create "${REPO_DIR}" 42
  local path
  path="$(dirname "${REPO_DIR}")/some-repo.ralph-worktrees/issue-42"
  [ -d "${path}" ]

  run "${WORKTREE}" discard "${REPO_DIR}" 42

  [ "$status" -eq 0 ]
  [ ! -d "${path}" ]

  run git -C "${REPO_DIR}" show-ref --verify --quiet "refs/heads/ralph-issues/issue-42"
  [ "$status" -eq 0 ]
}

@test "discard: succeeds as a no-op when no worktree exists for the issue" {
  run "${WORKTREE}" discard "${REPO_DIR}" 99

  [ "$status" -eq 0 ]
}

@test "discard: rejects a non-numeric issue number" {
  run "${WORKTREE}" discard "${REPO_DIR}" not-a-number

  [ "$status" -ne 0 ]
  [[ "$output" == *"issue number"* ]]
}

# integration-branch-name / integration-path: naming conventions for the
# run's shared integration branch and its dedicated worktree.

@test "integration-branch-name: builds the ralph-issues/parent-<n>-integration convention" {
  run "${WORKTREE}" integration-branch-name 1

  [ "$status" -eq 0 ]
  [ "$output" = "ralph-issues/parent-1-integration" ]
}

@test "integration-branch-name: rejects a non-numeric parent issue number" {
  run "${WORKTREE}" integration-branch-name not-a-number

  [ "$status" -ne 0 ]
  [[ "$output" == *"parent issue number"* ]]
}

@test "integration-path: builds the sibling .ralph-worktrees/parent-<n>-integration convention" {
  run "${WORKTREE}" integration-path "${REPO_DIR}" 1

  [ "$status" -eq 0 ]
  [ "$output" = "$(dirname "${REPO_DIR}")/some-repo.ralph-worktrees/parent-1-integration" ]
  [ ! -e "$(dirname "${REPO_DIR}")/some-repo.ralph-worktrees" ]
}

# create-integration: the dedicated, persistent worktree/branch that
# verified sub-issue work merges into.

@test "create-integration: creates the shared integration worktree and branch" {
  run "${WORKTREE}" create-integration "${REPO_DIR}" 1

  [ "$status" -eq 0 ]
  local expected_path
  expected_path="$(dirname "${REPO_DIR}")/some-repo.ralph-worktrees/parent-1-integration"
  [ "$output" = "${expected_path}" ]
  [ -d "${expected_path}" ]

  run git -C "${REPO_DIR}" show-ref --verify --quiet "refs/heads/ralph-issues/parent-1-integration"
  [ "$status" -eq 0 ]
}

@test "create-integration: a second call reuses the existing worktree instead of erroring" {
  "${WORKTREE}" create-integration "${REPO_DIR}" 1

  run "${WORKTREE}" create-integration "${REPO_DIR}" 1

  [ "$status" -eq 0 ]
  run git -C "${REPO_DIR}" worktree list
  [ "$(echo "$output" | grep -c "parent-1-integration")" -eq 1 ]
}

@test "create-integration: rejects a non-numeric parent issue number" {
  run "${WORKTREE}" create-integration "${REPO_DIR}" not-a-number

  [ "$status" -ne 0 ]
  [[ "$output" == *"parent issue number"* ]]
}

# RALPH_WORKTREE_BACKEND: selects the backend the five lifecycle/query
# subcommands route through. `auto` (the default) selects `wt` when it's on
# PATH, `git` otherwise.

@test "backend: RALPH_WORKTREE_BACKEND=auto (default) behaves like the git backend when wt is absent from PATH" {
  run env -u RALPH_WORKTREE_BACKEND PATH="/usr/bin:/bin" "${WORKTREE}" path "${REPO_DIR}" 42

  [ "$status" -eq 0 ]
  [ "$output" = "$(dirname "${REPO_DIR}")/some-repo.ralph-worktrees/issue-42" ]
}

@test "backend: RALPH_WORKTREE_BACKEND with an invalid value fails clearly" {
  run env RALPH_WORKTREE_BACKEND=bogus "${WORKTREE}" path "${REPO_DIR}" 42

  [ "$status" -ne 0 ]
  [[ "$output" == *"RALPH_WORKTREE_BACKEND"* ]]
}

@test "backend: auto selects wt when a wt stub is on PATH" {
  FAKE_WT_DIR="$(mktemp -d)"
  cat >"${FAKE_WT_DIR}/wt" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${FAKE_WT_DIR}/wt"

  PATH="${FAKE_WT_DIR}:${PATH}" run env -u RALPH_WORKTREE_BACKEND \
    bash -c 'source "$1"; resolve_backend' _ "${WORKTREE}"
  rm -rf "${FAKE_WT_DIR}"

  [ "$status" -eq 0 ]
  [ "$output" = "wt" ]
}

@test "backend: auto falls back to git when wt is not on PATH" {
  run env -u RALPH_WORKTREE_BACKEND PATH="/usr/bin:/bin" \
    bash -c 'source "$1"; resolve_backend' _ "${WORKTREE}"

  [ "$status" -eq 0 ]
  [ "$output" = "git" ]
}

# wt backend: dispatch tests against a stub `wt` on PATH (always run) --
# assert the exact `wt` invocations and JSON parsing, without depending on
# the real `wt` binary. A real-`wt` integration test follows, gated on
# `command -v wt`.

# $1: dir to write the stub into. The stub emits canned `--format json` on
# stdout but shells out to real `git worktree`/`git branch` underneath (per
# issue #32's Testing Decisions), so branch/worktree state is real git state
# rather than a simulation -- `list` derives its items by asking git, and
# `switch`/`remove` actually create/remove real worktrees.
setup_fake_wt() {
  local fakes_dir="$1"
  mkdir -p "${fakes_dir}"
  # Resolve to the real path up front: `git worktree list --porcelain` prints
  # realpaths, so worktree_path_for's own constructions must match or a
  # second `create` call's reuse-detection would spuriously mismatch.
  fakes_dir="$(cd "${fakes_dir}" && pwd -P)"
  : >"${fakes_dir}/invocations.log"

  cat >"${fakes_dir}/wt" <<EOF
#!/usr/bin/env bash
set -euo pipefail
FAKES_DIR="${fakes_dir}"
echo "\$*" >>"\${FAKES_DIR}/invocations.log"

# Parse past the leading \`-C <repo-root>\` global option to find the
# subcommand and its first positional argument, whatever it is.
args=("\$@")
repo_root=""
sub=""
positional=""
base_ref=""
i=0
while [[ \$i -lt \${#args[@]} ]]; do
  case "\${args[\$i]}" in
    -C) repo_root="\${args[\$((i + 1))]}"; i=\$((i + 2)) ;;
    switch|remove|list) sub="\${args[\$i]}"; i=\$((i + 1)) ;;
    --base) base_ref="\${args[\$((i + 1))]}"; i=\$((i + 2)) ;;
    --format) i=\$((i + 2)) ;;
    --create|--no-cd|--no-delete-branch|--foreground|--branches)
      i=\$((i + 1))
      ;;
    -*) i=\$((i + 1)) ;;
    *)
      [[ -z "\${positional}" ]] && positional="\${args[\$i]}"
      i=\$((i + 1))
      ;;
  esac
done

worktree_path_for() {
  echo "\${FAKES_DIR}/worktree-\${1//\//_}"
}

worktree_path_if_any() {
  git -C "\${repo_root}" worktree list --porcelain | awk -v branch="refs/heads/\$1" '
    /^worktree /{path=\$2}
    /^branch /{if (\$2 == branch) print path}
  '
}

case "\${sub}" in
  list)
    items="[]"
    while IFS= read -r b; do
      [[ -n "\${b}" ]] || continue
      wpath="\$(worktree_path_if_any "\${b}")"
      if [[ -n "\${wpath}" ]]; then
        items="\$(jq -c --arg b "\${b}" --arg p "\${wpath}" '. + [{branch: \$b, worktree: {path: \$p}}]' <<<"\${items}")"
      else
        items="\$(jq -c --arg b "\${b}" '. + [{branch: \$b, worktree: {path: null}}]' <<<"\${items}")"
      fi
    done < <(git -C "\${repo_root}" for-each-ref refs/heads --format='%(refname:short)')
    jq -n --argjson items "\${items}" '{items: \$items}'
    ;;
  switch)
    branch="\${positional}"
    if [[ "\$*" == *"--create"* ]]; then
      path="\$(worktree_path_for "\${branch}")"
      git -C "\${repo_root}" worktree add --quiet -b "\${branch}" "\${path}" "\${base_ref}"
      jq -n --arg branch "\${branch}" --arg path "\${path}" '{action:"created",branch:\$branch,path:\$path}'
    else
      path="\$(worktree_path_if_any "\${branch}")"
      if [[ -z "\${path}" ]]; then
        path="\$(worktree_path_for "\${branch}")"
        git -C "\${repo_root}" worktree add --quiet "\${path}" "\${branch}"
      fi
      jq -n --arg branch "\${branch}" --arg path "\${path}" '{action:"existing",branch:\$branch,path:\$path}'
    fi
    ;;
  remove)
    branch="\${positional}"
    path="\$(worktree_path_if_any "\${branch}")"
    if [[ -z "\${path}" ]]; then
      echo "no worktree" >&2
      exit 0
    fi
    git -C "\${repo_root}" worktree remove --force "\${path}"
    jq -n --arg branch "\${branch}" '[{branch:\$branch}]'
    ;;
  *)
    echo "fake wt: unhandled invocation: \$*" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "${fakes_dir}/wt"
}

@test "wt backend: create on a missing branch invokes switch --create with --base, --no-cd, --format json, no --yes" {
  FAKES_DIR="$(mktemp -d)"
  setup_fake_wt "${FAKES_DIR}"

  PATH="${FAKES_DIR}:${PATH}" run env RALPH_WORKTREE_BACKEND=wt \
    "${WORKTREE}" create "${REPO_DIR}" 42 HEAD
  local log
  log="$(cat "${FAKES_DIR}/invocations.log")"
  rm -rf "${FAKES_DIR}"

  [ "$status" -eq 0 ]
  [[ "$output" == *"worktree-ralph-issues_issue-42" ]]
  [[ "${log}" == *"switch --create ralph-issues/issue-42 --base HEAD --no-cd --format json"* ]]
  [[ "${log}" != *"--yes"* ]]
}

@test "wt backend: create on an existing branch reuses it via plain switch, ignoring base-ref" {
  FAKES_DIR="$(mktemp -d)"
  setup_fake_wt "${FAKES_DIR}"
  git -C "${REPO_DIR}" branch "ralph-issues/issue-42"

  PATH="${FAKES_DIR}:${PATH}" run env RALPH_WORKTREE_BACKEND=wt \
    "${WORKTREE}" create "${REPO_DIR}" 42 HEAD
  local log
  log="$(cat "${FAKES_DIR}/invocations.log")"
  rm -rf "${FAKES_DIR}"

  [ "$status" -eq 0 ]
  [[ "${log}" == *"switch ralph-issues/issue-42 --no-cd --format json"* ]]
  [[ "${log}" != *"switch --create"* ]]
}

@test "wt backend: a second create call for the same issue reuses the existing worktree" {
  FAKES_DIR="$(mktemp -d)"
  setup_fake_wt "${FAKES_DIR}"

  PATH="${FAKES_DIR}:${PATH}" run env RALPH_WORKTREE_BACKEND=wt \
    "${WORKTREE}" create "${REPO_DIR}" 42 HEAD
  local first_path="$output"

  PATH="${FAKES_DIR}:${PATH}" run env RALPH_WORKTREE_BACKEND=wt \
    "${WORKTREE}" create "${REPO_DIR}" 42 HEAD
  local log
  log="$(cat "${FAKES_DIR}/invocations.log")"
  rm -rf "${FAKES_DIR}"

  [ "$status" -eq 0 ]
  [ "$output" = "${first_path}" ]
  [[ "$(echo "${log}" | grep -c "switch --create")" -eq 1 ]]
}

@test "wt backend: create-integration on a missing branch creates it from base-ref" {
  FAKES_DIR="$(mktemp -d)"
  setup_fake_wt "${FAKES_DIR}"

  PATH="${FAKES_DIR}:${PATH}" run env RALPH_WORKTREE_BACKEND=wt \
    "${WORKTREE}" create-integration "${REPO_DIR}" 1 HEAD
  local log
  log="$(cat "${FAKES_DIR}/invocations.log")"
  rm -rf "${FAKES_DIR}"

  [ "$status" -eq 0 ]
  [[ "$output" == *"worktree-ralph-issues_parent-1-integration" ]]
  [[ "${log}" == *"switch --create ralph-issues/parent-1-integration --base HEAD --no-cd --format json"* ]]
}

@test "wt backend: discard invokes remove with --no-delete-branch --foreground, no --yes" {
  FAKES_DIR="$(mktemp -d)"
  setup_fake_wt "${FAKES_DIR}"
  PATH="${FAKES_DIR}:${PATH}" env RALPH_WORKTREE_BACKEND=wt \
    "${WORKTREE}" create "${REPO_DIR}" 42 HEAD >/dev/null
  : >"${FAKES_DIR}/invocations.log"

  PATH="${FAKES_DIR}:${PATH}" run env RALPH_WORKTREE_BACKEND=wt \
    "${WORKTREE}" discard "${REPO_DIR}" 42
  local log
  log="$(cat "${FAKES_DIR}/invocations.log")"
  rm -rf "${FAKES_DIR}"

  [ "$status" -eq 0 ]
  [[ "${log}" == *"remove ralph-issues/issue-42 --no-delete-branch --foreground"* ]]
  [[ "${log}" != *"--yes"* ]]
}

@test "wt backend: discard is a no-op when no branch exists for the issue" {
  FAKES_DIR="$(mktemp -d)"
  setup_fake_wt "${FAKES_DIR}"

  PATH="${FAKES_DIR}:${PATH}" run env RALPH_WORKTREE_BACKEND=wt \
    "${WORKTREE}" discard "${REPO_DIR}" 99
  local log
  log="$(cat "${FAKES_DIR}/invocations.log")"
  rm -rf "${FAKES_DIR}"

  [ "$status" -eq 0 ]
  [[ "${log}" != *"remove"* ]]
}

@test "wt backend: discard is a no-op when the branch exists but has no worktree" {
  FAKES_DIR="$(mktemp -d)"
  setup_fake_wt "${FAKES_DIR}"
  git -C "${REPO_DIR}" branch "ralph-issues/issue-42"

  PATH="${FAKES_DIR}:${PATH}" run env RALPH_WORKTREE_BACKEND=wt \
    "${WORKTREE}" discard "${REPO_DIR}" 42
  local log
  log="$(cat "${FAKES_DIR}/invocations.log")"
  rm -rf "${FAKES_DIR}"

  [ "$status" -eq 0 ]
  [[ "${log}" != *"remove"* ]]

  run git -C "${REPO_DIR}" show-ref --verify --quiet "refs/heads/ralph-issues/issue-42"
  [ "$status" -eq 0 ]
}

@test "wt backend: path errors clearly since the path isn't predictable before creation" {
  FAKES_DIR="$(mktemp -d)"
  setup_fake_wt "${FAKES_DIR}"

  PATH="${FAKES_DIR}:${PATH}" run env RALPH_WORKTREE_BACKEND=wt \
    "${WORKTREE}" path "${REPO_DIR}" 42
  rm -rf "${FAKES_DIR}"

  [ "$status" -ne 0 ]
  [[ "$output" == *"not supported under the wt backend"* ]]
}

@test "wt backend: integration-path errors clearly since the path isn't predictable before creation" {
  FAKES_DIR="$(mktemp -d)"
  setup_fake_wt "${FAKES_DIR}"

  PATH="${FAKES_DIR}:${PATH}" run env RALPH_WORKTREE_BACKEND=wt \
    "${WORKTREE}" integration-path "${REPO_DIR}" 1
  rm -rf "${FAKES_DIR}"

  [ "$status" -ne 0 ]
  [[ "$output" == *"not supported under the wt backend"* ]]
}

# Real-`wt` integration test: only runs if `wt` is actually installed, to
# validate the stub's assumptions against the real CLI's behavior.

@test "wt backend (real wt): create then discard round-trips against the real CLI" {
  if ! command -v wt >/dev/null 2>&1; then
    skip "wt is not installed"
  fi

  # `wt`'s progress output goes to stderr, but bats' `run` merges the whole
  # subprocess's stdout+stderr into $output -- redirect stderr away here so
  # $output is exactly the path lib/worktree prints on stdout.
  run env RALPH_WORKTREE_BACKEND=wt bash -c '"$1" create "$2" "$3" "$4" 2>/dev/null' \
    _ "${WORKTREE}" "${REPO_DIR}" 42 HEAD
  [ "$status" -eq 0 ]
  local path="$output"
  [ -d "${path}" ]

  run git -C "${REPO_DIR}" show-ref --verify --quiet "refs/heads/ralph-issues/issue-42"
  [ "$status" -eq 0 ]

  run env RALPH_WORKTREE_BACKEND=wt bash -c '"$1" create "$2" "$3" "$4" 2>/dev/null' \
    _ "${WORKTREE}" "${REPO_DIR}" 42 HEAD
  [ "$status" -eq 0 ]
  [ "$output" = "${path}" ]

  run env RALPH_WORKTREE_BACKEND=wt bash -c '"$1" discard "$2" "$3" 2>/dev/null' \
    _ "${WORKTREE}" "${REPO_DIR}" 42
  [ "$status" -eq 0 ]
  [ ! -d "${path}" ]

  run git -C "${REPO_DIR}" show-ref --verify --quiet "refs/heads/ralph-issues/issue-42"
  [ "$status" -eq 0 ]
}
