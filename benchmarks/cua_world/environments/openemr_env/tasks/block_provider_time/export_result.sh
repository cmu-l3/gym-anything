#!/bin/bash
# Export script for Block Provider Time task

echo "=== Exporting Block Provider Time Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png
echo "Final screenshot saved to /tmp/task_final.png"

# Provider details
PROVIDER_ID=1

# Get stored values
TARGET_DATE=$(cat /tmp/target_date.txt 2>/dev/null || echo "")
TASK_START=$(cat /tmp/task_start_timestamp.txt 2>/dev/null || echo "0")
INITIAL_EVENT_COUNT=$(cat /tmp/initial_event_count.txt 2>/dev/null || echo "0")
INITIAL_TARGET_DATE_EVENTS=$(cat /tmp/initial_target_date_events.txt 2>/dev/null || echo "0")

echo "Target date: $TARGET_DATE"
echo "Task start timestamp: $TASK_START"
echo "Initial event count: $INITIAL_EVENT_COUNT"

# Get current event count for provider
CURRENT_EVENT_COUNT=$(openemr_query "SELECT COUNT(*) FROM openemr_postcalendar_events WHERE pc_aid=$PROVIDER_ID" 2>/dev/null || echo "0")
echo "Current event count for provider: $CURRENT_EVENT_COUNT"

# Get current events on target date
CURRENT_TARGET_DATE_EVENTS=$(openemr_query "SELECT COUNT(*) FROM openemr_postcalendar_events WHERE pc_aid=$PROVIDER_ID AND pc_eventDate='$TARGET_DATE'" 2>/dev/null || echo "0")
echo "Current events on target date: $CURRENT_TARGET_DATE_EVENTS"

# Query for all events on the target date for this provider
echo ""
echo "=== Events on target date ($TARGET_DATE) ==="
TARGET_DATE_EVENTS=$(openemr_query "SELECT pc_eid, pc_aid, pc_pid, pc_eventDate, pc_startTime, pc_endTime, pc_duration, pc_title, pc_hometext, pc_catid FROM openemr_postcalendar_events WHERE pc_aid=$PROVIDER_ID AND pc_eventDate='$TARGET_DATE' ORDER BY pc_eid DESC" 2>/dev/null)
echo "$TARGET_DATE_EVENTS"

# Query for the most recent event created (highest pc_eid)
echo ""
echo "=== Most recent events for provider ==="
RECENT_EVENTS=$(openemr_query "SELECT pc_eid, pc_aid, pc_pid, pc_eventDate, pc_startTime, pc_endTime, pc_duration, pc_title, pc_hometext, pc_catid FROM openemr_postcalendar_events WHERE pc_aid=$PROVIDER_ID ORDER BY pc_eid DESC LIMIT 5" 2>/dev/null)
echo "$RECENT_EVENTS"

# Find the newest event that matches our criteria (on target date, around 14:00)
echo ""
echo "=== Looking for matching blocked time ==="
MATCHING_EVENT=$(openemr_query "SELECT pc_eid, pc_aid, pc_pid, pc_eventDate, pc_startTime, pc_endTime, pc_duration, pc_title, pc_hometext, pc_catid FROM openemr_postcalendar_events WHERE pc_aid=$PROVIDER_ID AND pc_eventDate='$TARGET_DATE' AND pc_startTime >= '13:00:00' AND pc_startTime <= '15:00:00' ORDER BY pc_eid DESC LIMIT 1" 2>/dev/null)

# If no exact match, try to find any new event on target date
if [ -z "$MATCHING_EVENT" ]; then
    echo "No exact time match, checking for any new event on target date..."
    MATCHING_EVENT=$(openemr_query "SELECT pc_eid, pc_aid, pc_pid, pc_eventDate, pc_startTime, pc_endTime, pc_duration, pc_title, pc_hometext, pc_catid FROM openemr_postcalendar_events WHERE pc_aid=$PROVIDER_ID AND pc_eventDate='$TARGET_DATE' ORDER BY pc_eid DESC LIMIT 1" 2>/dev/null)
fi

# Parse the matching event
EVENT_FOUND="false"
EVENT_EID=""
EVENT_AID=""
EVENT_PID=""
EVENT_DATE=""
EVENT_START_TIME=""
EVENT_END_TIME=""
EVENT_DURATION=""
EVENT_TITLE=""
EVENT_HOMETEXT=""
EVENT_CATID=""

if [ -n "$MATCHING_EVENT" ] && [ "$CURRENT_EVENT_COUNT" -gt "$INITIAL_EVENT_COUNT" ]; then
    EVENT_FOUND="true"
    EVENT_EID=$(echo "$MATCHING_EVENT" | cut -f1)
    EVENT_AID=$(echo "$MATCHING_EVENT" | cut -f2)
    EVENT_PID=$(echo "$MATCHING_EVENT" | cut -f3)
    EVENT_DATE=$(echo "$MATCHING_EVENT" | cut -f4)
    EVENT_START_TIME=$(echo "$MATCHING_EVENT" | cut -f5)
    EVENT_END_TIME=$(echo "$MATCHING_EVENT" | cut -f6)
    EVENT_DURATION=$(echo "$MATCHING_EVENT" | cut -f7)
    EVENT_TITLE=$(echo "$MATCHING_EVENT" | cut -f8)
    EVENT_HOMETEXT=$(echo "$MATCHING_EVENT" | cut -f9)
    EVENT_CATID=$(echo "$MATCHING_EVENT" | cut -f10)
    
    echo ""
    echo "Matching event found:"
    echo "  EID: $EVENT_EID"
    echo "  Provider ID: $EVENT_AID"
    echo "  Patient ID: $EVENT_PID"
    echo "  Date: $EVENT_DATE"
    echo "  Time: $EVENT_START_TIME - $EVENT_END_TIME"
    echo "  Duration: $EVENT_DURATION"
    echo "  Title: $EVENT_TITLE"
    echo "  Description: $EVENT_HOMETEXT"
    echo "  Category: $EVENT_CATID"
else
    echo "No matching event found"
fi

# Validate date matches target
DATE_VALID="false"
if [ "$EVENT_DATE" = "$TARGET_DATE" ]; then
    DATE_VALID="true"
    echo "Date validation: PASS ($EVENT_DATE = $TARGET_DATE)"
else
    echo "Date validation: FAIL ($EVENT_DATE != $TARGET_DATE)"
fi

# Validate time is around 14:00
TIME_VALID="false"
if [ -n "$EVENT_START_TIME" ]; then
    START_HOUR=$(echo "$EVENT_START_TIME" | cut -d: -f1)
    START_HOUR=$((10#$START_HOUR))  # Remove leading zeros
    if [ "$START_HOUR" -ge 13 ] && [ "$START_HOUR" -le 15 ]; then
        TIME_VALID="true"
        echo "Time validation: PASS (start hour $START_HOUR is between 13-15)"
    else
        echo "Time validation: FAIL (start hour $START_HOUR is not between 13-15)"
    fi
fi

# Validate no patient linked (blocked time)
NO_PATIENT="false"
if [ "$EVENT_PID" = "0" ] || [ -z "$EVENT_PID" ]; then
    NO_PATIENT="true"
    echo "No-patient validation: PASS (pid=$EVENT_PID)"
else
    echo "No-patient validation: FAIL (pid=$EVENT_PID, should be 0)"
fi

# Check for description keywords
DESCRIPTION_VALID="false"
COMBINED_TEXT=$(echo "$EVENT_TITLE $EVENT_HOMETEXT" | tr '[:upper:]' '[:lower:]')
if echo "$COMBINED_TEXT" | grep -qiE "(compliance|training|meeting|block|unavailable|staff|admin)"; then
    DESCRIPTION_VALID="true"
    echo "Description validation: PASS (found relevant keywords)"
else
    echo "Description validation: FAIL (no relevant keywords found)"
fi

# Escape special characters for JSON
EVENT_TITLE_ESCAPED=$(echo "$EVENT_TITLE" | sed 's/"/\\"/g' | tr '\n' ' ' | tr '\r' ' ')
EVENT_HOMETEXT_ESCAPED=$(echo "$EVENT_HOMETEXT" | sed 's/"/\\"/g' | tr '\n' ' ' | tr '\r' ' ')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/block_time_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "provider_id": $PROVIDER_ID,
    "target_date": "$TARGET_DATE",
    "task_start_timestamp": $TASK_START,
    "initial_event_count": ${INITIAL_EVENT_COUNT:-0},
    "current_event_count": ${CURRENT_EVENT_COUNT:-0},
    "initial_target_date_events": ${INITIAL_TARGET_DATE_EVENTS:-0},
    "current_target_date_events": ${CURRENT_TARGET_DATE_EVENTS:-0},
    "event_found": $EVENT_FOUND,
    "event": {
        "eid": "$EVENT_EID",
        "provider_id": "$EVENT_AID",
        "patient_id": "$EVENT_PID",
        "date": "$EVENT_DATE",
        "start_time": "$EVENT_START_TIME",
        "end_time": "$EVENT_END_TIME",
        "duration": "$EVENT_DURATION",
        "title": "$EVENT_TITLE_ESCAPED",
        "description": "$EVENT_HOMETEXT_ESCAPED",
        "category_id": "$EVENT_CATID"
    },
    "validation": {
        "date_valid": $DATE_VALID,
        "time_valid": $TIME_VALID,
        "no_patient": $NO_PATIENT,
        "description_valid": $DESCRIPTION_VALID
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/block_provider_time_result.json 2>/dev/null || sudo rm -f /tmp/block_provider_time_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/block_provider_time_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/block_provider_time_result.json
chmod 666 /tmp/block_provider_time_result.json 2>/dev/null || sudo chmod 666 /tmp/block_provider_time_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/block_provider_time_result.json"
cat /tmp/block_provider_time_result.json

echo ""
echo "=== Export Complete ==="