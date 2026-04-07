#!/bin/bash
echo "=== Exporting Command Acceptance Test Suite Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/command_acceptance_test_suite_start_ts 2>/dev/null || echo "0")
INITIAL_CMD_COUNT=$(cat /tmp/command_acceptance_test_suite_initial_cmds 2>/dev/null || echo "0")
OUTPUT="/home/ga/Desktop/test_report.json"

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

# Function to get total INST commands safely
get_total_inst_cmds() {
    local total=0
    # Try querying the target overall count
    local target_total=$(cosmos_api "get_cmd_cnt" '"INST"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null)
    if [[ "$target_total" =~ ^[0-9]+$ ]] && [ "$target_total" -gt 0 ]; then
        echo "$target_total"
        return
    fi

    # Fallback: sum common INST commands from dictionary
    for cmd in COLLECT SETPARAMS CLEAR ABORT NOOP ROUTE IGNORE ENABLE DISABLE; do
        local cnt=$(cosmos_api "get_cmd_cnt" "\"INST\",\"$cmd\"" 2>/dev/null | jq -r '.result // 0' 2>/dev/null)
        if [[ "$cnt" =~ ^[0-9]+$ ]]; then
            total=$((total + cnt))
        fi
    done
    echo "$total"
}

CURRENT_CMD_COUNT=$(get_total_inst_cmds)
echo "Initial CMD count: $INITIAL_CMD_COUNT"
echo "Current CMD count: $CURRENT_CMD_COUNT"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/command_acceptance_test_suite_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/command_acceptance_test_suite_end.png 2>/dev/null || true

# Save results to a temporary JSON file to avoid permission issues
TEMP_JSON=$(mktemp /tmp/cmd_test_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_is_new": $FILE_IS_NEW,
    "file_mtime": $FILE_MTIME,
    "initial_cmd_count": $INITIAL_CMD_COUNT,
    "current_cmd_count": $CURRENT_CMD_COUNT
}
EOF

# Move to final location safely
rm -f /tmp/command_acceptance_test_suite_result.json 2>/dev/null || sudo rm -f /tmp/command_acceptance_test_suite_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/command_acceptance_test_suite_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/command_acceptance_test_suite_result.json
chmod 666 /tmp/command_acceptance_test_suite_result.json 2>/dev/null || sudo chmod 666 /tmp/command_acceptance_test_suite_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "File exists: $FILE_EXISTS"
echo "File is new: $FILE_IS_NEW"
echo "=== Export Complete ==="