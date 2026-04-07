#!/bin/bash
# Export script for check_in_appointment task
# Exports appointment status and verification data to JSON

echo "=== Exporting Check-In Appointment Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

if [ -f /tmp/task_final_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_final_state.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SIZE} bytes"
fi

# Target patient
PATIENT_PID=3
EXPECTED_STATUS="@"

# Get appointment EID
APPT_EID=$(cat /tmp/appointment_eid.txt 2>/dev/null || echo "0")
INITIAL_STATUS=$(cat /tmp/initial_appointment_status.txt 2>/dev/null || echo "unknown")

echo ""
echo "=== Querying Appointment Status ==="
echo "Appointment EID: $APPT_EID"
echo "Initial status: $INITIAL_STATUS"

# Query current appointment status
TODAY=$(date +%Y-%m-%d)
APPT_DATA=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e "SELECT pc_eid, pc_pid, pc_eventDate, pc_startTime, pc_apptstatus, UNIX_TIMESTAMP(pc_time) as modified_time, pc_title FROM openemr_postcalendar_events WHERE pc_pid=${PATIENT_PID} AND pc_eventDate='${TODAY}' ORDER BY pc_eid DESC LIMIT 1" 2>/dev/null)

echo "Raw appointment data: $APPT_DATA"

# Parse appointment data
APPT_FOUND="false"
CURRENT_EID=""
CURRENT_PID=""
CURRENT_DATE=""
CURRENT_TIME=""
CURRENT_STATUS=""
MODIFIED_TIME="0"
CURRENT_TITLE=""

if [ -n "$APPT_DATA" ]; then
    APPT_FOUND="true"
    CURRENT_EID=$(echo "$APPT_DATA" | cut -f1)
    CURRENT_PID=$(echo "$APPT_DATA" | cut -f2)
    CURRENT_DATE=$(echo "$APPT_DATA" | cut -f3)
    CURRENT_TIME=$(echo "$APPT_DATA" | cut -f4)
    CURRENT_STATUS=$(echo "$APPT_DATA" | cut -f5)
    MODIFIED_TIME=$(echo "$APPT_DATA" | cut -f6)
    CURRENT_TITLE=$(echo "$APPT_DATA" | cut -f7)
    
    echo ""
    echo "Parsed appointment data:"
    echo "  EID: $CURRENT_EID"
    echo "  PID: $CURRENT_PID"
    echo "  Date: $CURRENT_DATE"
    echo "  Time: $CURRENT_TIME"
    echo "  Status: '$CURRENT_STATUS'"
    echo "  Modified: $MODIFIED_TIME"
    echo "  Title: $CURRENT_TITLE"
fi

# Determine if status is now "Arrived" (@)
STATUS_IS_ARRIVED="false"
if [ "$CURRENT_STATUS" = "@" ]; then
    STATUS_IS_ARRIVED="true"
    echo "SUCCESS: Status is '@' (Arrived)"
elif [ "$CURRENT_STATUS" = "~" ]; then
    echo "PARTIAL: Status is '~' (Arrived Late) - acceptable"
    STATUS_IS_ARRIVED="true"
elif [ "$CURRENT_STATUS" = "<" ]; then
    echo "PARTIAL: Status is '<' (In Exam Room) - acceptable"
    STATUS_IS_ARRIVED="true"
else
    echo "FAIL: Status is '$CURRENT_STATUS' (not Arrived)"
fi

# Check if status changed from initial
STATUS_CHANGED="false"
if [ "$INITIAL_STATUS" != "$CURRENT_STATUS" ]; then
    STATUS_CHANGED="true"
    echo "Status changed from '$INITIAL_STATUS' to '$CURRENT_STATUS'"
else
    echo "WARNING: Status unchanged from '$INITIAL_STATUS'"
fi

# Check if modification happened during task
MODIFIED_DURING_TASK="false"
if [ "$MODIFIED_TIME" -gt "$TASK_START" ]; then
    MODIFIED_DURING_TASK="true"
    echo "Appointment modified during task execution"
else
    echo "WARNING: No modification detected during task"
fi

# Check if Firefox is still running
FIREFOX_RUNNING="false"
if pgrep -f firefox > /dev/null; then
    FIREFOX_RUNNING="true"
fi

# Escape title for JSON
CURRENT_TITLE_ESCAPED=$(echo "$CURRENT_TITLE" | sed 's/"/\\"/g' | tr '\n' ' ')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/checkin_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": ${TASK_START:-0},
    "task_end_time": ${TASK_END:-0},
    "patient_pid": ${PATIENT_PID},
    "appointment_eid": "${APPT_EID}",
    "appointment_found": ${APPT_FOUND},
    "appointment": {
        "eid": "${CURRENT_EID}",
        "pid": "${CURRENT_PID}",
        "date": "${CURRENT_DATE}",
        "start_time": "${CURRENT_TIME}",
        "status": "${CURRENT_STATUS}",
        "modified_time": ${MODIFIED_TIME:-0},
        "title": "${CURRENT_TITLE_ESCAPED}"
    },
    "initial_status": "${INITIAL_STATUS}",
    "expected_status": "${EXPECTED_STATUS}",
    "status_is_arrived": ${STATUS_IS_ARRIVED},
    "status_changed": ${STATUS_CHANGED},
    "modified_during_task": ${MODIFIED_DURING_TASK},
    "firefox_running": ${FIREFOX_RUNNING},
    "screenshot_exists": $([ -f "/tmp/task_final_state.png" ] && echo "true" || echo "false"),
    "today_date": "${TODAY}",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/check_in_result.json 2>/dev/null || sudo rm -f /tmp/check_in_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/check_in_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/check_in_result.json
chmod 666 /tmp/check_in_result.json 2>/dev/null || sudo chmod 666 /tmp/check_in_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat /tmp/check_in_result.json
echo ""
echo "=== Export Complete ==="