#!/bin/bash
# Export script for Document Refusal of Care task

echo "=== Exporting Document Refusal of Care Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Capture final screenshot immediately
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

if [ -f /tmp/task_final_state.png ]; then
    SIZE=$(stat -c %s /tmp/task_final_state.png 2>/dev/null || echo "0")
    echo "Final screenshot captured: ${SIZE} bytes"
fi

# Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Get target patient info
PATIENT_PID=$(cat /tmp/target_patient_pid.txt 2>/dev/null || echo "0")
INITIAL_NOTE_COUNT=$(cat /tmp/initial_note_count.txt 2>/dev/null || echo "0")
TOTAL_INITIAL_NOTES=$(cat /tmp/total_initial_notes.txt 2>/dev/null || echo "0")

echo "Task timing: start=$TASK_START, end=$TASK_END"
echo "Target patient PID: $PATIENT_PID"
echo "Initial note count: $INITIAL_NOTE_COUNT"

# Get current note count for patient
CURRENT_NOTE_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COUNT(*) FROM pnotes WHERE pid=$PATIENT_PID AND activity=1" 2>/dev/null || echo "0")
echo "Current note count for patient: $CURRENT_NOTE_COUNT"

# Get total current notes
TOTAL_CURRENT_NOTES=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COUNT(*) FROM pnotes WHERE activity=1" 2>/dev/null || echo "0")
echo "Total current notes: $TOTAL_CURRENT_NOTES"

# Query for all recent notes for this patient (most recent first)
echo ""
echo "=== Querying notes for patient PID=$PATIENT_PID ==="
PATIENT_NOTES=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT id, DATE_FORMAT(date, '%Y-%m-%d %H:%i:%s') as date_str, title, LEFT(body, 500) as body_excerpt, user, UNIX_TIMESTAMP(date) as date_unix 
     FROM pnotes 
     WHERE pid=$PATIENT_PID AND activity=1 
     ORDER BY id DESC 
     LIMIT 10" 2>/dev/null)

echo "Patient notes:"
echo "$PATIENT_NOTES"

# Find notes created after task start
# Convert task start to MySQL datetime format
TASK_START_MYSQL=$(date -d "@$TASK_START" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "1970-01-01 00:00:00")
echo ""
echo "Looking for notes created after: $TASK_START_MYSQL"

NEW_NOTES=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT id, DATE_FORMAT(date, '%Y-%m-%d %H:%i:%s') as date_str, title, body, user, UNIX_TIMESTAMP(date) as date_unix 
     FROM pnotes 
     WHERE pid=$PATIENT_PID AND activity=1 AND UNIX_TIMESTAMP(date) >= $TASK_START - 120
     ORDER BY id DESC 
     LIMIT 5" 2>/dev/null)

echo "New notes (created during/near task window):"
echo "$NEW_NOTES"

# Parse the most recent note for detailed analysis
NOTE_FOUND="false"
NOTE_ID=""
NOTE_DATE=""
NOTE_TITLE=""
NOTE_BODY=""
NOTE_USER=""
NOTE_TIMESTAMP="0"

# Check if any new notes were created
if [ "$CURRENT_NOTE_COUNT" -gt "$INITIAL_NOTE_COUNT" ] || [ -n "$NEW_NOTES" ]; then
    # Get the newest note
    NEWEST_NOTE=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
        "SELECT id, DATE_FORMAT(date, '%Y-%m-%d %H:%i:%s'), title, body, user, UNIX_TIMESTAMP(date) 
         FROM pnotes 
         WHERE pid=$PATIENT_PID AND activity=1 
         ORDER BY id DESC 
         LIMIT 1" 2>/dev/null)
    
    if [ -n "$NEWEST_NOTE" ]; then
        NOTE_FOUND="true"
        NOTE_ID=$(echo "$NEWEST_NOTE" | cut -f1)
        NOTE_DATE=$(echo "$NEWEST_NOTE" | cut -f2)
        NOTE_TITLE=$(echo "$NEWEST_NOTE" | cut -f3)
        NOTE_BODY=$(echo "$NEWEST_NOTE" | cut -f4)
        NOTE_USER=$(echo "$NEWEST_NOTE" | cut -f5)
        NOTE_TIMESTAMP=$(echo "$NEWEST_NOTE" | cut -f6)
        
        echo ""
        echo "Newest note details:"
        echo "  ID: $NOTE_ID"
        echo "  Date: $NOTE_DATE"
        echo "  Title: $NOTE_TITLE"
        echo "  User: $NOTE_USER"
        echo "  Timestamp: $NOTE_TIMESTAMP"
        echo "  Body (first 200 chars): ${NOTE_BODY:0:200}"
    fi
fi

# Check for refusal-related content in title
TITLE_HAS_REFUSAL="false"
TITLE_LOWER=$(echo "$NOTE_TITLE" | tr '[:upper:]' '[:lower:]')
if echo "$TITLE_LOWER" | grep -qE "(refus|ama|against medical|decline|reject)"; then
    TITLE_HAS_REFUSAL="true"
    echo "Title contains refusal terminology"
fi

# Check for procedure reference in body
BODY_HAS_PROCEDURE="false"
BODY_LOWER=$(echo "$NOTE_BODY" | tr '[:upper:]' '[:lower:]')
if echo "$BODY_LOWER" | grep -qE "(mri|imaging|scan|magnetic resonance|diagnostic)"; then
    BODY_HAS_PROCEDURE="true"
    echo "Body references MRI/imaging procedure"
fi

# Check for risk discussion
BODY_HAS_RISKS="false"
if echo "$BODY_LOWER" | grep -qE "(risk|explain|discuss|counsel|inform|understand|warn|consequence)"; then
    BODY_HAS_RISKS="true"
    echo "Body mentions risk discussion"
fi

# Check for parent/guardian mention
BODY_HAS_PARENT="false"
if echo "$BODY_LOWER" | grep -qE "(parent|guardian|mother|father|family|caregiver)"; then
    BODY_HAS_PARENT="true"
    echo "Body mentions parent/guardian"
fi

# Check if note was created during task window
CREATED_DURING_TASK="false"
if [ "$NOTE_TIMESTAMP" -ge "$((TASK_START - 120))" ]; then
    CREATED_DURING_TASK="true"
    echo "Note was created during task window"
fi

# Escape special characters for JSON
NOTE_TITLE_ESCAPED=$(echo "$NOTE_TITLE" | sed 's/"/\\"/g' | sed 's/\\/\\\\/g' | tr '\n' ' ' | tr '\r' ' ')
NOTE_BODY_ESCAPED=$(echo "$NOTE_BODY" | sed 's/"/\\"/g' | sed 's/\\/\\\\/g' | tr '\n' ' ' | tr '\r' ' ')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/refusal_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "patient_pid": $PATIENT_PID,
    "initial_note_count": $INITIAL_NOTE_COUNT,
    "current_note_count": $CURRENT_NOTE_COUNT,
    "total_initial_notes": $TOTAL_INITIAL_NOTES,
    "total_current_notes": $TOTAL_CURRENT_NOTES,
    "note_found": $NOTE_FOUND,
    "note": {
        "id": "$NOTE_ID",
        "date": "$NOTE_DATE",
        "title": "$NOTE_TITLE_ESCAPED",
        "body": "$NOTE_BODY_ESCAPED",
        "user": "$NOTE_USER",
        "timestamp": $NOTE_TIMESTAMP
    },
    "content_analysis": {
        "title_has_refusal": $TITLE_HAS_REFUSAL,
        "body_has_procedure": $BODY_HAS_PROCEDURE,
        "body_has_risks": $BODY_HAS_RISKS,
        "body_has_parent": $BODY_HAS_PARENT,
        "created_during_task": $CREATED_DURING_TASK
    },
    "screenshot_exists": $([ -f "/tmp/task_final_state.png" ] && echo "true" || echo "false"),
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with proper permissions
rm -f /tmp/document_refusal_result.json 2>/dev/null || sudo rm -f /tmp/document_refusal_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/document_refusal_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/document_refusal_result.json
chmod 666 /tmp/document_refusal_result.json 2>/dev/null || sudo chmod 666 /tmp/document_refusal_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat /tmp/document_refusal_result.json
echo ""
echo "=== Export Complete ==="