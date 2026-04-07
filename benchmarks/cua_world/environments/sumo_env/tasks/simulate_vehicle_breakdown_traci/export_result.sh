#!/bin/bash
echo "=== Exporting simulate_vehicle_breakdown_traci result ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

SCRIPT_PATH="/home/ga/SUMO_Output/simulate_breakdown.py"
CSV_PATH="/home/ga/SUMO_Output/breakdown_queue.csv"

# Check Script
SCRIPT_EXISTS="false"
SCRIPT_CREATED_DURING_TASK="false"
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    SCRIPT_MTIME=$(stat -c %Y "$SCRIPT_PATH" 2>/dev/null || echo "0")
    if [ "$SCRIPT_MTIME" -gt "$TASK_START" ]; then
        SCRIPT_CREATED_DURING_TASK="true"
    fi
    # Copy to tmp for verifier
    cp "$SCRIPT_PATH" /tmp/simulate_breakdown.py
    chmod 666 /tmp/simulate_breakdown.py
fi

# Check CSV
CSV_EXISTS="false"
CSV_CREATED_DURING_TASK="false"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c %Y "$CSV_PATH" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING_TASK="true"
    fi
    # Copy to tmp for verifier
    cp "$CSV_PATH" /tmp/breakdown_queue.csv
    chmod 666 /tmp/breakdown_queue.csv
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "script_exists": $SCRIPT_EXISTS,
    "script_created_during_task": $SCRIPT_CREATED_DURING_TASK,
    "csv_exists": $CSV_EXISTS,
    "csv_created_during_task": $CSV_CREATED_DURING_TASK
}
EOF

rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="