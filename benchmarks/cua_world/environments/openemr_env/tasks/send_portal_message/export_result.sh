#!/bin/bash
# Export script for Send Portal Message Task

echo "=== Exporting Send Portal Message Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Target patient
PATIENT_PID=3

# Get timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Get initial counts
INITIAL_PNOTES=$(cat /tmp/initial_pnotes_count 2>/dev/null || echo "0")
INITIAL_PORTAL_MSG=$(cat /tmp/initial_portal_msg_count 2>/dev/null || echo "0")
INITIAL_ONSITE_MAIL=$(cat /tmp/initial_onsite_mail_count 2>/dev/null || echo "0")

# Get current counts
CURRENT_PNOTES=$(openemr_query "SELECT COUNT(*) FROM pnotes WHERE pid=$PATIENT_PID" 2>/dev/null || echo "0")
CURRENT_PORTAL_MSG=$(openemr_query "SELECT COUNT(*) FROM onsite_messages WHERE recip_id=$PATIENT_PID" 2>/dev/null || echo "0")
CURRENT_ONSITE_MAIL=$(openemr_query "SELECT COUNT(*) FROM onsite_mail WHERE recipient_id='$PATIENT_PID'" 2>/dev/null || echo "0")

echo "Message counts:"
echo "  pnotes: $INITIAL_PNOTES -> $CURRENT_PNOTES"
echo "  onsite_messages: $INITIAL_PORTAL_MSG -> $CURRENT_PORTAL_MSG"
echo "  onsite_mail: $INITIAL_ONSITE_MAIL -> $CURRENT_ONSITE_MAIL"

# Initialize result variables
MESSAGE_FOUND="false"
MESSAGE_TABLE=""
MESSAGE_ID=""
MESSAGE_SUBJECT=""
MESSAGE_BODY=""
MESSAGE_STATUS=""
MESSAGE_DATE=""

# Check pnotes table for new messages
echo ""
echo "=== Checking pnotes table ==="
if [ "$CURRENT_PNOTES" -gt "$INITIAL_PNOTES" ]; then
    echo "New pnote(s) found"
    PNOTE_DATA=$(openemr_query "SELECT id, title, body, message_status, date FROM pnotes WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 1" 2>/dev/null)
    if [ -n "$PNOTE_DATA" ]; then
        MESSAGE_FOUND="true"
        MESSAGE_TABLE="pnotes"
        MESSAGE_ID=$(echo "$PNOTE_DATA" | cut -f1)
        MESSAGE_SUBJECT=$(echo "$PNOTE_DATA" | cut -f2)
        MESSAGE_BODY=$(echo "$PNOTE_DATA" | cut -f3)
        MESSAGE_STATUS=$(echo "$PNOTE_DATA" | cut -f4)
        MESSAGE_DATE=$(echo "$PNOTE_DATA" | cut -f5)
        echo "Found pnote: ID=$MESSAGE_ID, Subject='$MESSAGE_SUBJECT'"
    fi
fi

# Check onsite_messages table
echo ""
echo "=== Checking onsite_messages table ==="
if [ "$CURRENT_PORTAL_MSG" -gt "$INITIAL_PORTAL_MSG" ]; then
    echo "New portal message(s) found"
    PORTAL_DATA=$(openemr_query "SELECT id, title, body, status, date FROM onsite_messages WHERE recip_id=$PATIENT_PID ORDER BY id DESC LIMIT 1" 2>/dev/null)
    if [ -n "$PORTAL_DATA" ]; then
        MESSAGE_FOUND="true"
        MESSAGE_TABLE="onsite_messages"
        MESSAGE_ID=$(echo "$PORTAL_DATA" | cut -f1)
        MESSAGE_SUBJECT=$(echo "$PORTAL_DATA" | cut -f2)
        MESSAGE_BODY=$(echo "$PORTAL_DATA" | cut -f3)
        MESSAGE_STATUS=$(echo "$PORTAL_DATA" | cut -f4)
        MESSAGE_DATE=$(echo "$PORTAL_DATA" | cut -f5)
        echo "Found portal message: ID=$MESSAGE_ID, Subject='$MESSAGE_SUBJECT'"
    fi
fi

# Check onsite_mail table
echo ""
echo "=== Checking onsite_mail table ==="
if [ "$CURRENT_ONSITE_MAIL" -gt "$INITIAL_ONSITE_MAIL" ]; then
    echo "New onsite mail found"
    MAIL_DATA=$(openemr_query "SELECT id, subject, body, status, date FROM onsite_mail WHERE recipient_id='$PATIENT_PID' ORDER BY id DESC LIMIT 1" 2>/dev/null)
    if [ -n "$MAIL_DATA" ]; then
        MESSAGE_FOUND="true"
        MESSAGE_TABLE="onsite_mail"
        MESSAGE_ID=$(echo "$MAIL_DATA" | cut -f1)
        MESSAGE_SUBJECT=$(echo "$MAIL_DATA" | cut -f2)
        MESSAGE_BODY=$(echo "$MAIL_DATA" | cut -f3)
        MESSAGE_STATUS=$(echo "$MAIL_DATA" | cut -f4)
        MESSAGE_DATE=$(echo "$MAIL_DATA" | cut -f5)
        echo "Found onsite mail: ID=$MESSAGE_ID, Subject='$MESSAGE_SUBJECT'"
    fi
fi

# Also check for any recent entries regardless of count (in case count was wrong)
echo ""
echo "=== Checking for recent messages (fallback) ==="
RECENT_PNOTE=$(openemr_query "SELECT id, title, body, message_status, date FROM pnotes WHERE pid=$PATIENT_PID AND (title LIKE '%Lab%' OR title LIKE '%lab%' OR body LIKE '%lab%' OR body LIKE '%Lab%') ORDER BY id DESC LIMIT 1" 2>/dev/null)
if [ -n "$RECENT_PNOTE" ] && [ "$MESSAGE_FOUND" = "false" ]; then
    MESSAGE_FOUND="true"
    MESSAGE_TABLE="pnotes"
    MESSAGE_ID=$(echo "$RECENT_PNOTE" | cut -f1)
    MESSAGE_SUBJECT=$(echo "$RECENT_PNOTE" | cut -f2)
    MESSAGE_BODY=$(echo "$RECENT_PNOTE" | cut -f3)
    MESSAGE_STATUS=$(echo "$RECENT_PNOTE" | cut -f4)
    MESSAGE_DATE=$(echo "$RECENT_PNOTE" | cut -f5)
    echo "Found matching pnote via keyword search"
fi

# Debug: Show all recent pnotes for this patient
echo ""
echo "=== DEBUG: All recent pnotes for patient ==="
openemr_query "SELECT id, title, LEFT(body, 100) as body_preview, message_status, date FROM pnotes WHERE pid=$PATIENT_PID ORDER BY id DESC LIMIT 5" 2>/dev/null
echo "=== END DEBUG ==="

# Validate message content
SUBJECT_HAS_LAB="false"
SUBJECT_HAS_FOLLOWUP="false"
BODY_HAS_LAB="false"
BODY_HAS_SCHEDULE="false"
BODY_HAS_PHONE="false"
IS_SENT="false"

if [ "$MESSAGE_FOUND" = "true" ]; then
    # Convert to lowercase for checking
    SUBJECT_LOWER=$(echo "$MESSAGE_SUBJECT" | tr '[:upper:]' '[:lower:]')
    BODY_LOWER=$(echo "$MESSAGE_BODY" | tr '[:upper:]' '[:lower:]')
    
    # Check subject
    if echo "$SUBJECT_LOWER" | grep -qE "(lab|result)"; then
        SUBJECT_HAS_LAB="true"
    fi
    if echo "$SUBJECT_LOWER" | grep -qE "(follow|schedule)"; then
        SUBJECT_HAS_FOLLOWUP="true"
    fi
    
    # Check body
    if echo "$BODY_LOWER" | grep -qE "(lab|result)"; then
        BODY_HAS_LAB="true"
    fi
    if echo "$BODY_LOWER" | grep -qE "(schedule|follow|appointment)"; then
        BODY_HAS_SCHEDULE="true"
    fi
    if echo "$MESSAGE_BODY" | grep -qE "555.?0100"; then
        BODY_HAS_PHONE="true"
    fi
    
    # Check if sent (not draft)
    STATUS_LOWER=$(echo "$MESSAGE_STATUS" | tr '[:upper:]' '[:lower:]')
    if echo "$STATUS_LOWER" | grep -qE "(sent|new|unread|read|1)" || [ -z "$MESSAGE_STATUS" ]; then
        IS_SENT="true"
    fi
    if echo "$STATUS_LOWER" | grep -qE "(draft|unsent|0)"; then
        IS_SENT="false"
    fi
fi

# Escape special characters for JSON
MESSAGE_SUBJECT_ESCAPED=$(echo "$MESSAGE_SUBJECT" | sed 's/"/\\"/g' | tr '\n' ' ' | head -c 500)
MESSAGE_BODY_ESCAPED=$(echo "$MESSAGE_BODY" | sed 's/"/\\"/g' | tr '\n' ' ' | head -c 2000)

# Create result JSON
TEMP_JSON=$(mktemp /tmp/portal_message_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "patient_pid": $PATIENT_PID,
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "counts": {
        "initial_pnotes": $INITIAL_PNOTES,
        "current_pnotes": $CURRENT_PNOTES,
        "initial_portal_msg": $INITIAL_PORTAL_MSG,
        "current_portal_msg": $CURRENT_PORTAL_MSG,
        "initial_onsite_mail": $INITIAL_ONSITE_MAIL,
        "current_onsite_mail": $CURRENT_ONSITE_MAIL
    },
    "message_found": $MESSAGE_FOUND,
    "message": {
        "table": "$MESSAGE_TABLE",
        "id": "$MESSAGE_ID",
        "subject": "$MESSAGE_SUBJECT_ESCAPED",
        "body": "$MESSAGE_BODY_ESCAPED",
        "status": "$MESSAGE_STATUS",
        "date": "$MESSAGE_DATE"
    },
    "validation": {
        "subject_has_lab": $SUBJECT_HAS_LAB,
        "subject_has_followup": $SUBJECT_HAS_FOLLOWUP,
        "body_has_lab": $BODY_HAS_LAB,
        "body_has_schedule": $BODY_HAS_SCHEDULE,
        "body_has_phone": $BODY_HAS_PHONE,
        "is_sent_not_draft": $IS_SENT
    },
    "screenshot_exists": $([ -f "/tmp/task_final.png" ] && echo "true" || echo "false"),
    "export_timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/send_portal_message_result.json 2>/dev/null || sudo rm -f /tmp/send_portal_message_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/send_portal_message_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/send_portal_message_result.json
chmod 666 /tmp/send_portal_message_result.json 2>/dev/null || sudo chmod 666 /tmp/send_portal_message_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result JSON saved to /tmp/send_portal_message_result.json"
cat /tmp/send_portal_message_result.json
echo ""
echo "=== Export Complete ==="