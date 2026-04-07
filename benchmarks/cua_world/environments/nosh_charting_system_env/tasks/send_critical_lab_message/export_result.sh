#!/bin/bash
echo "=== Exporting send_critical_lab_message results ==="

# Get timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Query the database for the message
# We need to verify:
# 1. Message exists
# 2. Created AFTER task start
# 3. Recipient is 'demo_provider' (ID usually 2)
# 4. Patient is 'Maria Rodriguez'
# 5. Subject contains 'URGENT'
# 6. Body contains '6.2'

echo "Querying NOSH database for messages..."

# Construct SQL query to return JSON-like structure or specific fields
# We look for the most recent message matching criteria
SQL_QUERY="SELECT 
    m.message_id, 
    m.date, 
    m.subject, 
    m.body, 
    u_to.username as recipient, 
    d.firstname, 
    d.lastname,
    m.pid
FROM messaging m
JOIN users u_to ON m.user_id_to = u_to.id
LEFT JOIN demographics d ON m.pid = d.pid
WHERE m.date >= FROM_UNIXTIME($TASK_START)
  AND m.subject LIKE '%URGENT%'
  AND m.body LIKE '%6.2%'
ORDER BY m.message_id DESC LIMIT 1;"

# Execute Query
RESULT_STR=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "$SQL_QUERY" 2>/dev/null)

# Parse Result
MESSAGE_FOUND="false"
RECIPIENT=""
PATIENT_NAME=""
SUBJECT=""
BODY=""

if [ -n "$RESULT_STR" ]; then
    MESSAGE_FOUND="true"
    # Result format is tab separated: ID, Date, Subject, Body, Recipient, FName, LName, PID
    RECIPIENT=$(echo "$RESULT_STR" | cut -f5)
    PATIENT_FNAME=$(echo "$RESULT_STR" | cut -f6)
    PATIENT_LNAME=$(echo "$RESULT_STR" | cut -f7)
    SUBJECT=$(echo "$RESULT_STR" | cut -f3)
    PATIENT_NAME="$PATIENT_FNAME $PATIENT_LNAME"
else
    # Debug: Check if ANY message was sent to verify activity
    DEBUG_COUNT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "SELECT COUNT(*) FROM messaging WHERE date >= FROM_UNIXTIME($TASK_START)")
    echo "Debug: Total messages sent during task: $DEBUG_COUNT"
fi

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "message_found": $MESSAGE_FOUND,
    "recipient": "$RECIPIENT",
    "patient_name": "$PATIENT_NAME",
    "subject_snippet": "$SUBJECT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="