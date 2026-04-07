#!/bin/bash
# Export script for Create Recurring Appointment Series Task

echo "=== Exporting Recurring Appointment Series Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Target patient
PATIENT_PID=1

# Get initial state
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_APPT_COUNT=$(cat /tmp/initial_appt_count.txt 2>/dev/null || echo "0")
EXISTING_IDS=$(cat /tmp/existing_appt_ids.txt 2>/dev/null || echo "")
NEXT_TUESDAY=$(cat /tmp/next_tuesday.txt 2>/dev/null || date -d "next Tuesday" +%Y-%m-%d)

echo "Task start timestamp: $TASK_START"
echo "Initial appointment count: $INITIAL_APPT_COUNT"
echo "Existing appointment IDs: $EXISTING_IDS"

# Get current appointment count for patient
CURRENT_APPT_COUNT=$(openemr_query "SELECT COUNT(*) FROM openemr_postcalendar_events WHERE pc_pid=$PATIENT_PID" 2>/dev/null || echo "0")
echo "Current appointment count: $CURRENT_APPT_COUNT"

# Calculate new appointments added
NEW_APPT_COUNT=$((CURRENT_APPT_COUNT - INITIAL_APPT_COUNT))
echo "New appointments added: $NEW_APPT_COUNT"

# Query for NEW appointments only (higher eid than before)
echo ""
echo "=== Querying for NEW appointments for patient PID=$PATIENT_PID ==="

# Build query to exclude existing IDs
if [ -n "$EXISTING_IDS" ]; then
    EXCLUDE_CLAUSE="AND pc_eid NOT IN ($EXISTING_IDS)"
else
    EXCLUDE_CLAUSE=""
fi

NEW_APPTS_RAW=$(openemr_query "SELECT pc_eid, pc_pid, pc_eventDate, pc_startTime, pc_endTime, pc_duration, pc_hometext, pc_title, DAYOFWEEK(pc_eventDate) as dow FROM openemr_postcalendar_events WHERE pc_pid=$PATIENT_PID $EXCLUDE_CLAUSE ORDER BY pc_eventDate ASC" 2>/dev/null)

echo "New appointments found:"
echo "$NEW_APPTS_RAW"

# Parse appointments into JSON array
APPTS_JSON="["
FIRST=true
PREV_DATE=""

while IFS=$'\t' read -r eid pid event_date start_time end_time duration reason title dow; do
    if [ -z "$eid" ]; then
        continue
    fi
    
    # Calculate days since previous appointment
    DAYS_SINCE_PREV=""
    if [ -n "$PREV_DATE" ] && [ -n "$event_date" ]; then
        PREV_EPOCH=$(date -d "$PREV_DATE" +%s 2>/dev/null || echo "0")
        CURR_EPOCH=$(date -d "$event_date" +%s 2>/dev/null || echo "0")
        if [ "$PREV_EPOCH" -gt 0 ] && [ "$CURR_EPOCH" -gt 0 ]; then
            DAYS_SINCE_PREV=$(( (CURR_EPOCH - PREV_EPOCH) / 86400 ))
        fi
    fi
    PREV_DATE="$event_date"
    
    # Escape strings for JSON
    reason_escaped=$(echo "$reason" | sed 's/"/\\"/g' | tr '\n' ' ')
    title_escaped=$(echo "$title" | sed 's/"/\\"/g' | tr '\n' ' ')
    
    if [ "$FIRST" = true ]; then
        FIRST=false
    else
        APPTS_JSON+=","
    fi
    
    APPTS_JSON+=$(cat <<APPTJSON
{
        "eid": "$eid",
        "pid": "$pid",
        "event_date": "$event_date",
        "start_time": "$start_time",
        "end_time": "$end_time",
        "duration": "$duration",
        "reason": "$reason_escaped",
        "title": "$title_escaped",
        "day_of_week": "$dow",
        "days_since_previous": "$DAYS_SINCE_PREV"
    }
APPTJSON
)
done <<< "$NEW_APPTS_RAW"

APPTS_JSON+="]"

# Analyze appointments for verification
# Check if all are on Tuesday (dow=3 in MySQL)
TUESDAY_COUNT=0
NON_TUESDAY_COUNT=0
CORRECT_TIME_COUNT=0
WEEKLY_INTERVAL_COUNT=0
PREV_DATE=""

while IFS=$'\t' read -r eid pid event_date start_time end_time duration reason title dow; do
    if [ -z "$eid" ]; then
        continue
    fi
    
    # Check day of week (MySQL: 1=Sunday, 2=Monday, 3=Tuesday)
    if [ "$dow" = "3" ]; then
        TUESDAY_COUNT=$((TUESDAY_COUNT + 1))
    else
        NON_TUESDAY_COUNT=$((NON_TUESDAY_COUNT + 1))
    fi
    
    # Check start time (should be around 10:00)
    START_HOUR=$(echo "$start_time" | cut -d: -f1 | sed 's/^0//')
    START_MIN=$(echo "$start_time" | cut -d: -f2 | sed 's/^0//')
    # Allow 9:30 to 10:30
    if [ "$START_HOUR" -eq 10 ] || ([ "$START_HOUR" -eq 9 ] && [ "$START_MIN" -ge 30 ]); then
        CORRECT_TIME_COUNT=$((CORRECT_TIME_COUNT + 1))
    fi
    
    # Check weekly interval
    if [ -n "$PREV_DATE" ]; then
        PREV_EPOCH=$(date -d "$PREV_DATE" +%s 2>/dev/null || echo "0")
        CURR_EPOCH=$(date -d "$event_date" +%s 2>/dev/null || echo "0")
        if [ "$PREV_EPOCH" -gt 0 ] && [ "$CURR_EPOCH" -gt 0 ]; then
            DAYS_APART=$(( (CURR_EPOCH - PREV_EPOCH) / 86400 ))
            # Allow 6-8 days (approximately weekly)
            if [ "$DAYS_APART" -ge 6 ] && [ "$DAYS_APART" -le 8 ]; then
                WEEKLY_INTERVAL_COUNT=$((WEEKLY_INTERVAL_COUNT + 1))
            fi
        fi
    fi
    PREV_DATE="$event_date"
done <<< "$NEW_APPTS_RAW"

echo ""
echo "Analysis:"
echo "  New appointments: $NEW_APPT_COUNT"
echo "  On Tuesday: $TUESDAY_COUNT"
echo "  Not on Tuesday: $NON_TUESDAY_COUNT"
echo "  Correct time (10:00 AM): $CORRECT_TIME_COUNT"
echo "  Weekly intervals: $WEEKLY_INTERVAL_COUNT"

# Create result JSON
TEMP_JSON=$(mktemp /tmp/recurring_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "task_start_timestamp": $TASK_START,
    "initial_appt_count": ${INITIAL_APPT_COUNT:-0},
    "current_appt_count": ${CURRENT_APPT_COUNT:-0},
    "new_appt_count": ${NEW_APPT_COUNT:-0},
    "analysis": {
        "tuesday_count": $TUESDAY_COUNT,
        "non_tuesday_count": $NON_TUESDAY_COUNT,
        "correct_time_count": $CORRECT_TIME_COUNT,
        "weekly_interval_count": $WEEKLY_INTERVAL_COUNT
    },
    "appointments": $APPTS_JSON,
    "next_tuesday_expected": "$NEXT_TUESDAY",
    "screenshot_exists": $([ -f "/tmp/task_final.png" ] && echo "true" || echo "false"),
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/recurring_appointments_result.json 2>/dev/null || sudo rm -f /tmp/recurring_appointments_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/recurring_appointments_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/recurring_appointments_result.json
chmod 666 /tmp/recurring_appointments_result.json 2>/dev/null || sudo chmod 666 /tmp/recurring_appointments_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/recurring_appointments_result.json"
cat /tmp/recurring_appointments_result.json
echo ""
echo "=== Export Complete ==="