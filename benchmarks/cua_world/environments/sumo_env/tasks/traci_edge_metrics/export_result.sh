#!/bin/bash
echo "=== Exporting traci_edge_metrics result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
SCRIPT_PATH="/home/ga/SUMO_Output/traci_monitor.py"
CSV_PATH="/home/ga/SUMO_Output/edge_metrics.csv"

SCRIPT_EXISTS="false"
SCRIPT_CREATED_DURING_TASK="false"
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    SCRIPT_MTIME=$(stat -c %Y "$SCRIPT_PATH" 2>/dev/null || echo "0")
    if [ "$SCRIPT_MTIME" -ge "$TASK_START" ]; then
        SCRIPT_CREATED_DURING_TASK="true"
    fi
fi

CSV_EXISTS="false"
CSV_CREATED_DURING_TASK="false"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -ge "$TASK_START" ]; then
        CSV_CREATED_DURING_TASK="true"
    fi
fi

# Check if script has basic syntax validity
VALID_PYTHON="false"
if [ "$SCRIPT_EXISTS" = "true" ]; then
    if python3 -m py_compile "$SCRIPT_PATH" > /dev/null 2>&1; then
        VALID_PYTHON="true"
    fi
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "script_exists": $SCRIPT_EXISTS,
    "script_created_during_task": $SCRIPT_CREATED_DURING_TASK,
    "valid_python": $VALID_PYTHON,
    "csv_exists": $CSV_EXISTS,
    "csv_created_during_task": $CSV_CREATED_DURING_TASK,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move and fix permissions safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"

echo "=== Export complete ==="