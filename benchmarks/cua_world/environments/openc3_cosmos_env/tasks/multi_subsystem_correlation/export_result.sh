#!/bin/bash
echo "=== Exporting Multi-Subsystem Correlation Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/multi_subsystem_correlation_start_ts 2>/dev/null || echo "0")
OUTPUT="/home/ga/Desktop/correlation_report.json"

FILE_EXISTS=false
FILE_IS_NEW=false
FILE_MTIME=0

if [ -f "$OUTPUT" ]; then
    FILE_EXISTS=true
    FILE_MTIME=$(stat -c %Y "$OUTPUT" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_IS_NEW=true
    fi
fi

# Verify API is streaming (query ADCS Q1 and HEALTH_STATUS TEMP1 to confirm target health)
# This provides an anti-gaming check that the data source was actively available.
Q1_VAL=$(cosmos_tlm "INST ADCS Q1" 2>/dev/null || echo "unknown")
TEMP1_VAL=$(cosmos_tlm "INST HEALTH_STATUS TEMP1" 2>/dev/null || echo "unknown")

# Take final screenshot
DISPLAY=:1 import -window root /tmp/multi_subsystem_correlation_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/multi_subsystem_correlation_end.png 2>/dev/null || true

cat > /tmp/multi_subsystem_correlation_result.json << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_mtime": $FILE_MTIME,
    "api_active": $([ "$Q1_VAL" != "unknown" ] && [ "$TEMP1_VAL" != "unknown" ] && echo "true" || echo "false")
}
EOF

echo "File exists: $FILE_EXISTS"
echo "File is new: $FILE_IS_NEW"
echo "API Active: $([ "$Q1_VAL" != "unknown" ] && [ "$TEMP1_VAL" != "unknown" ] && echo "true" || echo "false")"
echo "=== Export Complete ==="