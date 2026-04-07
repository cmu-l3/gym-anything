#!/bin/bash
# Export script for Document No-Show Task
# Queries database and exports all verification data to JSON

echo "=== Exporting Document No-Show Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/task_final_state.png
sleep 1

# Get timing information
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Target patient
PATIENT_PID=2
TODAY=$(date +%Y-%m-%d)

# Get initial state data
INITIAL_EID=$(cat /tmp/initial_appointment_eid.txt 2>/dev/null || echo "0")
INITIAL_STATUS=$(cat /tmp/initial_appointment_status.txt 2>/dev/null || echo "-")

echo "Initial appointment EID: $INITIAL_EID"
echo "Initial status: '$INITIAL_STATUS'"

# Query current appointment state
echo ""
echo "=== Querying current appointment state ==="
APPT_DATA=$(openemr_query "SELECT pc_eid, pc_pid, pc_eventDate, pc_startTime, pc_endTime, pc_apptstatus, pc_hometext, pc_title, UNIX_TIMESTAMP(pc_time) as modified_ts FROM openemr_postcalendar_events WHERE pc_pid=$PATIENT_PID AND pc_eventDate='$TODAY' AND pc_startTime='09:00:00' ORDER BY pc_eid DESC LIMIT 1" 2>/dev/null)

echo "Appointment data: $APPT_DATA"

# Parse appointment data
APPT_FOUND="false"
APPT_EID=""
APPT_DATE=""
APPT_START_TIME=""
APPT_END_TIME=""
APPT_STATUS=""
APPT_COMMENT=""
APPT_TITLE=""
APPT_MODIFIED_TS="0"

if [ -n "$APPT_DATA" ]; then
    APPT_FOUND="true"
    APPT_EID=$(echo "$APPT_DATA" | cut -f1)
    APPT_PID=$(echo "$APPT_DATA" | cut -f2)
    APPT_DATE=$(echo "$APPT_DATA" | cut -f3)
    APPT_START_TIME=$(echo "$APPT_DATA" | cut -f4)
    APPT_END_TIME=$(echo "$APPT_DATA" | cut -f5)
    APPT_STATUS=$(echo "$APPT_DATA" | cut -f6)
    APPT_COMMENT=$(echo "$APPT_DATA" | cut -f7)
    APPT_TITLE=$(echo "$APPT_DATA" | cut -f8)
    APPT_MODIFIED_TS=$(echo "$APPT_DATA" | cut -f9)
    
    echo ""
    echo "Parsed appointment:"
    echo "  EID: $APPT_EID"
    echo "  Date: $APPT_DATE"
    echo "  Time: $APPT_START_TIME - $APPT_END_TIME"
    echo "  Status: '$APPT_STATUS' (was: '$INITIAL_STATUS')"
    echo "  Comment: '$APPT_COMMENT'"
    echo "  Modified timestamp: $APPT_MODIFIED_TS"
fi

# Check if status changed from initial
STATUS_CHANGED="false"
if [ "$APPT_STATUS" != "$INITIAL_STATUS" ]; then
    STATUS_CHANGED="true"
    echo "Status was changed from '$INITIAL_STATUS' to '$APPT_STATUS'"
else
    echo "Status NOT changed (still '$APPT_STATUS')"
fi

# Check if status indicates no-show
# OpenEMR uses: '?' for no-show, 'x' for cancelled, '-' for scheduled
STATUS_IS_NOSHOW="false"
APPT_STATUS_LOWER=$(echo "$APPT_STATUS" | tr '[:upper:]' '[:lower:]')
if [ "$APPT_STATUS" = "?" ] || [ "$APPT_STATUS" = "x" ] || \
   echo "$APPT_STATUS_LOWER" | grep -qE "(no.?show|noshow|ns|@no)"; then
    STATUS_IS_NOSHOW="true"
    echo "Status indicates no-show"
fi

# Check if comment has content
HAS_COMMENT="false"
COMMENT_LENGTH=${#APPT_COMMENT}
if [ "$COMMENT_LENGTH" -gt 10 ]; then
    HAS_COMMENT="true"
    echo "Comment has content ($COMMENT_LENGTH chars)"
fi

# Check if comment mentions contact attempts
COMMENT_HAS_KEYWORDS="false"
COMMENT_LOWER=$(echo "$APPT_COMMENT" | tr '[:upper:]' '[:lower:]')
if echo "$COMMENT_LOWER" | grep -qE "(called|voicemail|message|phone|contact|left|answer)"; then
    COMMENT_HAS_KEYWORDS="true"
    echo "Comment mentions contact attempts"
fi

# Check if appointment was modified during task window
MODIFIED_DURING_TASK="false"
if [ "$APPT_MODIFIED_TS" -gt "$TASK_START" ]; then
    MODIFIED_DURING_TASK="true"
    echo "Appointment modified during task (ts=$APPT_MODIFIED_TS > start=$TASK_START)"
fi

# Check if date/time were preserved
DETAILS_PRESERVED="false"
if [ "$APPT_DATE" = "$TODAY" ] && [ "$APPT_START_TIME" = "09:00:00" ]; then
    DETAILS_PRESERVED="true"
    echo "Appointment date/time preserved correctly"
fi

# Escape special characters for JSON
APPT_COMMENT_ESCAPED=$(echo "$APPT_COMMENT" | sed 's/"/\\"/g' | sed 's/\\/\\\\/g' | tr '\n' ' ' | tr '\r' ' ')
APPT_TITLE_ESCAPED=$(echo "$APPT_TITLE" | sed 's/"/\\"/g' | tr '\n' ' ')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/noshow_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_timing": {
        "start_timestamp": $TASK_START,
        "end_timestamp": $TASK_END,
        "duration_seconds": $((TASK_END - TASK_START))
    },
    "patient": {
        "pid": $PATIENT_PID,
        "expected_date": "$TODAY",
        "expected_time": "09:00:00"
    },
    "initial_state": {
        "eid": "$INITIAL_EID",
        "status": "$INITIAL_STATUS"
    },
    "current_state": {
        "appointment_found": $APPT_FOUND,
        "eid": "$APPT_EID",
        "date": "$APPT_DATE",
        "start_time": "$APPT_START_TIME",
        "end_time": "$APPT_END_TIME",
        "status": "$APPT_STATUS",
        "comment": "$APPT_COMMENT_ESCAPED",
        "title": "$APPT_TITLE_ESCAPED",
        "modified_timestamp": $APPT_MODIFIED_TS
    },
    "verification": {
        "status_changed": $STATUS_CHANGED,
        "status_is_noshow": $STATUS_IS_NOSHOW,
        "has_comment": $HAS_COMMENT,
        "comment_has_keywords": $COMMENT_HAS_KEYWORDS,
        "modified_during_task": $MODIFIED_DURING_TASK,
        "details_preserved": $DETAILS_PRESERVED
    },
    "screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Move to final location
rm -f /tmp/document_noshow_result.json 2>/dev/null || sudo rm -f /tmp/document_noshow_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/document_noshow_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/document_noshow_result.json
chmod 666 /tmp/document_noshow_result.json 2>/dev/null || sudo chmod 666 /tmp/document_noshow_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat /tmp/document_noshow_result.json
echo ""
echo "=== Export Complete ==="