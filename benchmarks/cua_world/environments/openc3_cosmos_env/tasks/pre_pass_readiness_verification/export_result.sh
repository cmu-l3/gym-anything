#!/bin/bash
echo "=== Exporting Pre-Pass Readiness Verification Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/pre_pass_start_ts 2>/dev/null || echo "0")
OUTPUT="/home/ga/Desktop/pre_pass_checklist.json"

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

# Query current command counts
INITIAL_CLEAR_COUNT=$(cat /tmp/pre_pass_initial_clear 2>/dev/null || echo "0")
INITIAL_COLLECT_COUNT=$(cat /tmp/pre_pass_initial_collect 2>/dev/null || echo "0")
CURRENT_CLEAR_COUNT=$(cosmos_api "get_cmd_cnt" '"INST","CLEAR"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null || echo "0")
CURRENT_COLLECT_COUNT=$(cosmos_api "get_cmd_cnt" '"INST","COLLECT"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null || echo "0")

# Determine if INST2_INT is reconnected using multiple fallback checks to ensure robustness
INST2_INT_CONNECTED="false"
RAW_INTERFACES=$(cosmos_api "get_interfaces" "" 2>/dev/null || echo "")

if echo "$RAW_INTERFACES" | grep -q '"INST2_INT","CONNECTED"'; then
    INST2_INT_CONNECTED="true"
elif echo "$RAW_INTERFACES" | jq -e '.result[]? | select(.[0]=="INST2_INT" and .[1]=="CONNECTED")' >/dev/null 2>&1; then
    INST2_INT_CONNECTED="true"
elif echo "$RAW_INTERFACES" | jq -e '.result[]? | select(.name=="INST2_INT" and .state=="CONNECTED")' >/dev/null 2>&1; then
    INST2_INT_CONNECTED="true"
else
    # Fallback to direct interface query
    RAW_INT=$(cosmos_api "get_interface" '"INST2_INT"' 2>/dev/null || echo "")
    if echo "$RAW_INT" | grep -iq "CONNECTED"; then
        INST2_INT_CONNECTED="true"
    fi
fi

# Take final screenshot
DISPLAY=:1 import -window root /tmp/pre_pass_readiness_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/pre_pass_readiness_end.png 2>/dev/null || true

# Construct export JSON
cat > /tmp/pre_pass_readiness_result.json << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_mtime": $FILE_MTIME,
    "initial_clear_count": $INITIAL_CLEAR_COUNT,
    "current_clear_count": $CURRENT_CLEAR_COUNT,
    "initial_collect_count": $INITIAL_COLLECT_COUNT,
    "current_collect_count": $CURRENT_COLLECT_COUNT,
    "inst2_int_connected": $INST2_INT_CONNECTED
}
EOF

echo "File exists: $FILE_EXISTS"
echo "File is new: $FILE_IS_NEW"
echo "INST2_INT Connected: $INST2_INT_CONNECTED"
echo "CLEAR Delta: $(($CURRENT_CLEAR_COUNT - $INITIAL_CLEAR_COUNT))"
echo "COLLECT Delta: $(($CURRENT_COLLECT_COUNT - $INITIAL_COLLECT_COUNT))"
echo "=== Export Complete ==="