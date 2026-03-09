#!/bin/bash
# Export script for Send Provider Message task
# Verifies the message was created in the database

echo "=== Exporting Send Provider Message Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Get the initial max message ID to find new messages
INITIAL_MAX_ID=$(cat /tmp/initial_max_msg_id 2>/dev/null || echo "0")
echo "Searching for messages with ID > $INITIAL_MAX_ID..."

# Query for the latest message sent by oscardoc (999998) created during the task
# We join messagetbl (content) with messagelisttbl (recipient linkage)
# messagetbl columns: message_id, subject, message, sentby, status, messagedate
# messagelisttbl columns: message_id, provider_no (recipient), status
# Note: provider_no in messagelisttbl is the recipient

QUERY="SELECT 
    m.message_id, 
    m.subject, 
    m.message, 
    m.sentby, 
    l.provider_no as recipient_id
FROM messagetbl m 
JOIN messagelisttbl l ON m.message_id = l.message_id 
WHERE m.message_id > $INITIAL_MAX_ID 
  AND m.sentby = '999998' 
ORDER BY m.message_id DESC LIMIT 1"

echo "Executing query..."
# Use python/mysql connector or raw mysql cli formatted as JSON-like structure
# We'll use raw mysql and parse safely in python verifier, or output simple lines here

RESULT_RAW=$(docker exec oscar-db mysql -u oscar -poscar oscar -N -e "$QUERY" 2>/dev/null)

MSG_FOUND="false"
MSG_ID=""
MSG_SUBJECT=""
MSG_BODY=""
MSG_SENDER=""
MSG_RECIPIENT=""

if [ -n "$RESULT_RAW" ]; then
    MSG_FOUND="true"
    # MySQL -N output is tab separated
    MSG_ID=$(echo "$RESULT_RAW" | cut -f1)
    MSG_SUBJECT=$(echo "$RESULT_RAW" | cut -f2)
    MSG_BODY=$(echo "$RESULT_RAW" | cut -f3)
    MSG_SENDER=$(echo "$RESULT_RAW" | cut -f4)
    MSG_RECIPIENT=$(echo "$RESULT_RAW" | cut -f5)
    
    echo "Found Message:"
    echo "  ID: $MSG_ID"
    echo "  Subject: $MSG_SUBJECT"
    echo "  Sender: $MSG_SENDER"
    echo "  Recipient: $MSG_RECIPIENT"
else
    echo "No new messages found from provider 999998."
fi

# Escape for JSON (basic escaping for quotes and newlines)
# Using python for safe JSON creation
python3 -c "
import json
import os
import sys

data = {
    'found': '$MSG_FOUND' == 'true',
    'message_id': '$MSG_ID',
    'subject': '''$MSG_SUBJECT''',
    'body': '''$MSG_BODY''',
    'sender': '$MSG_SENDER',
    'recipient': '$MSG_RECIPIENT',
    'initial_max_id': '$INITIAL_MAX_ID'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(data, f, indent=2)
"

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="