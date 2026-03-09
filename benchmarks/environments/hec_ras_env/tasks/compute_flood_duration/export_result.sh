#!/bin/bash
echo "=== Exporting compute_flood_duration results ==="

# 1. Timestamps and File Checks
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

CSV_PATH="/home/ga/Documents/hec_ras_results/flood_duration.csv"
SCRIPT_PATH="/home/ga/Documents/hec_ras_results/flood_duration_analysis.py"

# CSV Check
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c %s "$CSV_PATH")
    CSV_MTIME=$(stat -c %Y "$CSV_PATH")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_CREATED_DURING_TASK="true"
    else
        CSV_CREATED_DURING_TASK="false"
    fi
else
    CSV_EXISTS="false"
    CSV_SIZE="0"
    CSV_CREATED_DURING_TASK="false"
fi

# Script Check
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    SCRIPT_SIZE=$(stat -c %s "$SCRIPT_PATH")
else
    SCRIPT_EXISTS="false"
    SCRIPT_SIZE="0"
fi

# 2. Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 3. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    "csv_created_during_task": $CSV_CREATED_DURING_TASK,
    "script_exists": $SCRIPT_EXISTS,
    "script_size": $SCRIPT_SIZE,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result metadata saved to /tmp/task_result.json"
echo "=== Export complete ==="