#!/bin/bash
echo "=== Exporting Composite Health Index Computation Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/health_index_start_ts 2>/dev/null || echo "0")
INITIAL_COLLECTS=$(cat /tmp/health_index_initial_collects 2>/dev/null || echo "0")
OUTPUT="/home/ga/Desktop/health_index_report.json"

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

# Record final COLLECTS value for boundary verification
FINAL_COLLECTS=$(cosmos_tlm "INST HEALTH_STATUS COLLECTS" 2>/dev/null || echo "0")
if [ -z "$FINAL_COLLECTS" ] || [ "$FINAL_COLLECTS" = "null" ]; then
    # Fallback to current API fetch if empty
    FINAL_COLLECTS=$(curl -s -X POST "$OPENC3_URL/openc3-api/api" -H "Content-Type: application/json" -H "Authorization: $(get_cosmos_token)" -d '{"jsonrpc":"2.0","method":"tlm","params":["INST HEALTH_STATUS COLLECTS"],"id":1,"keyword_params":{"type":"FORMATTED","scope":"DEFAULT"}}' | jq -r '.result // 0' 2>/dev/null || echo "0")
fi

echo "Initial COLLECTS: $INITIAL_COLLECTS"
echo "Final COLLECTS: $FINAL_COLLECTS"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/health_index_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/health_index_end.png 2>/dev/null || true

cat > /tmp/health_index_result.json << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_mtime": $FILE_MTIME,
    "initial_collects": $INITIAL_COLLECTS,
    "final_collects": $FINAL_COLLECTS
}
EOF

echo "File exists: $FILE_EXISTS"
echo "File is new: $FILE_IS_NEW"
echo "=== Export Complete ==="