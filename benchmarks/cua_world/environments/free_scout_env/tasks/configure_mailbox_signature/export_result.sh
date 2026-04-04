#!/bin/bash
set -e
echo "=== Exporting configure_mailbox_signature result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Get mailbox ID
MAILBOX_ID=$(cat /tmp/task_mailbox_id.txt 2>/dev/null || echo "")
if [ -z "$MAILBOX_ID" ]; then
    MAILBOX_ID=$(fs_query "SELECT id FROM mailboxes WHERE email='itsupport@acmecorp.com' ORDER BY id DESC LIMIT 1" 2>/dev/null)
fi

echo "Mailbox ID: $MAILBOX_ID"

MAILBOX_FOUND="false"
SIGNATURE_RAW=""
UPDATED_AT_TIMESTAMP="0"
TASK_START_TIMESTAMP=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

if [ -n "$MAILBOX_ID" ] && [ "$MAILBOX_ID" != "0" ]; then
    MAILBOX_FOUND="true"
    
    # Get the raw signature HTML
    SIGNATURE_RAW=$(fs_query "SELECT signature FROM mailboxes WHERE id = $MAILBOX_ID" 2>/dev/null || echo "")
    
    # Get the updated_at timestamp
    UPDATED_AT_TIMESTAMP=$(fs_query "SELECT UNIX_TIMESTAMP(updated_at) FROM mailboxes WHERE id = $MAILBOX_ID" 2>/dev/null || echo "0")
fi

# Escape JSON strings
# We use Python for safe escaping to handle HTML content properly
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

python3 -c "
import json
import os

try:
    sig = '''$SIGNATURE_RAW'''
except:
    sig = \"\"

result = {
    'mailbox_found': $MAILBOX_FOUND,
    'mailbox_id': '$MAILBOX_ID',
    'signature_content': sig,
    'updated_at': $UPDATED_AT_TIMESTAMP,
    'task_start': $TASK_START_TIMESTAMP,
    'screenshot_path': '/tmp/task_final.png'
}

with open('$TEMP_JSON', 'w') as f:
    json.dump(result, f)
"

# Move to standard location with safe permissions
safe_write_result "$TEMP_JSON" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="