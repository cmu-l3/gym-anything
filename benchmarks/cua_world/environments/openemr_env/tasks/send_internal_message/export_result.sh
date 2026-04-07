#!/bin/bash
# Export script for Send Internal Message task
# Exports verification data to JSON for the verifier to read

echo "=== Exporting Send Internal Message Result ==="

# Configuration
PATIENT_PID=4
RESULT_FILE="/tmp/send_message_result.json"

# Get task timing information
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
TASK_START_DATETIME=$(date -d @$TASK_START '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "2000-01-01 00:00:00")

echo "Task timing: start=$TASK_START, end=$TASK_END"
echo "Task start datetime: $TASK_START_DATETIME"

# Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final_state.png 2>/dev/null || true

SCREENSHOT_EXISTS="false"
if [ -f /tmp/task_final_state.png ]; then
    SCREENSHOT_EXISTS="true"
    echo "Final screenshot saved"
fi

# Get initial counts
INITIAL_MSG_COUNT=$(cat /tmp/initial_message_count.txt 2>/dev/null || echo "0")
INITIAL_TOTAL_COUNT=$(cat /tmp/initial_total_message_count.txt 2>/dev/null || echo "0")

# Get current message counts
CURRENT_MSG_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COUNT(*) FROM pnotes WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
CURRENT_TOTAL_COUNT=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT COUNT(*) FROM pnotes" 2>/dev/null || echo "0")

echo ""
echo "Message counts:"
echo "  Patient messages: initial=$INITIAL_MSG_COUNT, current=$CURRENT_MSG_COUNT"
echo "  Total messages: initial=$INITIAL_TOTAL_COUNT, current=$CURRENT_TOTAL_COUNT"

# Query for new messages for this patient (created after task start)
echo ""
echo "=== Querying messages for patient PID=$PATIENT_PID ==="

# Get the newest message for this patient
NEWEST_MSG=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT id, date, title, body, user, assigned_to, pid, message_status, activity 
     FROM pnotes 
     WHERE pid=$PATIENT_PID 
     ORDER BY id DESC 
     LIMIT 1" 2>/dev/null)

echo "Newest message for patient:"
echo "$NEWEST_MSG"

# Also check for any messages mentioning the patient or BP
echo ""
echo "=== Checking for messages with BP keywords ==="
BP_MSGS=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
    "SELECT id, date, title, body, pid, assigned_to 
     FROM pnotes 
     WHERE (body LIKE '%158%' OR body LIKE '%94%' OR title LIKE '%BP%' OR title LIKE '%blood pressure%')
     AND date > '$TASK_START_DATETIME'
     ORDER BY id DESC 
     LIMIT 3" 2>/dev/null)
echo "$BP_MSGS"

# Parse the newest message data
MSG_FOUND="false"
MSG_ID=""
MSG_DATE=""
MSG_TITLE=""
MSG_BODY=""
MSG_USER=""
MSG_ASSIGNED=""
MSG_PID=""
MSG_STATUS=""
MSG_ACTIVITY=""

if [ -n "$NEWEST_MSG" ] && [ "$CURRENT_MSG_COUNT" -gt "$INITIAL_MSG_COUNT" ]; then
    MSG_FOUND="true"
    MSG_ID=$(echo "$NEWEST_MSG" | cut -f1)
    MSG_DATE=$(echo "$NEWEST_MSG" | cut -f2)
    MSG_TITLE=$(echo "$NEWEST_MSG" | cut -f3)
    MSG_BODY=$(echo "$NEWEST_MSG" | cut -f4)
    MSG_USER=$(echo "$NEWEST_MSG" | cut -f5)
    MSG_ASSIGNED=$(echo "$NEWEST_MSG" | cut -f6)
    MSG_PID=$(echo "$NEWEST_MSG" | cut -f7)
    MSG_STATUS=$(echo "$NEWEST_MSG" | cut -f8)
    MSG_ACTIVITY=$(echo "$NEWEST_MSG" | cut -f9)
    
    echo ""
    echo "New message found:"
    echo "  ID: $MSG_ID"
    echo "  Date: $MSG_DATE"
    echo "  Title: $MSG_TITLE"
    echo "  Body: $MSG_BODY"
    echo "  From: $MSG_USER"
    echo "  Assigned To: $MSG_ASSIGNED"
    echo "  Patient PID: $MSG_PID"
else
    echo "No new message found for patient PID=$PATIENT_PID"
    
    # Check if any message was created but with different patient
    if [ "$CURRENT_TOTAL_COUNT" -gt "$INITIAL_TOTAL_COUNT" ]; then
        echo ""
        echo "Note: Total message count increased, but no new message for target patient"
        echo "Checking most recent message overall:"
        docker exec openemr-mysql mysql -u openemr -popenemr openemr -e \
            "SELECT id, pid, date, title, assigned_to FROM pnotes ORDER BY id DESC LIMIT 3" 2>/dev/null
    fi
fi

# Check if assigned user is a provider
RECIPIENT_IS_PROVIDER="false"
RECIPIENT_NAME=""
if [ -n "$MSG_ASSIGNED" ] && [ "$MSG_ASSIGNED" != "NULL" ]; then
    PROVIDER_INFO=$(docker exec openemr-mysql mysql -u openemr -popenemr openemr -N -e \
        "SELECT fname, lname, authorized FROM users WHERE username='$MSG_ASSIGNED' LIMIT 1" 2>/dev/null)
    if [ -n "$PROVIDER_INFO" ]; then
        RECIPIENT_FNAME=$(echo "$PROVIDER_INFO" | cut -f1)
        RECIPIENT_LNAME=$(echo "$PROVIDER_INFO" | cut -f2)
        RECIPIENT_AUTH=$(echo "$PROVIDER_INFO" | cut -f3)
        RECIPIENT_NAME="$RECIPIENT_FNAME $RECIPIENT_LNAME"
        if [ "$RECIPIENT_AUTH" = "1" ]; then
            RECIPIENT_IS_PROVIDER="true"
        fi
        echo "Recipient: $RECIPIENT_NAME (authorized=$RECIPIENT_AUTH)"
    fi
fi

# Validate content
HAS_SYSTOLIC="false"
HAS_DIASTOLIC="false"
HAS_BP_KEYWORD="false"
HAS_REVIEW_REQUEST="false"

MSG_BODY_LOWER=$(echo "$MSG_BODY" | tr '[:upper:]' '[:lower:]')
MSG_TITLE_LOWER=$(echo "$MSG_TITLE" | tr '[:upper:]' '[:lower:]')
MSG_COMBINED="$MSG_BODY $MSG_TITLE"
MSG_COMBINED_LOWER="$MSG_BODY_LOWER $MSG_TITLE_LOWER"

if echo "$MSG_COMBINED" | grep -q "158"; then
    HAS_SYSTOLIC="true"
fi
if echo "$MSG_COMBINED" | grep -q "94"; then
    HAS_DIASTOLIC="true"
fi
if echo "$MSG_COMBINED_LOWER" | grep -qE "(bp|blood pressure|hypertension|elevated)"; then
    HAS_BP_KEYWORD="true"
fi
if echo "$MSG_COMBINED_LOWER" | grep -qE "(review|attention|please|check|see|notify|alert)"; then
    HAS_REVIEW_REQUEST="true"
fi

# Escape special characters for JSON
MSG_TITLE_ESCAPED=$(echo "$MSG_TITLE" | sed 's/"/\\"/g' | sed 's/\\/\\\\/g' | tr '\n' ' ' | tr '\r' ' ')
MSG_BODY_ESCAPED=$(echo "$MSG_BODY" | sed 's/"/\\"/g' | sed 's/\\/\\\\/g' | tr '\n' ' ' | tr '\r' ' ')
RECIPIENT_NAME_ESCAPED=$(echo "$RECIPIENT_NAME" | sed 's/"/\\"/g')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/send_msg_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "task_start_datetime": "$TASK_START_DATETIME",
    "patient_pid": $PATIENT_PID,
    "initial_patient_msg_count": ${INITIAL_MSG_COUNT:-0},
    "current_patient_msg_count": ${CURRENT_MSG_COUNT:-0},
    "initial_total_msg_count": ${INITIAL_TOTAL_COUNT:-0},
    "current_total_msg_count": ${CURRENT_TOTAL_COUNT:-0},
    "new_message_found": $MSG_FOUND,
    "message": {
        "id": "$MSG_ID",
        "date": "$MSG_DATE",
        "title": "$MSG_TITLE_ESCAPED",
        "body": "$MSG_BODY_ESCAPED",
        "sender": "$MSG_USER",
        "assigned_to": "$MSG_ASSIGNED",
        "pid": "$MSG_PID",
        "status": "$MSG_STATUS"
    },
    "recipient": {
        "username": "$MSG_ASSIGNED",
        "name": "$RECIPIENT_NAME_ESCAPED",
        "is_provider": $RECIPIENT_IS_PROVIDER
    },
    "content_validation": {
        "has_systolic_158": $HAS_SYSTOLIC,
        "has_diastolic_94": $HAS_DIASTOLIC,
        "has_bp_keyword": $HAS_BP_KEYWORD,
        "has_review_request": $HAS_REVIEW_REQUEST
    },
    "screenshot_exists": $SCREENSHOT_EXISTS
}
EOF

# Move to final location
rm -f "$RESULT_FILE" 2>/dev/null || sudo rm -f "$RESULT_FILE" 2>/dev/null || true
cp "$TEMP_JSON" "$RESULT_FILE" 2>/dev/null || sudo cp "$TEMP_JSON" "$RESULT_FILE"
chmod 666 "$RESULT_FILE" 2>/dev/null || sudo chmod 666 "$RESULT_FILE" 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "=== Export Result ==="
cat "$RESULT_FILE"
echo ""
echo "=== Export Complete ==="