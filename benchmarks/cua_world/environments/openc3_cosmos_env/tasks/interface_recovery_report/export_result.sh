#!/bin/bash
echo "=== Exporting Interface Recovery Report Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/interface_recovery_start_ts 2>/dev/null || echo "0")
INITIAL_STATE=$(cat /tmp/interface_recovery_initial_state 2>/dev/null || echo "UNKNOWN")
OUTPUT="/home/ga/Desktop/interface_recovery_report.json"

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

# Query current state of the INST_INT interface to verify recovery
CURRENT_INT_STATE=$(cosmos_api "interface_state" '"INST_INT"' 2>/dev/null | jq -r '.result // "UNKNOWN"' 2>/dev/null || echo "UNKNOWN")

echo "Initial INST_INT state: $INITIAL_STATE"
echo "Current INST_INT state: $CURRENT_INT_STATE"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/interface_recovery_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/interface_recovery_end.png 2>/dev/null || true

# Export metadata safely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_mtime": $FILE_MTIME,
    "initial_interface_state": "$INITIAL_STATE",
    "current_interface_state": "$CURRENT_INT_STATE"
}
EOF

rm -f /tmp/interface_recovery_report_result.json 2>/dev/null || sudo rm -f /tmp/interface_recovery_report_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/interface_recovery_report_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/interface_recovery_report_result.json
chmod 666 /tmp/interface_recovery_report_result.json 2>/dev/null || sudo chmod 666 /tmp/interface_recovery_report_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "File exists: $FILE_EXISTS"
echo "File is new: $FILE_IS_NEW"
echo "=== Export Complete ==="