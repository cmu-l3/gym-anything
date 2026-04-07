#!/bin/bash
echo "=== Exporting task result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")
PYTHON_RAN="false"

# Check if python was run
if [ -f /home/ga/.bash_history ]; then
    if grep -q "python3\|python " /home/ga/.bash_history 2>/dev/null; then
        PYTHON_RAN="true"
    fi
fi

# Define targets
JSON_FILE="/home/ga/Documents/SAM_Projects/fuel_cell_results.json"
SCRIPT_FILE="/home/ga/Documents/SAM_Projects/fuel_cell_model.py"

JSON_EXISTS="false"
JSON_MODIFIED="false"
SCRIPT_EXISTS="false"
SCRIPT_MODIFIED="false"

# Check JSON
if [ -f "$JSON_FILE" ]; then
    JSON_EXISTS="true"
    FILE_MTIME=$(stat -c%Y "$JSON_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        JSON_MODIFIED="true"
    fi
fi

# Check Script
if [ -f "$SCRIPT_FILE" ]; then
    SCRIPT_EXISTS="true"
    SCRIPT_MTIME=$(stat -c%Y "$SCRIPT_FILE" 2>/dev/null || echo "0")
    if [ "$SCRIPT_MTIME" -gt "$TASK_START" ]; then
        SCRIPT_MODIFIED="true"
    fi
fi

# Create export summary
cat << EOF > /tmp/task_result.json
{
    "python_ran": $PYTHON_RAN,
    "json_exists": $JSON_EXISTS,
    "json_modified_during_task": $JSON_MODIFIED,
    "script_exists": $SCRIPT_EXISTS,
    "script_modified_during_task": $SCRIPT_MODIFIED,
    "task_start": $TASK_START,
    "export_timestamp": $(date +%s)
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="