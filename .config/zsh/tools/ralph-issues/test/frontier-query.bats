#!/usr/bin/env bats

setup() {
  FRONTIER_QUERY_BIN="${BATS_TEST_DIRNAME}/../lib/frontier-query"
}

@test "native shape: picks the first unblocked, unassigned, ready-for-agent sub-issue in tracker order" {
  run "${FRONTIER_QUERY_BIN}" <<'JSON'
{
  "shape": "native",
  "sub_issues": [
    {"number": 5, "blocked_by": 1, "assignees": [], "labels": ["ready-for-agent"]},
    {"number": 6, "blocked_by": 0, "assignees": ["alice"], "labels": ["ready-for-agent"]},
    {"number": 7, "blocked_by": 0, "assignees": [], "labels": ["ready-for-agent"]},
    {"number": 8, "blocked_by": 0, "assignees": [], "labels": ["ready-for-agent"]}
  ]
}
JSON

  [ "$status" -eq 0 ]
  [ "$output" = '{"next":7}' ]
}

@test "native shape: returns null when every sub-issue is blocked or assigned" {
  run "${FRONTIER_QUERY_BIN}" <<'JSON'
{
  "shape": "native",
  "sub_issues": [
    {"number": 5, "blocked_by": 1, "assignees": [], "labels": ["ready-for-agent"]},
    {"number": 6, "blocked_by": 0, "assignees": ["alice"], "labels": ["ready-for-agent"]}
  ]
}
JSON

  [ "$status" -eq 0 ]
  [ "$output" = '{"next":null}' ]
}

@test "native shape: returns null for an empty sub-issue list" {
  run "${FRONTIER_QUERY_BIN}" <<'JSON'
{
  "shape": "native",
  "sub_issues": []
}
JSON

  [ "$status" -eq 0 ]
  [ "$output" = '{"next":null}' ]
}

@test "native shape: a single unblocked, unassigned, ready-for-agent sub-issue is picked" {
  run "${FRONTIER_QUERY_BIN}" <<'JSON'
{
  "shape": "native",
  "sub_issues": [
    {"number": 42, "blocked_by": 0, "assignees": [], "labels": ["ready-for-agent"]}
  ]
}
JSON

  [ "$status" -eq 0 ]
  [ "$output" = '{"next":42}' ]
}

@test "native shape: skips an unblocked, unassigned sub-issue lacking ready-for-agent" {
  run "${FRONTIER_QUERY_BIN}" <<'JSON'
{
  "shape": "native",
  "sub_issues": [
    {"number": 5, "blocked_by": 0, "assignees": [], "labels": []},
    {"number": 6, "blocked_by": 0, "assignees": [], "labels": ["ready-for-agent"]}
  ]
}
JSON

  [ "$status" -eq 0 ]
  [ "$output" = '{"next":6}' ]
}

@test "checklist shape: picks the first unblocked, unassigned, ready-for-agent issue in checklist order" {
  run "${FRONTIER_QUERY_BIN}" <<'JSON'
{
  "shape": "checklist",
  "checklist_order": [7, 5, 6],
  "issues": {
    "5": {"blocked_by": [], "assignees": [], "labels": ["ready-for-agent"]},
    "6": {"blocked_by": [], "assignees": [], "labels": ["ready-for-agent"]},
    "7": {"blocked_by": [4], "assignees": [], "labels": ["ready-for-agent"]}
  },
  "open_issues": [4, 5, 6, 7]
}
JSON

  [ "$status" -eq 0 ]
  [ "$output" = '{"next":5}' ]
}

@test "checklist shape: a blocker that is already closed does not block" {
  run "${FRONTIER_QUERY_BIN}" <<'JSON'
{
  "shape": "checklist",
  "checklist_order": [7, 5],
  "issues": {
    "5": {"blocked_by": [], "assignees": [], "labels": ["ready-for-agent"]},
    "7": {"blocked_by": [4], "assignees": [], "labels": ["ready-for-agent"]}
  },
  "open_issues": [5, 7]
}
JSON

  [ "$status" -eq 0 ]
  [ "$output" = '{"next":7}' ]
}

@test "checklist shape: an issue with any open blocker is skipped" {
  run "${FRONTIER_QUERY_BIN}" <<'JSON'
{
  "shape": "checklist",
  "checklist_order": [7, 5],
  "issues": {
    "5": {"blocked_by": [], "assignees": [], "labels": ["ready-for-agent"]},
    "7": {"blocked_by": [4, 6], "assignees": [], "labels": ["ready-for-agent"]}
  },
  "open_issues": [4, 5, 6, 7]
}
JSON

  [ "$status" -eq 0 ]
  [ "$output" = '{"next":5}' ]
}

@test "checklist shape: an assigned issue is skipped even if unblocked" {
  run "${FRONTIER_QUERY_BIN}" <<'JSON'
{
  "shape": "checklist",
  "checklist_order": [5, 6],
  "issues": {
    "5": {"blocked_by": [], "assignees": ["alice"], "labels": ["ready-for-agent"]},
    "6": {"blocked_by": [], "assignees": [], "labels": ["ready-for-agent"]}
  },
  "open_issues": [5, 6]
}
JSON

  [ "$status" -eq 0 ]
  [ "$output" = '{"next":6}' ]
}

@test "native shape: a sub-issue that is both blocked and assigned is skipped" {
  run "${FRONTIER_QUERY_BIN}" <<'JSON'
{
  "shape": "native",
  "sub_issues": [
    {"number": 5, "blocked_by": 1, "assignees": ["alice"], "labels": ["ready-for-agent"]},
    {"number": 6, "blocked_by": 0, "assignees": [], "labels": ["ready-for-agent"]}
  ]
}
JSON

  [ "$status" -eq 0 ]
  [ "$output" = '{"next":6}' ]
}

@test "checklist shape: an issue that is both blocked and assigned is skipped" {
  run "${FRONTIER_QUERY_BIN}" <<'JSON'
{
  "shape": "checklist",
  "checklist_order": [5, 6],
  "issues": {
    "5": {"blocked_by": [9], "assignees": ["alice"], "labels": ["ready-for-agent"]},
    "6": {"blocked_by": [], "assignees": [], "labels": ["ready-for-agent"]}
  },
  "open_issues": [5, 6, 9]
}
JSON

  [ "$status" -eq 0 ]
  [ "$output" = '{"next":6}' ]
}

@test "checklist shape: returns null when every candidate is blocked or assigned" {
  run "${FRONTIER_QUERY_BIN}" <<'JSON'
{
  "shape": "checklist",
  "checklist_order": [5, 6],
  "issues": {
    "5": {"blocked_by": [9], "assignees": [], "labels": ["ready-for-agent"]},
    "6": {"blocked_by": [], "assignees": ["alice"], "labels": ["ready-for-agent"]}
  },
  "open_issues": [5, 6, 9]
}
JSON

  [ "$status" -eq 0 ]
  [ "$output" = '{"next":null}' ]
}

@test "checklist shape: skips an unblocked, unassigned issue lacking ready-for-agent" {
  run "${FRONTIER_QUERY_BIN}" <<'JSON'
{
  "shape": "checklist",
  "checklist_order": [5, 6],
  "issues": {
    "5": {"blocked_by": [], "assignees": [], "labels": []},
    "6": {"blocked_by": [], "assignees": [], "labels": ["ready-for-agent"]}
  },
  "open_issues": [5, 6]
}
JSON

  [ "$status" -eq 0 ]
  [ "$output" = '{"next":6}' ]
}

@test "rejects input with an unknown or missing shape" {
  run "${FRONTIER_QUERY_BIN}" <<'JSON'
{
  "shape": "made-up",
  "sub_issues": []
}
JSON

  [ "$status" -ne 0 ]
}
