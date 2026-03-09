#!/bin/bash
echo "=== Exporting record_vitals results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final_state.png

# 2. Retrieve setup data
MARIA_ID=$(cat /tmp/maria_santos_id.txt 2>/dev/null || echo "")
TASK_START_MYSQL=$(cat /tmp/task_start_time_mysql.txt 2>/dev/null || echo "1970-01-01 00:00:00")
INITIAL_COUNT=$(cat /tmp/initial_measurement_count.txt 2>/dev/null || echo "0")

echo "Checking measurements for Patient ID: $MARIA_ID since $TASK_START_MYSQL"

# 3. Query Database for NEW measurements
# We fetch type, dataField (value), and dateEntered
# Note: dateEntered in Oscar is typically DATE or DATETIME. If DATE, we might rely on ID > X or just date >= today.
# measurements table schema usually has 'dateEntered' as datetime or timestamp.
RAW_DATA=$(oscar_query "SELECT type, dataField, dateEntered FROM measurements WHERE demographicNo='$MARIA_ID' AND dateEntered >= '$TASK_START_MYSQL' ORDER BY id DESC")

# 4. Get current total count
CURRENT_COUNT=$(oscar_query "SELECT COUNT(*) FROM measurements WHERE demographicNo='$MARIA_ID'" 2>/dev/null || echo "0")

# 5. Check if browser is still running
BROWSER_RUNNING="false"
if pgrep -f firefox > /dev/null; then
    BROWSER_RUNNING="true"
fi

# 6. Construct JSON Result
# We parse the raw sql output (tab separated) into a JSON array
MEASUREMENTS_JSON="[]"
if [ -n "$RAW_DATA" ]; then
    # Convert tab-separated lines to JSON objects
    # This python snippet does the parsing safely
    MEASUREMENTS_JSON=$(python3 -c "
import sys, json
lines = sys.stdin.read().splitlines()
data = []
for line in lines:
    parts = line.split('\t')
    if len(parts) >= 2:
        entry = {'type': parts[0], 'value': parts[1]}
        if len(parts) > 2:
            entry['date'] = parts[2]
        data.append(entry)
print(json.dumps(data))
" <<< "$RAW_DATA")
fi

# Create temporary JSON file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_id": "$MARIA_ID",
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "new_measurements": $MEASUREMENTS_JSON,
    "browser_running": $BROWSER_RUNNING,
    "task_start_time": "$TASK_START_MYSQL",
    "screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Move to final location (handle permissions)
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json