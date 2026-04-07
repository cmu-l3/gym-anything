#!/bin/bash
echo "=== Exporting task result ==="

# Record task end time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Paths
SCRIPT_PATH="/home/ga/Documents/SAM_Projects/debt_sensitivity.py"
JSON_PATH="/home/ga/Documents/SAM_Projects/lcoe_sensitivity.json"

# Check script file
SCRIPT_EXISTS="false"
SCRIPT_MODIFIED="false"
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    SCRIPT_MTIME=$(stat -c%Y "$SCRIPT_PATH" 2>/dev/null || echo "0")
    if [ "$SCRIPT_MTIME" -gt "$TASK_START" ]; then
        SCRIPT_MODIFIED="true"
    fi
fi

# Check JSON file
JSON_EXISTS="false"
JSON_MODIFIED="false"
JSON_SIZE="0"
if [ -f "$JSON_PATH" ]; then
    JSON_EXISTS="true"
    JSON_SIZE=$(stat -c%s "$JSON_PATH" 2>/dev/null || echo "0")
    JSON_MTIME=$(stat -c%Y "$JSON_PATH" 2>/dev/null || echo "0")
    if [ "$JSON_MTIME" -gt "$TASK_START" ]; then
        JSON_MODIFIED="true"
    fi
fi

# Create export JSON with basic file stats. Detailed content verification is handled in verifier.py
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "script_exists": $SCRIPT_EXISTS,
    "script_modified_during_task": $SCRIPT_MODIFIED,
    "json_exists": $JSON_EXISTS,
    "json_modified_during_task": $JSON_MODIFIED,
    "json_size_bytes": $JSON_SIZE,
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Basic stats exported to /tmp/task_result.json"
echo "=== Export complete ==="