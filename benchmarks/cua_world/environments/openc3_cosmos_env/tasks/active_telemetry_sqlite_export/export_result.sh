#!/bin/bash
echo "=== Exporting Active Telemetry SQLite Export Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/active_telemetry_sqlite_export_start_ts 2>/dev/null || echo "0")
INITIAL_CMD_COUNT=$(cat /tmp/active_telemetry_initial_cmd_count 2>/dev/null || echo "0")
OUTPUT="/home/ga/Desktop/telemetry_archive.db"

FILE_EXISTS=false
FILE_IS_NEW=false
FILE_MTIME=0
FILE_SIZE=0

# Verify file presence and freshness
if [ -f "$OUTPUT" ]; then
    FILE_EXISTS=true
    FILE_MTIME=$(stat -c %Y "$OUTPUT" 2>/dev/null || echo "0")
    FILE_SIZE=$(stat -c %s "$OUTPUT" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_IS_NEW=true
    fi
fi

# Query current command count via OpenC3 JSON-RPC API
CURRENT_CMD_COUNT=$(cosmos_api "get_cmd_cnt" '"INST","COLLECT"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null || echo "0")

# Take final trajectory screenshot
take_screenshot /tmp/active_telemetry_sqlite_export_end.png

# Bundle result meta-data for the verifier script
cat > /tmp/active_telemetry_sqlite_export_result.json << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_mtime": $FILE_MTIME,
    "file_size": $FILE_SIZE,
    "initial_cmd_count": $INITIAL_CMD_COUNT,
    "current_cmd_count": $CURRENT_CMD_COUNT
}
EOF

echo "File exists: $FILE_EXISTS"
echo "File is new: $FILE_IS_NEW"
echo "Initial command count: $INITIAL_CMD_COUNT"
echo "Current command count: $CURRENT_CMD_COUNT"
echo "=== Export Complete ==="