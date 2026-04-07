#!/bin/bash
# Export script for Schedule Appointment task
# Exports all verification data to JSON file for verifier to read

echo "=== Exporting Schedule Appointment Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot for evidence
take_screenshot /tmp/task_final.png
echo "Final screenshot saved to /tmp/task_final.png"

# Target patient
PATIENT_PID=2

# Get baseline data
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_APT_COUNT=$(cat /tmp/initial_apt_count.txt 2>/dev/null || echo "0")
INITIAL_TOTAL_APT=$(cat /tmp/initial_total_apt_count.txt 2>/dev/null || echo "0")
MAX_APT_ID_BEFORE=$(cat /tmp/max_apt_id.txt 2>/dev/null || echo "0")
VALID_DATE_START=$(cat /tmp/valid_date_start.txt 2>/dev/null || echo "$(date +%Y-%m-%d)")
VALID_DATE_END=$(cat /tmp/valid_date_end.txt 2>/dev/null || echo "$(date -d '+7 days' +%Y-%m-%d)")

echo "Baseline data:"
echo "  Task start: $TASK_START"
echo "  Initial patient appointments: $INITIAL_APT_COUNT"
echo "  Initial total appointments: $INITIAL_TOTAL_APT"
echo "  Max appointment ID before: $MAX_APT_ID_BEFORE"
echo "  Valid date range: $VALID_DATE_START to $VALID_DATE_END"

# Get current appointment count for patient
CURRENT_APT_COUNT=$(openemr_query "SELECT COUNT(*) FROM openemr_postcalendar_events WHERE pc_pid=$PATIENT_PID" 2>/dev/null || echo "0")
CURRENT_TOTAL_APT=$(openemr_query "SELECT COUNT(*) FROM openemr_postcalendar_events" 2>/dev/null || echo "0")

echo ""
echo "Current state:"
echo "  Patient appointments: $CURRENT_APT_COUNT (was $INITIAL_APT_COUNT)"
echo "  Total appointments: $CURRENT_TOTAL_APT (was $INITIAL_TOTAL_APT)"

# Debug: Show all appointments for this patient
echo ""
echo "=== DEBUG: All appointments for patient PID=$PATIENT_PID ==="
openemr_query "SELECT pc_eid, pc_pid, pc_eventDate, pc_startTime, pc_duration, pc_hometext, pc_title, pc_catid FROM openemr_postcalendar_events WHERE pc_pid=$PATIENT_PID ORDER BY pc_eid DESC LIMIT 10" 2>/dev/null
echo "=== END DEBUG ==="

# Query for NEW appointments (pc_eid > MAX_APT_ID_BEFORE) for this patient
echo ""
echo "Looking for new appointments for patient $PATIENT_PID created during task..."
NEW_APPTS=$(openemr_query "SELECT pc_eid, pc_pid, pc_eventDate, pc_startTime, pc_endTime, pc_duration, pc_hometext, pc_title, pc_catid FROM openemr_postcalendar_events WHERE pc_pid=$PATIENT_PID AND pc_eid > $MAX_APT_ID_BEFORE ORDER BY pc_eid DESC LIMIT 5" 2>/dev/null)

if [ -n "$NEW_APPTS" ]; then
    echo "New appointments found:"
    echo "$NEW_APPTS"
else
    echo "No new appointments found for patient $PATIENT_PID"
    
    # Check if any new appointments were created at all (for debugging)
    ANY_NEW=$(openemr_query "SELECT pc_eid, pc_pid, pc_eventDate, pc_startTime, pc_hometext FROM openemr_postcalendar_events WHERE pc_eid > $MAX_APT_ID_BEFORE ORDER BY pc_eid DESC LIMIT 5" 2>/dev/null)
    if [ -n "$ANY_NEW" ]; then
        echo "NOTE: New appointments were created but for different patients:"
        echo "$ANY_NEW"
    fi
fi

# Get the most recent NEW appointment for the target patient
NEWEST_APPT=$(openemr_query "SELECT pc_eid, pc_pid, pc_eventDate, pc_startTime, pc_endTime, pc_duration, pc_hometext, pc_title, pc_catid FROM openemr_postcalendar_events WHERE pc_pid=$PATIENT_PID AND pc_eid > $MAX_APT_ID_BEFORE ORDER BY pc_eid DESC LIMIT 1" 2>/dev/null)

# Parse appointment data
APPT_FOUND="false"
APPT_EID=""
APPT_DATE=""
APPT_START_TIME=""
APPT_END_TIME=""
APPT_DURATION=""
APPT_COMMENT=""
APPT_TITLE=""
APPT_CATID=""

if [ -n "$NEWEST_APPT" ]; then
    APPT_FOUND="true"
    APPT_EID=$(echo "$NEWEST_APPT" | cut -f1)
    APPT_PID=$(echo "$NEWEST_APPT" | cut -f2)
    APPT_DATE=$(echo "$NEWEST_APPT" | cut -f3)
    APPT_START_TIME=$(echo "$NEWEST_APPT" | cut -f4)
    APPT_END_TIME=$(echo "$NEWEST_APPT" | cut -f5)
    APPT_DURATION=$(echo "$NEWEST_APPT" | cut -f6)
    APPT_COMMENT=$(echo "$NEWEST_APPT" | cut -f7)
    APPT_TITLE=$(echo "$NEWEST_APPT" | cut -f8)
    APPT_CATID=$(echo "$NEWEST_APPT" | cut -f9)

    echo ""
    echo "New appointment details:"
    echo "  EID: $APPT_EID"
    echo "  Patient PID: $APPT_PID"
    echo "  Date: $APPT_DATE"
    echo "  Time: $APPT_START_TIME - $APPT_END_TIME"
    echo "  Duration: $APPT_DURATION minutes"
    echo "  Comment: $APPT_COMMENT"
    echo "  Title: $APPT_TITLE"
    echo "  Category ID: $APPT_CATID"
fi

# Validate date is within range
DATE_VALID="false"
if [ -n "$APPT_DATE" ]; then
    APPT_EPOCH=$(date -d "$APPT_DATE" +%s 2>/dev/null || echo "0")
    START_EPOCH=$(date -d "$VALID_DATE_START" +%s 2>/dev/null || echo "0")
    END_EPOCH=$(date -d "$VALID_DATE_END" +%s 2>/dev/null || echo "0")

    if [ "$APPT_EPOCH" -ge "$START_EPOCH" ] && [ "$APPT_EPOCH" -le "$END_EPOCH" ]; then
        DATE_VALID="true"
        echo "Date validation: PASS ($APPT_DATE is within $VALID_DATE_START to $VALID_DATE_END)"
    else
        echo "Date validation: FAIL ($APPT_DATE is outside valid range)"
    fi
fi

# Validate time is within range (9 AM - 4 PM)
TIME_VALID="false"
if [ -n "$APPT_START_TIME" ]; then
    START_HOUR=$(echo "$APPT_START_TIME" | cut -d: -f1 | sed 's/^0*//')
    START_HOUR=${START_HOUR:-0}
    
    if [ "$START_HOUR" -ge 9 ] && [ "$START_HOUR" -lt 16 ]; then
        TIME_VALID="true"
        echo "Time validation: PASS ($APPT_START_TIME is between 9 AM and 4 PM)"
    else
        echo "Time validation: FAIL ($APPT_START_TIME is outside valid hours)"
    fi
fi

# Validate duration is at least 15 minutes
DURATION_VALID="false"
if [ -n "$APPT_DURATION" ]; then
    APPT_DURATION_NUM=${APPT_DURATION:-0}
    if [ "$APPT_DURATION_NUM" -ge 15 ]; then
        DURATION_VALID="true"
        echo "Duration validation: PASS ($APPT_DURATION minutes >= 15)"
    else
        echo "Duration validation: FAIL ($APPT_DURATION minutes < 15)"
    fi
fi

# Check comment for relevant keywords
COMMENT_VALID="false"
COMMENT_LOWER=$(echo "$APPT_COMMENT $APPT_TITLE" | tr '[:upper:]' '[:lower:]')
if echo "$COMMENT_LOWER" | grep -qE "(routine|follow|visit|check|office|appointment)"; then
    COMMENT_VALID="true"
    echo "Comment validation: PASS (contains relevant keywords)"
elif [ -n "$APPT_COMMENT" ] || [ -n "$APPT_TITLE" ]; then
    echo "Comment validation: PARTIAL (has text but no specific keywords)"
else
    echo "Comment validation: FAIL (no comment/title provided)"
fi

# Escape special characters for JSON
APPT_COMMENT_ESCAPED=$(echo "$APPT_COMMENT" | sed 's/"/\\"/g' | sed 's/\\/\\\\/g' | tr '\n' ' ')
APPT_TITLE_ESCAPED=$(echo "$APPT_TITLE" | sed 's/"/\\"/g' | sed 's/\\/\\\\/g' | tr '\n' ' ')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/schedule_appointment_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "task_end_time": $(date +%s),
    "patient_pid": $PATIENT_PID,
    "initial_apt_count": ${INITIAL_APT_COUNT:-0},
    "current_apt_count": ${CURRENT_APT_COUNT:-0},
    "initial_total_apt": ${INITIAL_TOTAL_APT:-0},
    "current_total_apt": ${CURRENT_TOTAL_APT:-0},
    "max_apt_id_before": ${MAX_APT_ID_BEFORE:-0},
    "new_appointment_found": $APPT_FOUND,
    "appointment": {
        "eid": "$APPT_EID",
        "pid": "$PATIENT_PID",
        "date": "$APPT_DATE",
        "start_time": "$APPT_START_TIME",
        "end_time": "$APPT_END_TIME",
        "duration": "${APPT_DURATION:-0}",
        "comment": "$APPT_COMMENT_ESCAPED",
        "title": "$APPT_TITLE_ESCAPED",
        "category_id": "$APPT_CATID"
    },
    "validation": {
        "date_valid": $DATE_VALID,
        "time_valid": $TIME_VALID,
        "duration_valid": $DURATION_VALID,
        "comment_valid": $COMMENT_VALID,
        "valid_date_start": "$VALID_DATE_START",
        "valid_date_end": "$VALID_DATE_END"
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="