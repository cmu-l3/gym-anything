#!/bin/bash
echo "=== Exporting Closed-Loop Telemetry Response Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/closed_loop_telemetry_start_ts 2>/dev/null || echo "0")
INITIAL_CMD_COUNT=$(cat /tmp/closed_loop_telemetry_initial_cmd_count 2>/dev/null || echo "0")

SCRIPT_FILE="/home/ga/Desktop/closed_loop.py"
REPORT_FILE="/home/ga/Desktop/automation_report.json"

SCRIPT_EXISTS=false
SCRIPT_IS_NEW=false
REPORT_EXISTS=false
REPORT_IS_NEW=false

# Check python script
if [ -f "$SCRIPT_FILE" ]; then
    SCRIPT_EXISTS=true
    SCRIPT_MTIME=$(stat -c %Y "$SCRIPT_FILE" 2>/dev/null || echo "0")
    if [ "$SCRIPT_MTIME" -gt "$TASK_START" ]; then
        SCRIPT_IS_NEW=true
    fi
fi

# Check JSON report
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS=true
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_IS_NEW=true
    fi
fi

# Query current COLLECT command count from live system
CURRENT_CMD_COUNT=$(cosmos_api "get_cmd_cnt" '"INST","COLLECT"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null || echo "0")

echo "Initial COLLECT count: $INITIAL_CMD_COUNT"
echo "Current COLLECT count: $CURRENT_CMD_COUNT"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/closed_loop_telemetry_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/closed_loop_telemetry_end.png 2>/dev/null || true

# Write export metadata
cat > /tmp/closed_loop_telemetry_response_result.json << EOF
{
    "task_start": $TASK_START,
    "script_exists": $SCRIPT_EXISTS,
    "script_is_new": $SCRIPT_IS_NEW,
    "report_exists": $REPORT_EXISTS,
    "report_is_new": $REPORT_IS_NEW,
    "initial_cmd_count": $INITIAL_CMD_COUNT,
    "current_cmd_count": $CURRENT_CMD_COUNT
}
EOF

echo "Script exists: $SCRIPT_EXISTS (New: $SCRIPT_IS_NEW)"
echo "Report exists: $REPORT_EXISTS (New: $REPORT_IS_NEW)"
echo "=== Export Complete ==="