#!/bin/bash
echo "=== Exporting Empirical Limit Calibration Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Stop the ground truth logger
if [ -f /tmp/logger_pid ]; then
    kill $(cat /tmp/logger_pid) 2>/dev/null || true
fi

TASK_START=$(cat /tmp/limit_calibration_start_ts 2>/dev/null || echo "0")
OUTPUT="/home/ga/Desktop/limit_calibration_report.json"

FILE_EXISTS="false"
FILE_IS_NEW="false"
FILE_MTIME="0"

if [ -f "$OUTPUT" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$OUTPUT" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_IS_NEW="true"
    fi
fi

# Query current limits for TEMP3 to verify agent applied them in the system
CURRENT_LIMITS=$(cosmos_api "get_limits" '"INST","HEALTH_STATUS","TEMP3"' | jq -c '.result // []' 2>/dev/null || echo "[]")
INITIAL_LIMITS=$(cat /tmp/limit_calibration_initial_limits 2>/dev/null || echo "[]")

# Take final screenshot
DISPLAY=:1 import -window root /tmp/limit_calibration_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/limit_calibration_end.png 2>/dev/null || true

# Export metadata securely to temp JSON
cat > /tmp/limit_calibration_result.json << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_mtime": $FILE_MTIME,
    "initial_limits": $INITIAL_LIMITS,
    "current_limits": $CURRENT_LIMITS
}
EOF

chmod 666 /tmp/limit_calibration_result.json

echo "File exists: $FILE_EXISTS"
echo "File is new: $FILE_IS_NEW"
echo "Current limits JSON length: ${#CURRENT_LIMITS}"
echo "=== Export Complete ==="