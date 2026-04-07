#!/bin/bash
echo "=== Exporting Patient Transport Handoff Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot (captures the post-disconnect state)
take_screenshot /tmp/task_final_screenshot.png

# --- DATA COLLECTION ---

# 1. Timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 2. Window Analysis (Final State)
# We need to check if Multiparameter is GONE and Pulse Oximeter is PRESENT
CURRENT_WINDOWS=$(DISPLAY=:1 wmctrl -l 2>/dev/null)

MULTIPARAMETER_PRESENT="false"
if echo "$CURRENT_WINDOWS" | grep -iE "multiparameter|multiParam" > /dev/null; then
    MULTIPARAMETER_PRESENT="true"
fi

PULSE_OX_PRESENT="false"
if echo "$CURRENT_WINDOWS" | grep -iE "pulse.?ox|oximeter" > /dev/null; then
    PULSE_OX_PRESENT="true"
fi

VITAL_SIGNS_PRESENT="false"
if echo "$CURRENT_WINDOWS" | grep -iE "vital.?sign|VitalSign" > /dev/null; then
    VITAL_SIGNS_PRESENT="true"
fi

# 3. Log Analysis (Historical Actions)
# We need to verify that devices were created during the task
LOG_FILE="/home/ga/openice/logs/openice.log"
INITIAL_LOG_SIZE=$(cat /tmp/initial_log_size 2>/dev/null || echo "0")
NEW_LOG=$(tail -c +$((INITIAL_LOG_SIZE + 1)) "$LOG_FILE" 2>/dev/null || echo "")

MULTIPARAMETER_CREATED_LOG="false"
if echo "$NEW_LOG" | grep -iE "multiparameter|multiParam" > /dev/null; then
    MULTIPARAMETER_CREATED_LOG="true"
fi

PULSE_OX_CREATED_LOG="false"
if echo "$NEW_LOG" | grep -iE "pulse.?ox|oximeter" > /dev/null; then
    PULSE_OX_CREATED_LOG="true"
fi

VITAL_SIGNS_LAUNCHED_LOG="false"
if echo "$NEW_LOG" | grep -iE "vital.?sign|VitalSign" > /dev/null; then
    VITAL_SIGNS_LAUNCHED_LOG="true"
fi

# 4. Artifact Verification
OVERLAP_SCREENSHOT_PATH="/home/ga/Desktop/handoff_overlap.png"
OVERLAP_SCREENSHOT_EXISTS="false"
if [ -f "$OVERLAP_SCREENSHOT_PATH" ]; then
    # Verify it was created AFTER task start
    F_MTIME=$(stat -c %Y "$OVERLAP_SCREENSHOT_PATH" 2>/dev/null || echo "0")
    if [ "$F_MTIME" -gt "$TASK_START" ]; then
        OVERLAP_SCREENSHOT_EXISTS="true"
    fi
fi

LOG_REPORT_PATH="/home/ga/Desktop/transport_log.txt"
LOG_REPORT_EXISTS="false"
LOG_REPORT_CONTENT=""
if [ -f "$LOG_REPORT_PATH" ]; then
    F_MTIME=$(stat -c %Y "$LOG_REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$F_MTIME" -gt "$TASK_START" ]; then
        LOG_REPORT_EXISTS="true"
        LOG_REPORT_CONTENT=$(cat "$LOG_REPORT_PATH")
    fi
fi

# 5. OpenICE Status
OPENICE_RUNNING="false"
if is_openice_running; then
    OPENICE_RUNNING="true"
fi

# --- JSON EXPORT ---
create_result_json << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "openice_running": $OPENICE_RUNNING,
    "final_state": {
        "multiparameter_window_present": $MULTIPARAMETER_PRESENT,
        "pulse_ox_window_present": $PULSE_OX_PRESENT,
        "vital_signs_window_present": $VITAL_SIGNS_PRESENT
    },
    "history_log": {
        "multiparameter_created": $MULTIPARAMETER_CREATED_LOG,
        "pulse_ox_created": $PULSE_OX_CREATED_LOG,
        "vital_signs_launched": $VITAL_SIGNS_LAUNCHED_LOG
    },
    "artifacts": {
        "overlap_screenshot_exists": $OVERLAP_SCREENSHOT_EXISTS,
        "overlap_screenshot_path": "$OVERLAP_SCREENSHOT_PATH",
        "log_report_exists": $LOG_REPORT_EXISTS,
        "log_report_content": "$(escape_json_value "$LOG_REPORT_CONTENT")"
    },
    "final_screenshot_path": "/tmp/task_final_screenshot.png"
}
EOF

echo "=== Export Complete ==="
cat /tmp/task_result.json