#!/bin/bash
echo "=== Exporting Operational Limits Reconfig Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_ts 2>/dev/null || echo "0")
OUTPUT="/home/ga/Desktop/limits_change_report.json"

FILE_EXISTS="false"
FILE_IS_NEW="false"
FILE_MTIME=0

if [ -f "$OUTPUT" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$OUTPUT" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_IS_NEW="true"
    fi
fi

# Query current limits via COSMOS JSON-RPC API to verify agent changed them
CURRENT_LIMITS=$(cosmos_api "get_limits" '"INST","HEALTH_STATUS","TEMP1"' 2>/dev/null | jq -c '.result // []' 2>/dev/null || echo "[]")
INITIAL_LIMITS=$(cat /tmp/initial_limits.json 2>/dev/null || echo "[]")

echo "Initial limits: $INITIAL_LIMITS"
echo "Current limits: $CURRENT_LIMITS"

# Take final screenshot
take_screenshot /tmp/task_end.png

# Package everything into the result JSON
cat > /tmp/operational_limits_reconfig_result.json << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_mtime": $FILE_MTIME,
    "initial_limits": $INITIAL_LIMITS,
    "current_limits": $CURRENT_LIMITS
}
EOF

echo "File exists: $FILE_EXISTS"
echo "File is new: $FILE_IS_NEW"
echo "=== Export Complete ==="