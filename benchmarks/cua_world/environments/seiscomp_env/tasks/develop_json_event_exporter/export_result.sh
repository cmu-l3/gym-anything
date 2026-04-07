#!/bin/bash
echo "=== Exporting develop_json_event_exporter result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Paths
SCRIPT_PATH="/home/ga/Documents/export_latest_json.py"
JSON_PATH="/home/ga/Documents/latest_event.json"

SCRIPT_EXISTS="false"
SCRIPT_CREATED_DURING_TASK="false"
JSON_EXISTS="false"
JSON_CREATED_DURING_TASK="false"

# Check script file
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    SCRIPT_MTIME=$(stat -c %Y "$SCRIPT_PATH" 2>/dev/null || echo "0")
    if [ "$SCRIPT_MTIME" -ge "$TASK_START" ]; then
        SCRIPT_CREATED_DURING_TASK="true"
    fi
    # Copy to tmp for verifier to read
    cp "$SCRIPT_PATH" /tmp/export_latest_json.py 2>/dev/null
    chmod 644 /tmp/export_latest_json.py 2>/dev/null
fi

# Check json file
if [ -f "$JSON_PATH" ]; then
    JSON_EXISTS="true"
    JSON_MTIME=$(stat -c %Y "$JSON_PATH" 2>/dev/null || echo "0")
    if [ "$JSON_MTIME" -ge "$TASK_START" ]; then
        JSON_CREATED_DURING_TASK="true"
    fi
    # Copy to tmp for verifier to read
    cp "$JSON_PATH" /tmp/latest_event.json 2>/dev/null
    chmod 644 /tmp/latest_event.json 2>/dev/null
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "script_exists": $SCRIPT_EXISTS,
    "script_created_during_task": $SCRIPT_CREATED_DURING_TASK,
    "json_exists": $JSON_EXISTS,
    "json_created_during_task": $JSON_CREATED_DURING_TASK
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null
rm -f "$TEMP_JSON"

echo "Result metadata saved to /tmp/task_result.json"
echo "=== Export complete ==="