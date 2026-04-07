#!/bin/bash
# Export script for Modify Appointment Details task
# Exports current appointment state for verification

echo "=== Exporting Modify Appointment Details Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

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

# Get stored values from setup
PATIENT_PID=2
ORIGINAL_APPT_ID=$(cat /tmp/original_appt_id.txt 2>/dev/null || echo "0")
APPOINTMENT_DATE=$(cat /tmp/appointment_date.txt 2>/dev/null || echo "")
INITIAL_CATID=$(cat /tmp/initial_catid.txt 2>/dev/null || echo "")
INITIAL_DURATION=$(cat /tmp/initial_duration.txt 2>/dev/null || echo "900")

echo "Original appointment ID: $ORIGINAL_APPT_ID"
echo "Appointment date: $APPOINTMENT_DATE"
echo "Initial category ID: $INITIAL_CATID"
echo "Initial duration: $INITIAL_DURATION"

# Get initial state for comparison
INITIAL_STATE=$(cat /tmp/initial_appointment_state.txt 2>/dev/null || echo "")
echo "Initial state: $INITIAL_STATE"

# Query current appointment state
echo ""
echo "=== Querying current appointment state ==="
CURRENT_STATE=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT pc_eid, pc_catid, pc_duration, pc_hometext, pc_eventDate, pc_startTime, pc_endTime, pc_pid, pc_title 
     FROM openemr_postcalendar_events 
     WHERE pc_pid=$PATIENT_PID AND pc_eventDate='$APPOINTMENT_DATE'
     ORDER BY pc_eid DESC LIMIT 1" 2>/dev/null)

echo "Current appointment state: $CURRENT_STATE"

# Parse current state
APPT_EXISTS="false"
CURRENT_EID=""
CURRENT_CATID=""
CURRENT_DURATION=""
CURRENT_COMMENT=""
CURRENT_DATE=""
CURRENT_START_TIME=""
CURRENT_END_TIME=""
CURRENT_PID=""
CURRENT_TITLE=""

if [ -n "$CURRENT_STATE" ]; then
    APPT_EXISTS="true"
    CURRENT_EID=$(echo "$CURRENT_STATE" | cut -f1)
    CURRENT_CATID=$(echo "$CURRENT_STATE" | cut -f2)
    CURRENT_DURATION=$(echo "$CURRENT_STATE" | cut -f3)
    CURRENT_COMMENT=$(echo "$CURRENT_STATE" | cut -f4)
    CURRENT_DATE=$(echo "$CURRENT_STATE" | cut -f5)
    CURRENT_START_TIME=$(echo "$CURRENT_STATE" | cut -f6)
    CURRENT_END_TIME=$(echo "$CURRENT_STATE" | cut -f7)
    CURRENT_PID=$(echo "$CURRENT_STATE" | cut -f8)
    CURRENT_TITLE=$(echo "$CURRENT_STATE" | cut -f9)
    
    echo ""
    echo "Parsed current values:"
    echo "  - EID: $CURRENT_EID"
    echo "  - Category ID: $CURRENT_CATID"
    echo "  - Duration: $CURRENT_DURATION seconds ($(($CURRENT_DURATION / 60)) minutes)"
    echo "  - Comment: $CURRENT_COMMENT"
    echo "  - Date: $CURRENT_DATE"
    echo "  - Start Time: $CURRENT_START_TIME"
    echo "  - End Time: $CURRENT_END_TIME"
    echo "  - Patient PID: $CURRENT_PID"
    echo "  - Title: $CURRENT_TITLE"
else
    echo "WARNING: No appointment found for patient on $APPOINTMENT_DATE"
fi

# Get Office Visit category ID for comparison
OFFICE_VISIT_CATID=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT pc_catid FROM openemr_postcalendar_categories WHERE pc_catname LIKE '%Office%' LIMIT 1" 2>/dev/null || echo "")

# Get category name for current category
CURRENT_CAT_NAME=""
if [ -n "$CURRENT_CATID" ]; then
    CURRENT_CAT_NAME=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
        "SELECT pc_catname FROM openemr_postcalendar_categories WHERE pc_catid=$CURRENT_CATID" 2>/dev/null || echo "")
fi
echo "  - Category Name: $CURRENT_CAT_NAME"

# Determine if changes were made
DURATION_CHANGED="false"
CATEGORY_CHANGED="false"
COMMENT_CHANGED="false"
DATETIME_PRESERVED="false"

if [ "$CURRENT_DURATION" != "$INITIAL_DURATION" ] && [ -n "$CURRENT_DURATION" ]; then
    DURATION_CHANGED="true"
fi

if [ "$CURRENT_CATID" != "$INITIAL_CATID" ] && [ -n "$CURRENT_CATID" ]; then
    CATEGORY_CHANGED="true"
fi

# Check if comment was updated with relevant keywords
COMMENT_LOWER=$(echo "$CURRENT_COMMENT" | tr '[:upper:]' '[:lower:]')
if echo "$COMMENT_LOWER" | grep -qE "(additional|concern|extended|more time|longer)"; then
    COMMENT_CHANGED="true"
fi

# Check if date and time are preserved
if [ "$CURRENT_DATE" = "$APPOINTMENT_DATE" ] && [ "$CURRENT_START_TIME" = "10:00:00" ]; then
    DATETIME_PRESERVED="true"
fi

echo ""
echo "Change detection:"
echo "  - Duration changed: $DURATION_CHANGED (was $INITIAL_DURATION, now $CURRENT_DURATION)"
echo "  - Category changed: $CATEGORY_CHANGED (was $INITIAL_CATID, now $CURRENT_CATID)"
echo "  - Comment updated: $COMMENT_CHANGED"
echo "  - DateTime preserved: $DATETIME_PRESERVED"

# Escape special characters for JSON
CURRENT_COMMENT_ESCAPED=$(echo "$CURRENT_COMMENT" | sed 's/"/\\"/g' | sed 's/\\/\\\\/g' | tr '\n' ' ' | tr '\r' ' ')
CURRENT_TITLE_ESCAPED=$(echo "$CURRENT_TITLE" | sed 's/"/\\"/g' | sed 's/\\/\\\\/g' | tr '\n' ' ' | tr '\r' ' ')
CURRENT_CAT_NAME_ESCAPED=$(echo "$CURRENT_CAT_NAME" | sed 's/"/\\"/g' | sed 's/\\/\\\\/g' | tr '\n' ' ' | tr '\r' ' ')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/modify_appt_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "task_duration_seconds": $((TASK_END - TASK_START)),
    "patient_pid": $PATIENT_PID,
    "original_appt_id": "$ORIGINAL_APPT_ID",
    "appointment_date": "$APPOINTMENT_DATE",
    "appointment_exists": $APPT_EXISTS,
    "initial_state": {
        "catid": "$INITIAL_CATID",
        "duration": $INITIAL_DURATION,
        "start_time": "10:00:00"
    },
    "current_state": {
        "eid": "$CURRENT_EID",
        "pid": "$CURRENT_PID",
        "catid": "$CURRENT_CATID",
        "category_name": "$CURRENT_CAT_NAME_ESCAPED",
        "duration": ${CURRENT_DURATION:-0},
        "comment": "$CURRENT_COMMENT_ESCAPED",
        "title": "$CURRENT_TITLE_ESCAPED",
        "date": "$CURRENT_DATE",
        "start_time": "$CURRENT_START_TIME",
        "end_time": "$CURRENT_END_TIME"
    },
    "changes_detected": {
        "duration_changed": $DURATION_CHANGED,
        "category_changed": $CATEGORY_CHANGED,
        "comment_updated": $COMMENT_CHANGED,
        "datetime_preserved": $DATETIME_PRESERVED
    },
    "reference": {
        "office_visit_catid": "$OFFICE_VISIT_CATID",
        "expected_duration": 1800
    },
    "screenshot_exists": $([ -f "/tmp/task_final_state.png" ] && echo "true" || echo "false"),
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/modify_appointment_result.json 2>/dev/null || sudo rm -f /tmp/modify_appointment_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/modify_appointment_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/modify_appointment_result.json
chmod 666 /tmp/modify_appointment_result.json 2>/dev/null || sudo chmod 666 /tmp/modify_appointment_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/modify_appointment_result.json"
cat /tmp/modify_appointment_result.json
echo ""
echo "=== Export Complete ==="