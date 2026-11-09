# event.jq — the one validator for an events.jsonl line.
#
# event.sh runs it before it appends a line. monitor-events.sh and
# validate-run-state.sh run it on every line they read. run-viewer.py applies
# the same rules in Python, and the test suites send the same boundary records
# through every consumer. Change a rule here and in run-viewer.py together.
#
# Use: jq -e -f event.jq <<<"$LINE"   (exit 0 = valid)
(type == "object") and
(.ts | type == "string" and test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) and
(.lane | type == "string" and length > 0) and
(.task | type == "string" and length > 0) and
(.type | IN("task_start", "task_done", "progress", "question", "waiting", "blocked", "done", "decision")) and
(.msg | type == "string" and test("^[^\r\n]*$") and length <= 3000) and
(if has("round") then (.round | type == "number" and . == floor and . >= 0) else true end) and
((keys_unsorted - ["ts", "lane", "task", "type", "msg", "round"]) == [])
