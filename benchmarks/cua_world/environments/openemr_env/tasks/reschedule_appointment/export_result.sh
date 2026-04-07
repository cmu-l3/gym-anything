#!/bin/bash
# Export script for Reschedule Appointment task
# Collects all verification data and saves to JSON

echo "=== Exporting Reschedule Appointment Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
echo "Capturing final screenshot..."
take_screenshot /tmp/task_final_state.png

# Get timestamps and dates
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_DATE=$(cat /tmp/task_start_date.txt 2>/dev/null || date +%Y-%m-%d)
ORIGINAL_DATE=$(cat /tmp/original_appt_date.txt 2>/dev/null || date -d "+1 day" +%Y-%m-%d)
TARGET_DATE=$(cat /tmp/target_appt_date.txt 2>/dev/null || date -d "+2 days" +%Y-%m-%d)
ORIGINAL_APPT_ID=$(cat /tmp/original_appt_id.txt 2>/dev/null || echo "0")
SETUP_APPT_COUNT=$(cat /tmp/setup_appt_count.txt 2>/dev/null || echo "1")

TASK_END=$(date +%s)

echo "Task timing: start=$TASK_START, end=$TASK_END"
echo "Original date: $ORIGINAL_DATE, Target date: $TARGET_DATE"
echo "Original appointment ID: $ORIGINAL_APPT_ID"

PATIENT_PID=3

# Query: Check for appointment at NEW date/time (target)
echo ""
echo "=== Checking for appointment at new date/time ==="
NEW_APPT_QUERY="SELECT pc_eid, pc_pid, pc_eventDate, pc_startTime, pc_endTime, pc_duration, pc_title, pc_catid 
FROM openemr_postcalendar_events 
WHERE pc_pid = $PATIENT_PID 
  AND pc_eventDate = '$TARGET_DATE'
  AND (pc_startTime LIKE '14:30%' OR pc_startTime = '14:30:00')
ORDER BY pc_eid DESC LIMIT 1"

NEW_APPT_DATA=$(openemr_query "$NEW_APPT_QUERY" 2>/dev/null)
echo "New appointment query result: $NEW_APPT_DATA"

# Parse new appointment data
NEW_APPT_FOUND="false"
NEW_APPT_EID=""
NEW_APPT_DATE=""
NEW_APPT_START=""
NEW_APPT_END=""
NEW_APPT_DURATION=""
NEW_APPT_TITLE=""
NEW_APPT_CATID=""

if [ -n "$NEW_APPT_DATA" ]; then
    NEW_APPT_FOUND="true"
    NEW_APPT_EID=$(echo "$NEW_APPT_DATA" | cut -f1)
    NEW_APPT_DATE=$(echo "$NEW_APPT_DATA" | cut -f3)
    NEW_APPT_START=$(echo "$NEW_APPT_DATA" | cut -f4)
    NEW_APPT_END=$(echo "$NEW_APPT_DATA" | cut -f5)
    NEW_APPT_DURATION=$(echo "$NEW_APPT_DATA" | cut -f6)
    NEW_APPT_TITLE=$(echo "$NEW_APPT_DATA" | cut -f7)
    NEW_APPT_CATID=$(echo "$NEW_APPT_DATA" | cut -f8)
    echo "Found new appointment: EID=$NEW_APPT_EID, Date=$NEW_APPT_DATE, Time=$NEW_APPT_START"
fi

# Query: Check if ORIGINAL time slot still has appointment
echo ""
echo "=== Checking original time slot ==="
ORIG_SLOT_QUERY="SELECT COUNT(*) FROM openemr_postcalendar_events 
WHERE pc_pid = $PATIENT_PID 
  AND pc_eventDate = '$ORIGINAL_DATE'
  AND (pc_startTime LIKE '10:00%' OR pc_startTime = '10:00:00')"

ORIG_SLOT_COUNT=$(openemr_query "$ORIG_SLOT_QUERY" 2>/dev/null || echo "1")
echo "Appointments at original slot: $ORIG_SLOT_COUNT"

ORIGINAL_SLOT_CLEARED="false"
if [ "$ORIG_SLOT_COUNT" = "0" ]; then
    ORIGINAL_SLOT_CLEARED="true"
    echo "Original slot is cleared (good - appointment was moved)"
else
    echo "Original slot still has appointment (appointment may have been duplicated)"
fi

# Query: Count total appointments for patient in date range
echo ""
echo "=== Counting total appointments in date range ==="
TOTAL_QUERY="SELECT COUNT(*) FROM openemr_postcalendar_events 
WHERE pc_pid = $PATIENT_PID 
  AND pc_eventDate >= '$ORIGINAL_DATE'
  AND pc_eventDate <= '$TARGET_DATE'"

TOTAL_APPT_COUNT=$(openemr_query "$TOTAL_QUERY" 2>/dev/null || echo "0")
echo "Total appointments in range: $TOTAL_APPT_COUNT (started with $SETUP_APPT_COUNT)"

SINGLE_APPOINTMENT="false"
if [ "$TOTAL_APPT_COUNT" = "1" ]; then
    SINGLE_APPOINTMENT="true"
    echo "Single appointment (good - rescheduled, not duplicated)"
elif [ "$TOTAL_APPT_COUNT" = "0" ]; then
    echo "No appointments found (appointment may have been deleted)"
else
    echo "Multiple appointments ($TOTAL_APPT_COUNT) - possible duplication"
fi

# Check if appointment was modified (not the original)
APPT_MODIFIED="false"
if [ -n "$NEW_APPT_EID" ]; then
    if [ "$NEW_APPT_EID" = "$ORIGINAL_APPT_ID" ]; then
        APPT_MODIFIED="true"
        echo "Same appointment ID - appointment was edited in place"
    else
        echo "Different appointment ID - may be new appointment created"
    fi
fi

# Validate date is correct
DATE_CORRECT="false"
if [ "$NEW_APPT_DATE" = "$TARGET_DATE" ]; then
    DATE_CORRECT="true"
fi

# Validate time is correct (2:30 PM = 14:30)
TIME_CORRECT="false"
if echo "$NEW_APPT_START" | grep -q "14:30"; then
    TIME_CORRECT="true"
fi

# Check duration preserved (should be ~1800 seconds = 30 min)
DURATION_PRESERVED="false"
if [ -n "$NEW_APPT_DURATION" ]; then
    # Duration could be stored as seconds or minutes depending on version
    DUR_NUM=$(echo "$NEW_APPT_DURATION" | grep -oE '[0-9]+')
    if [ "$DUR_NUM" -ge 1500 ] && [ "$DUR_NUM" -le 2100 ]; then
        DURATION_PRESERVED="true"
    elif [ "$DUR_NUM" -ge 25 ] && [ "$DUR_NUM" -le 35 ]; then
        # Duration in minutes
        DURATION_PRESERVED="true"
    fi
fi

# Debug: Show all appointments for patient
echo ""
echo "=== All appointments for patient in date range ==="
openemr_query "SELECT pc_eid, pc_eventDate, pc_startTime, pc_title FROM openemr_postcalendar_events WHERE pc_pid = $PATIENT_PID AND pc_eventDate >= '$ORIGINAL_DATE' AND pc_eventDate <= '$TARGET_DATE' ORDER BY pc_eventDate, pc_startTime" 2>/dev/null

# Escape strings for JSON
NEW_APPT_TITLE_ESC=$(echo "$NEW_APPT_TITLE" | sed 's/"/\\"/g' | tr -d '\n')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/reschedule_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "patient_pid": $PATIENT_PID,
    "original_date": "$ORIGINAL_DATE",
    "target_date": "$TARGET_DATE",
    "original_appt_id": "$ORIGINAL_APPT_ID",
    "setup_appt_count": $SETUP_APPT_COUNT,
    "new_appointment": {
        "found": $NEW_APPT_FOUND,
        "eid": "$NEW_APPT_EID",
        "date": "$NEW_APPT_DATE",
        "start_time": "$NEW_APPT_START",
        "end_time": "$NEW_APPT_END",
        "duration": "$NEW_APPT_DURATION",
        "title": "$NEW_APPT_TITLE_ESC",
        "category_id": "$NEW_APPT_CATID"
    },
    "validation": {
        "date_correct": $DATE_CORRECT,
        "time_correct": $TIME_CORRECT,
        "original_slot_cleared": $ORIGINAL_SLOT_CLEARED,
        "single_appointment": $SINGLE_APPOINTMENT,
        "duration_preserved": $DURATION_PRESERVED,
        "appointment_modified": $APPT_MODIFIED
    },
    "counts": {
        "original_slot_count": $ORIG_SLOT_COUNT,
        "total_in_range": $TOTAL_APPT_COUNT
    },
    "screenshot_exists": $([ -f "/tmp/task_final_state.png" ] && echo "true" || echo "false"),
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Save to standard location
rm -f /tmp/reschedule_appointment_result.json 2>/dev/null || sudo rm -f /tmp/reschedule_appointment_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/reschedule_appointment_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/reschedule_appointment_result.json
chmod 666 /tmp/reschedule_appointment_result.json 2>/dev/null || sudo chmod 666 /tmp/reschedule_appointment_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat /tmp/reschedule_appointment_result.json
echo ""
echo "=== Export Complete ==="