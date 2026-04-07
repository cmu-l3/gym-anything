#!/bin/bash
# Export script for Schedule Hypertension Follow-up Task

echo "=== Exporting Schedule Followup Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Target patient
PATIENT_PID=3

# Get initial counts
INITIAL_APPT_COUNT=$(cat /tmp/initial_appt_count 2>/dev/null || echo "0")
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Get current appointment count for patient
CURRENT_APPT_COUNT=$(openemr_query "SELECT COUNT(*) FROM openemr_postcalendar_events WHERE pc_pid=$PATIENT_PID" 2>/dev/null || echo "0")

echo "Appointment count: initial=$INITIAL_APPT_COUNT, current=$CURRENT_APPT_COUNT"

# Get today's date and date 14 days ahead
TODAY=$(date +%Y-%m-%d)
MAX_DATE=$(date -d "+14 days" +%Y-%m-%d)

echo "Valid date range: $TODAY to $MAX_DATE"

# Query for new appointments for this patient
# Look for appointments created recently (within last hour to account for timezone issues)
echo ""
echo "=== Querying appointments for patient PID=$PATIENT_PID ==="
ALL_APPTS=$(openemr_query "SELECT pc_eid, pc_pid, pc_eventDate, pc_startTime, pc_endTime, pc_duration, pc_hometext, pc_title, pc_catid FROM openemr_postcalendar_events WHERE pc_pid=$PATIENT_PID ORDER BY pc_eid DESC LIMIT 10" 2>/dev/null)
echo "All appointments for patient:"
echo "$ALL_APPTS"

# Find the most recent appointment (highest pc_eid indicates newest)
NEWEST_APPT=$(openemr_query "SELECT pc_eid, pc_pid, pc_eventDate, pc_startTime, pc_endTime, pc_duration, pc_hometext, pc_title, pc_catid FROM openemr_postcalendar_events WHERE pc_pid=$PATIENT_PID ORDER BY pc_eid DESC LIMIT 1" 2>/dev/null)

# Parse appointment data
APPT_FOUND="false"
APPT_EID=""
APPT_DATE=""
APPT_START_TIME=""
APPT_END_TIME=""
APPT_DURATION=""
APPT_REASON=""
APPT_TITLE=""
APPT_CATID=""

if [ -n "$NEWEST_APPT" ] && [ "$CURRENT_APPT_COUNT" -gt "$INITIAL_APPT_COUNT" ]; then
    APPT_FOUND="true"
    APPT_EID=$(echo "$NEWEST_APPT" | cut -f1)
    APPT_PID=$(echo "$NEWEST_APPT" | cut -f2)
    APPT_DATE=$(echo "$NEWEST_APPT" | cut -f3)
    APPT_START_TIME=$(echo "$NEWEST_APPT" | cut -f4)
    APPT_END_TIME=$(echo "$NEWEST_APPT" | cut -f5)
    APPT_DURATION=$(echo "$NEWEST_APPT" | cut -f6)
    APPT_REASON=$(echo "$NEWEST_APPT" | cut -f7)
    APPT_TITLE=$(echo "$NEWEST_APPT" | cut -f8)
    APPT_CATID=$(echo "$NEWEST_APPT" | cut -f9)

    echo ""
    echo "New appointment found:"
    echo "  EID: $APPT_EID"
    echo "  Patient PID: $APPT_PID"
    echo "  Date: $APPT_DATE"
    echo "  Time: $APPT_START_TIME - $APPT_END_TIME"
    echo "  Duration: $APPT_DURATION minutes"
    echo "  Reason: $APPT_REASON"
    echo "  Title: $APPT_TITLE"
    echo "  Category: $APPT_CATID"
else
    echo "No new appointment found for patient"
fi

# Validate appointment is in valid date range
DATE_VALID="false"
if [ -n "$APPT_DATE" ]; then
    # Convert dates to epoch seconds for proper comparison
    APPT_EPOCH=$(date -d "$APPT_DATE" +%s 2>/dev/null || echo "0")
    TODAY_EPOCH=$(date -d "$TODAY" +%s 2>/dev/null || echo "0")
    MAX_EPOCH=$(date -d "$MAX_DATE" +%s 2>/dev/null || echo "0")

    if [ "$APPT_EPOCH" -ge "$TODAY_EPOCH" ] && [ "$APPT_EPOCH" -le "$MAX_EPOCH" ]; then
        DATE_VALID="true"
        echo "Date $APPT_DATE is within valid range"
    else
        echo "Date $APPT_DATE is OUTSIDE valid range ($TODAY to $MAX_DATE)"
    fi
fi

# Validate appointment is in morning (09:00-12:00)
TIME_VALID="false"
if [ -n "$APPT_START_TIME" ]; then
    # Extract hour from start time (format: HH:MM:SS or HH:MM)
    START_HOUR=$(echo "$APPT_START_TIME" | cut -d: -f1)
    START_HOUR=$((10#$START_HOUR))  # Remove leading zeros
    if [ "$START_HOUR" -ge 9 ] && [ "$START_HOUR" -lt 12 ]; then
        TIME_VALID="true"
        echo "Start time $APPT_START_TIME is within morning hours (9-12)"
    else
        echo "Start time $APPT_START_TIME is OUTSIDE morning hours"
    fi
fi

# Check if reason mentions hypertension/BP/follow-up
REASON_VALID="false"
REASON_LOWER=$(echo "$APPT_REASON $APPT_TITLE" | tr '[:upper:]' '[:lower:]')
if echo "$REASON_LOWER" | grep -qE "(hypertension|blood pressure|htn|bp|follow.?up|followup|f/u)"; then
    REASON_VALID="true"
    echo "Reason contains appropriate keywords"
else
    echo "Reason does not contain hypertension/follow-up keywords"
fi

# Escape special characters for JSON
APPT_REASON_ESCAPED=$(echo "$APPT_REASON" | sed 's/"/\\"/g' | tr '\n' ' ')
APPT_TITLE_ESCAPED=$(echo "$APPT_TITLE" | sed 's/"/\\"/g' | tr '\n' ' ')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/schedule_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "initial_appt_count": ${INITIAL_APPT_COUNT:-0},
    "current_appt_count": ${CURRENT_APPT_COUNT:-0},
    "new_appointment_found": $APPT_FOUND,
    "appointment": {
        "eid": "$APPT_EID",
        "date": "$APPT_DATE",
        "start_time": "$APPT_START_TIME",
        "end_time": "$APPT_END_TIME",
        "duration_minutes": "${APPT_DURATION:-0}",
        "reason": "$APPT_REASON_ESCAPED",
        "title": "$APPT_TITLE_ESCAPED",
        "category_id": "$APPT_CATID"
    },
    "validation": {
        "date_in_range": $DATE_VALID,
        "time_in_morning": $TIME_VALID,
        "reason_appropriate": $REASON_VALID,
        "valid_date_range": {
            "start": "$TODAY",
            "end": "$MAX_DATE"
        }
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/schedule_followup_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/schedule_followup_result.json
chmod 666 /tmp/schedule_followup_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/schedule_followup_result.json"
cat /tmp/schedule_followup_result.json

echo ""
echo "=== Export Complete ==="
