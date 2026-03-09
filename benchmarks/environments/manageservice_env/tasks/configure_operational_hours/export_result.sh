#!/bin/bash
# Export script for "configure_operational_hours" task
# 1. Captures final screenshot
# 2. Dumps the OperationalHours table from DB
# 3. Creates a JSON result file

echo "=== Exporting task results ==="
source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils"; exit 1; }

# 1. Take final screenshot (Evidence of UI state)
take_screenshot /tmp/task_final.png

# 2. Query Database for Final State
# We get raw rows: day_of_week|start_time|end_time|is_working_day
# Example output: 2|08:00|18:00|true
echo "Querying final operational hours..."
DB_QUERY="SELECT day_of_week, start_time, end_time, is_working_day FROM operationalhours ORDER BY day_of_week;"
DB_OUTPUT=$(sdp_db_exec "$DB_QUERY")

# Save raw DB output for debugging/verification
echo "$DB_OUTPUT" > /tmp/final_hours_db.txt

# 3. Get file timestamps (Anti-gaming)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 4. Construct JSON Result
# We will embed the raw DB text into the JSON so the python verifier can parse it.
# We perform simple escaping of the DB output for JSON validity.
ESCAPED_DB_OUTPUT=$(echo "$DB_OUTPUT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')
ESCAPED_INITIAL=$(cat /tmp/initial_hours_state.txt 2>/dev/null | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "db_output_raw": $ESCAPED_DB_OUTPUT,
    "initial_db_output": $ESCAPED_INITIAL,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="