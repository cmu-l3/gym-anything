#!/bin/bash
echo "=== Exporting Multi-Node Communication Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final_screenshot.png

# Timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Check Process Count (Expect >= 2 OpenICE instances)
# We look for java processes running the demo-apps
PROCESS_COUNT=$(pgrep -f "java.*demo-apps" | wc -l)

# 2. Check Log B Existence and Content
LOG_B="/home/ga/Desktop/node_b.log"
LOG_B_EXISTS="false"
LOG_B_SIZE=0
NODE_B_STARTED="false"

if [ -f "$LOG_B" ]; then
    LOG_B_EXISTS="true"
    LOG_B_SIZE=$(stat -c %s "$LOG_B")
    # Check if log B actually contains OpenICE startup logs
    if grep -q "OpenICE" "$LOG_B" || grep -q "Supervisor" "$LOG_B" || grep -q "ICE" "$LOG_B"; then
        NODE_B_STARTED="true"
    fi
fi

# 3. Analyze Logs for Device Creation and Discovery
LOG_A="/home/ga/openice/logs/openice.log"
INITIAL_LOG_A_SIZE=$(cat /tmp/initial_log_a_size 2>/dev/null || echo "0")

# Extract new content from Log A
NEW_LOG_A_CONTENT=$(tail -c +$((INITIAL_LOG_A_SIZE + 1)) "$LOG_A" 2>/dev/null)

# Check Node A (Primary) activity
# Did Node A create an Infusion Pump?
A_CREATED_PUMP="false"
if echo "$NEW_LOG_A_CONTENT" | grep -qi "Infusion Pump"; then
    A_CREATED_PUMP="true"
fi
# Did Node A see the Capnometer (remote)?
A_SAW_CAPNOMETER="false"
if echo "$NEW_LOG_A_CONTENT" | grep -qi "Capnometer"; then
    A_SAW_CAPNOMETER="true"
fi

# Check Node B (Secondary) activity
# Did Node B create a Capnometer?
B_CREATED_CAPNOMETER="false"
if [ "$LOG_B_EXISTS" = "true" ]; then
    if grep -qi "Capnometer" "$LOG_B"; then
        B_CREATED_CAPNOMETER="true"
    fi
fi
# Did Node B see the Infusion Pump (remote)?
B_SAW_PUMP="false"
if [ "$LOG_B_EXISTS" = "true" ]; then
    if grep -qi "Infusion Pump" "$LOG_B"; then
        B_SAW_PUMP="true"
    fi
fi

# 4. Check Report
REPORT_PATH="/home/ga/Desktop/interop_report.txt"
REPORT_EXISTS="false"
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
fi

# 5. Visual Check: Window Count
WINDOW_COUNT=$(DISPLAY=:1 wmctrl -l | grep -i "openice\|supervisor" | wc -l)

# Create Result JSON
create_result_json << EOF
{
    "task_start": $TASK_START,
    "process_count": $PROCESS_COUNT,
    "log_b_exists": $LOG_B_EXISTS,
    "node_b_started_in_log": $NODE_B_STARTED,
    "a_created_pump": $A_CREATED_PUMP,
    "a_saw_capnometer": $A_SAW_CAPNOMETER,
    "b_created_capnometer": $B_CREATED_CAPNOMETER,
    "b_saw_pump": $B_SAW_PUMP,
    "report_exists": $REPORT_EXISTS,
    "window_count": $WINDOW_COUNT,
    "screenshot_path": "/tmp/task_final_screenshot.png"
}
EOF

echo "=== Export Complete ==="
cat /tmp/task_result.json