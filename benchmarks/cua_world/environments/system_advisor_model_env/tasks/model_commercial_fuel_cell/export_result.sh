#!/bin/bash
echo "=== Exporting task result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

# Check if project files exist
SAM_FILE="/home/ga/Documents/SAM_Projects/datacenter_fuel_cell.sam"
PY_FILE="/home/ga/Documents/SAM_Projects/datacenter_fuel_cell.py"
JSON_FILE="/home/ga/Documents/SAM_Projects/fuel_cell_results.json"

PROJECT_EXISTS="false"
PROJECT_MODIFIED="false"

if [ -f "$SAM_FILE" ]; then
    PROJECT_EXISTS="true"
    MTIME=$(stat -c%Y "$SAM_FILE" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        PROJECT_MODIFIED="true"
    fi
elif [ -f "$PY_FILE" ]; then
    PROJECT_EXISTS="true"
    MTIME=$(stat -c%Y "$PY_FILE" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        PROJECT_MODIFIED="true"
    fi
fi

JSON_EXISTS="false"
JSON_MODIFIED="false"

if [ -f "$JSON_FILE" ]; then
    JSON_EXISTS="true"
    MTIME=$(stat -c%Y "$JSON_FILE" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START" ]; then
        JSON_MODIFIED="true"
    fi
fi

# Write result JSON safely
cat > /tmp/task_result.json << EOF
{
    "project_exists": $PROJECT_EXISTS,
    "project_modified": $PROJECT_MODIFIED,
    "json_exists": $JSON_EXISTS,
    "json_modified": $JSON_MODIFIED,
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="