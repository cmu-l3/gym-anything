#!/bin/bash
echo "=== Exporting payload_acceleration_profiling Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_ts 2>/dev/null || echo "0")
CSV="/home/ga/Documents/CoppeliaSim/exports/payload_kinematics.csv"
JSON="/home/ga/Documents/CoppeliaSim/exports/payload_safety_report.json"

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Base file checks
CSV_EXISTS="false"
CSV_IS_NEW="false"
JSON_EXISTS="false"
JSON_IS_NEW="false"

if [ -f "$CSV" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c %Y "$CSV" 2>/dev/null || echo "0")
    if [ "$CSV_MTIME" -gt "$TASK_START" ]; then
        CSV_IS_NEW="true"
    fi
fi

if [ -f "$JSON" ]; then
    JSON_EXISTS="true"
    JSON_MTIME=$(stat -c %Y "$JSON" 2>/dev/null || echo "0")
    if [ "$JSON_MTIME" -gt "$TASK_START" ]; then
        JSON_IS_NEW="true"
    fi
fi

# Write metadata result JSON to TMP so verifier can securely copy it and the data files
cat > /tmp/payload_acceleration_result.json << EOF
{
    "task_start": $TASK_START,
    "csv_exists": $CSV_EXISTS,
    "csv_is_new": $CSV_IS_NEW,
    "json_exists": $JSON_EXISTS,
    "json_is_new": $JSON_IS_NEW
}
EOF

echo "=== Export Complete ==="