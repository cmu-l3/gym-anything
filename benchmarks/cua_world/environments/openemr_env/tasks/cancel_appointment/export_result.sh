#!/bin/bash
# Export script for Cancel Appointment task

echo "=== Exporting Cancel Appointment Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot first
echo "Capturing final screenshot..."
take_screenshot /tmp/task_final_state.png

# Read task setup data
SARAH_PID=$(cat /tmp/task_patient_pid.txt 2>/dev/null || echo "0")
APPT_ID=$(cat /tmp/task_appointment_id.txt 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_STATUS=$(cat /tmp/task_initial_status.txt 2>/dev/null || echo "-")
INITIAL_APPT_COUNT=$(cat /tmp/task_initial_appt_count.txt 2>/dev/null || echo "0")

echo "Patient PID: $SARAH_PID"
echo "Appointment EID: $APPT_ID"
echo "Task start timestamp: $TASK_START"
echo "Initial status: '$INITIAL_STATUS'"

# Check if the appointment still exists (not deleted)
echo ""
echo "=== Checking appointment status ==="
APPT_EXISTS=$(openemr_query "SELECT COUNT(*) FROM openemr_postcalendar_events WHERE pc_eid=$APPT_ID" 2>/dev/null || echo "0")

RECORD_PRESERVED="false"
if [ "$APPT_EXISTS" = "1" ]; then
    RECORD_PRESERVED="true"
    echo "Appointment record exists (good - not deleted)"
else
    echo "WARNING: Appointment record NOT found (may have been deleted)"
fi

# Get current appointment data
APPT_DATA=$(openemr_query "SELECT pc_eid, pc_pid, pc_apptstatus, pc_eventDate, pc_startTime, pc_hometext, UNIX_TIMESTAMP(pc_time) FROM openemr_postcalendar_events WHERE pc_eid=$APPT_ID" 2>/dev/null)

echo "Appointment data: $APPT_DATA"

# Parse appointment data
CURRENT_STATUS=""
CURRENT_DATE=""
CURRENT_TIME=""
CURRENT_COMMENTS=""
MODIFIED_TS="0"

if [ -n "$APPT_DATA" ]; then
    CURRENT_STATUS=$(echo "$APPT_DATA" | cut -f3)
    CURRENT_DATE=$(echo "$APPT_DATA" | cut -f4)
    CURRENT_TIME=$(echo "$APPT_DATA" | cut -f5)
    CURRENT_COMMENTS=$(echo "$APPT_DATA" | cut -f6)
    MODIFIED_TS=$(echo "$APPT_DATA" | cut -f7)
    
    echo "Current status: '$CURRENT_STATUS'"
    echo "Current date: $CURRENT_DATE"
    echo "Current time: $CURRENT_TIME"
    echo "Comments: '$CURRENT_COMMENTS'"
    echo "Modified timestamp: $MODIFIED_TS"
fi

# Check if status changed to cancelled
STATUS_CHANGED="false"
CANCELLED_CODES="x X %"
for code in $CANCELLED_CODES; do
    if [ "$CURRENT_STATUS" = "$code" ]; then
        STATUS_CHANGED="true"
        echo "Status changed to cancelled ('$CURRENT_STATUS')"
        break
    fi
done

if [ "$STATUS_CHANGED" = "false" ]; then
    echo "Status NOT changed to cancelled (current: '$CURRENT_STATUS')"
fi

# Check if reason contains expected keywords
REASON_DOCUMENTED="false"
COMMENTS_LOWER=$(echo "$CURRENT_COMMENTS" | tr '[:upper:]' '[:lower:]')
if echo "$COMMENTS_LOWER" | grep -qE "(work|cancel|patient|conflict|request)"; then
    REASON_DOCUMENTED="true"
    echo "Cancellation reason contains expected keywords"
else
    echo "Cancellation reason does not contain expected keywords"
fi

# Check if appointment was modified after task start
MODIFIED_AFTER_START="false"
if [ -n "$MODIFIED_TS" ] && [ "$MODIFIED_TS" != "0" ] && [ "$MODIFIED_TS" -gt "$TASK_START" ]; then
    MODIFIED_AFTER_START="true"
    echo "Appointment was modified after task started"
else
    echo "Appointment modification time not verified"
fi

# Check correct date and time
CORRECT_DATETIME="false"
if [ "$CURRENT_DATE" = "2024-12-20" ] && [ "${CURRENT_TIME:0:5}" = "10:00" ]; then
    CORRECT_DATETIME="true"
    echo "Correct appointment date/time confirmed"
fi

# Get current appointment count for patient (to detect if any appointments were deleted)
CURRENT_APPT_COUNT=$(openemr_query "SELECT COUNT(*) FROM openemr_postcalendar_events WHERE pc_pid=$SARAH_PID" 2>/dev/null || echo "0")
echo "Current appointment count for patient: $CURRENT_APPT_COUNT (was: $INITIAL_APPT_COUNT)"

# Escape comments for JSON
CURRENT_COMMENTS_ESCAPED=$(echo "$CURRENT_COMMENTS" | sed 's/"/\\"/g' | sed 's/\\/\\\\/g' | tr '\n' ' ' | tr '\r' ' ')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/cancel_appt_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $SARAH_PID,
    "appointment_eid": $APPT_ID,
    "task_start_timestamp": $TASK_START,
    "initial_status": "$INITIAL_STATUS",
    "current_status": "$CURRENT_STATUS",
    "record_preserved": $RECORD_PRESERVED,
    "status_changed_to_cancelled": $STATUS_CHANGED,
    "appointment_date": "$CURRENT_DATE",
    "appointment_time": "$CURRENT_TIME",
    "correct_datetime": $CORRECT_DATETIME,
    "comments": "$CURRENT_COMMENTS_ESCAPED",
    "reason_documented": $REASON_DOCUMENTED,
    "modified_timestamp": $MODIFIED_TS,
    "modified_after_start": $MODIFIED_AFTER_START,
    "initial_appt_count": $INITIAL_APPT_COUNT,
    "current_appt_count": $CURRENT_APPT_COUNT,
    "screenshot_exists": $([ -f "/tmp/task_final_state.png" ] && echo "true" || echo "false"),
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/cancel_appointment_result.json 2>/dev/null || sudo rm -f /tmp/cancel_appointment_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/cancel_appointment_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/cancel_appointment_result.json
chmod 666 /tmp/cancel_appointment_result.json 2>/dev/null || sudo chmod 666 /tmp/cancel_appointment_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat /tmp/cancel_appointment_result.json
echo ""
echo "=== Export Complete ==="