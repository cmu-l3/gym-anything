#!/bin/bash
# Export script for Create Patient Recall Task

echo "=== Exporting Create Patient Recall Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png
echo "Final screenshot saved"

# Target patient
PATIENT_PID=3

# Get task timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
echo "Task duration: $((TASK_END - TASK_START)) seconds"

# Get initial counts
INITIAL_REMINDERS=$(cat /tmp/initial_reminder_count.txt 2>/dev/null || echo "0")
INITIAL_RECALLS=$(cat /tmp/initial_recall_count.txt 2>/dev/null || echo "0")
INITIAL_CALENDAR=$(cat /tmp/initial_calendar_count.txt 2>/dev/null || echo "0")

# Get current counts
CURRENT_REMINDERS=$(openemr_query "SELECT COUNT(*) FROM patient_reminders WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
CURRENT_RECALLS=$(openemr_query "SELECT COUNT(*) FROM patient_recall WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
CURRENT_CALENDAR=$(openemr_query "SELECT COUNT(*) FROM openemr_postcalendar_events WHERE pc_pid=$PATIENT_PID AND pc_eventDate > CURDATE()" 2>/dev/null || echo "0")

echo ""
echo "Count comparison:"
echo "  patient_reminders: $INITIAL_REMINDERS -> $CURRENT_REMINDERS"
echo "  patient_recall: $INITIAL_RECALLS -> $CURRENT_RECALLS"
echo "  future calendar: $INITIAL_CALENDAR -> $CURRENT_CALENDAR"

# Calculate date range for validation (150-210 days from today)
TODAY=$(date +%Y-%m-%d)
MIN_DATE=$(date -d "+150 days" +%Y-%m-%d)
MAX_DATE=$(date -d "+210 days" +%Y-%m-%d)
echo "Valid recall date range: $MIN_DATE to $MAX_DATE"

# Query for newest recall/reminder entries
echo ""
echo "=== Querying for recall entries ==="

# Check patient_reminders table (most common)
echo "Checking patient_reminders table..."
REMINDER_DATA=$(openemr_query "SELECT id, pid, due_status, date_created, date_sent, reason, voice_status, sms_status, email_status FROM patient_reminders WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 5" 2>/dev/null || echo "")
echo "Recent reminders:"
echo "$REMINDER_DATA"

# Check patient_recall table if it exists
echo ""
echo "Checking patient_recall table..."
RECALL_DATA=$(openemr_query "SELECT * FROM patient_recall WHERE pid=$PATIENT_PID ORDER BY recall_date DESC LIMIT 5" 2>/dev/null || echo "")
echo "Recent recalls:"
echo "$RECALL_DATA"

# Check for any recall-related calendar events
echo ""
echo "Checking calendar for recall-type events..."
CALENDAR_RECALLS=$(openemr_query "SELECT pc_eid, pc_pid, pc_eventDate, pc_title, pc_hometext, pc_catid FROM openemr_postcalendar_events WHERE pc_pid=$PATIENT_PID AND pc_eventDate BETWEEN '$MIN_DATE' AND '$MAX_DATE' ORDER BY pc_eid DESC LIMIT 5" 2>/dev/null || echo "")
echo "Future calendar events in date range:"
echo "$CALENDAR_RECALLS"

# Determine which method was used and get the newest entry
RECALL_FOUND="false"
RECALL_ID=""
RECALL_DATE=""
RECALL_REASON=""
RECALL_PROVIDER=""
RECALL_SOURCE="none"

# First check patient_reminders (most common in OpenEMR)
if [ "$CURRENT_REMINDERS" -gt "$INITIAL_REMINDERS" ]; then
    echo ""
    echo "New entry found in patient_reminders table"
    RECALL_SOURCE="patient_reminders"
    
    # Get the newest reminder
    NEWEST_REMINDER=$(openemr_query "SELECT id, pid, due_status, date_created, reason FROM patient_reminders WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 1" 2>/dev/null)
    if [ -n "$NEWEST_REMINDER" ]; then
        RECALL_FOUND="true"
        RECALL_ID=$(echo "$NEWEST_REMINDER" | cut -f1)
        RECALL_DATE=$(echo "$NEWEST_REMINDER" | cut -f4)
        RECALL_REASON=$(echo "$NEWEST_REMINDER" | cut -f5)
        echo "Newest reminder: ID=$RECALL_ID, Date=$RECALL_DATE, Reason=$RECALL_REASON"
    fi
fi

# Check patient_recall table
if [ "$RECALL_FOUND" = "false" ] && [ "$CURRENT_RECALLS" -gt "$INITIAL_RECALLS" ]; then
    echo ""
    echo "New entry found in patient_recall table"
    RECALL_SOURCE="patient_recall"
    
    NEWEST_RECALL=$(openemr_query "SELECT id, pid, recall_date, reason, provider FROM patient_recall WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 1" 2>/dev/null)
    if [ -n "$NEWEST_RECALL" ]; then
        RECALL_FOUND="true"
        RECALL_ID=$(echo "$NEWEST_RECALL" | cut -f1)
        RECALL_DATE=$(echo "$NEWEST_RECALL" | cut -f3)
        RECALL_REASON=$(echo "$NEWEST_RECALL" | cut -f4)
        RECALL_PROVIDER=$(echo "$NEWEST_RECALL" | cut -f5)
        echo "Newest recall: ID=$RECALL_ID, Date=$RECALL_DATE, Reason=$RECALL_REASON"
    fi
fi

# Check calendar events as fallback
if [ "$RECALL_FOUND" = "false" ] && [ "$CURRENT_CALENDAR" -gt "$INITIAL_CALENDAR" ]; then
    echo ""
    echo "New entry found in calendar (may be recall-type event)"
    RECALL_SOURCE="calendar"
    
    NEWEST_EVENT=$(openemr_query "SELECT pc_eid, pc_eventDate, pc_title, pc_hometext FROM openemr_postcalendar_events WHERE pc_pid=$PATIENT_PID AND pc_eventDate > CURDATE() ORDER BY pc_eid DESC LIMIT 1" 2>/dev/null)
    if [ -n "$NEWEST_EVENT" ]; then
        RECALL_FOUND="true"
        RECALL_ID=$(echo "$NEWEST_EVENT" | cut -f1)
        RECALL_DATE=$(echo "$NEWEST_EVENT" | cut -f2)
        RECALL_REASON=$(echo "$NEWEST_EVENT" | cut -f3 ; echo "$NEWEST_EVENT" | cut -f4)
        echo "Newest calendar event: ID=$RECALL_ID, Date=$RECALL_DATE"
    fi
fi

# Validate the recall date is in expected range
DATE_VALID="false"
if [ -n "$RECALL_DATE" ]; then
    # Convert to epoch for comparison
    RECALL_EPOCH=$(date -d "$RECALL_DATE" +%s 2>/dev/null || echo "0")
    MIN_EPOCH=$(date -d "$MIN_DATE" +%s 2>/dev/null || echo "0")
    MAX_EPOCH=$(date -d "$MAX_DATE" +%s 2>/dev/null || echo "0")
    
    if [ "$RECALL_EPOCH" -ge "$MIN_EPOCH" ] && [ "$RECALL_EPOCH" -le "$MAX_EPOCH" ]; then
        DATE_VALID="true"
        echo "Recall date $RECALL_DATE is within valid range"
    else
        echo "Recall date $RECALL_DATE is OUTSIDE valid range ($MIN_DATE to $MAX_DATE)"
    fi
fi

# Check if reason contains expected keywords
REASON_VALID="false"
if [ -n "$RECALL_REASON" ]; then
    REASON_LOWER=$(echo "$RECALL_REASON" | tr '[:upper:]' '[:lower:]')
    if echo "$REASON_LOWER" | grep -qE "(wellness|annual|exam|physical|checkup|preventive)"; then
        REASON_VALID="true"
        echo "Recall reason contains expected keywords"
    else
        echo "Recall reason does not contain expected keywords: $RECALL_REASON"
    fi
fi

# Escape special characters for JSON
RECALL_REASON_ESCAPED=$(echo "$RECALL_REASON" | sed 's/"/\\"/g' | tr '\n' ' ' | head -c 500)

# Create result JSON
TEMP_JSON=$(mktemp /tmp/recall_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "counts": {
        "initial_reminders": ${INITIAL_REMINDERS:-0},
        "current_reminders": ${CURRENT_REMINDERS:-0},
        "initial_recalls": ${INITIAL_RECALLS:-0},
        "current_recalls": ${CURRENT_RECALLS:-0},
        "initial_calendar": ${INITIAL_CALENDAR:-0},
        "current_calendar": ${CURRENT_CALENDAR:-0}
    },
    "recall_found": $RECALL_FOUND,
    "recall_source": "$RECALL_SOURCE",
    "recall": {
        "id": "$RECALL_ID",
        "date": "$RECALL_DATE",
        "reason": "$RECALL_REASON_ESCAPED",
        "provider": "$RECALL_PROVIDER"
    },
    "validation": {
        "date_valid": $DATE_VALID,
        "reason_valid": $REASON_VALID,
        "min_date": "$MIN_DATE",
        "max_date": "$MAX_DATE"
    },
    "screenshot_exists": $([ -f "/tmp/task_final.png" ] && echo "true" || echo "false"),
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/create_recall_result.json 2>/dev/null || sudo rm -f /tmp/create_recall_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/create_recall_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/create_recall_result.json
chmod 666 /tmp/create_recall_result.json 2>/dev/null || sudo chmod 666 /tmp/create_recall_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/create_recall_result.json"
cat /tmp/create_recall_result.json
echo ""
echo "=== Export Complete ==="