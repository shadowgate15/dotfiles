if .shape == "native" then
  (.sub_issues // [])
  | map(select(
      (.blocked_by // 0) == 0
      and (((.assignees // []) | length) == 0)
      and (((.labels // []) | index("ready-for-agent")) != null)
    ))
  | {next: (.[0].number // null)}
elif .shape == "checklist" then
  (.open_issues // []) as $open
  | (.issues // {}) as $issues
  | (.checklist_order // [])
  | map(
      . as $number
      | ($issues[$number | tostring] // {}) as $issue
      | {
          number: $number,
          blocked: (($issue.blocked_by // []) | any(. as $blocker | ($open | index($blocker)) != null)),
          assigned: ((($issue.assignees // []) | length) > 0),
          ready: ((($issue.labels // []) | index("ready-for-agent")) != null)
        }
    )
  | map(select(.blocked == false and .assigned == false and .ready == true))
  | {next: (.[0].number // null)}
else
  error("frontier-query: unknown or missing \"shape\" (expected \"native\" or \"checklist\")")
end
