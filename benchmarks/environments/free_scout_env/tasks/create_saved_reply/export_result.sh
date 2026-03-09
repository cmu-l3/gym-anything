#!/bin/bash
echo "=== Exporting create_saved_reply result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Load start time and initial count
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_saved_reply_count.txt 2>/dev/null || echo "0")
EXPECTED_MAILBOX_ID=$(cat /tmp/expected_mailbox_id.txt 2>/dev/null || echo "")

# Get current count
CURRENT_COUNT=$(fs_query "SELECT COUNT(*) FROM saved_replies" 2>/dev/null || echo "0")

# Search for the saved reply by name
# We look for the exact name or a very close match
TARGET_NAME="Password Reset Instructions"

echo "Searching for saved reply: '$TARGET_NAME'..."

# Query details: ID, Name, MailboxID, Text Body, CreatedAt timestamp
REPLY_DATA=$(fs_query "SELECT id, name, mailbox_id, text, UNIX_TIMESTAMP(created_at) FROM saved_replies WHERE LOWER(TRIM(name)) = LOWER(TRIM('$TARGET_NAME')) ORDER BY id DESC LIMIT 1" 2>/dev/null)

REPLY_FOUND="false"
REPLY_ID=""
REPLY_NAME=""
REPLY_MAILBOX_ID=""
REPLY_TEXT=""
REPLY_CREATED_TS="0"

if [ -n "$REPLY_DATA" ]; then
    REPLY_FOUND="true"
    REPLY_ID=$(echo "$REPLY_DATA" | cut -f1)
    REPLY_NAME=$(echo "$REPLY_DATA" | cut -f2)
    REPLY_MAILBOX_ID=$(echo "$REPLY_DATA" | cut -f3)
    REPLY_TEXT=$(echo "$REPLY_DATA" | cut -f4)
    REPLY_CREATED_TS=$(echo "$REPLY_DATA" | cut -f5)
fi

# If not found by exact name, try partial match (for scoring partial credit if needed)
if [ "$REPLY_FOUND" = "false" ]; then
    REPLY_DATA=$(fs_query "SELECT id, name, mailbox_id, text, UNIX_TIMESTAMP(created_at) FROM saved_replies WHERE LOWER(name) LIKE '%password reset%' ORDER BY id DESC LIMIT 1" 2>/dev/null)
    if [ -n "$REPLY_DATA" ]; then
        # We found something similar, but flag it
        REPLY_ID=$(echo "$REPLY_DATA" | cut -f1)
        REPLY_NAME=$(echo "$REPLY_DATA" | cut -f2)
        REPLY_MAILBOX_ID=$(echo "$REPLY_DATA" | cut -f3)
        REPLY_TEXT=$(echo "$REPLY_DATA" | cut -f4)
        REPLY_CREATED_TS=$(echo "$REPLY_DATA" | cut -f5)
        # We don't mark REPLY_FOUND=true because the name wasn't exact, 
        # but we export the data for the verifier to decide on partial credit
    fi
fi

# Sanitize text for JSON (escape quotes and newlines)
# We use python for robust escaping to avoid JSON syntax errors
ESCAPED_TEXT=$(python3 -c "import sys, json; print(json.dumps(sys.stdin.read()))" <<< "$REPLY_TEXT")
# The python output includes surrounding quotes, remove them
ESCAPED_TEXT=${ESCAPED_TEXT:1:-1}

ESCAPED_NAME=$(echo "$REPLY_NAME" | sed 's/"/\\"/g')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "expected_mailbox_id": "$EXPECTED_MAILBOX_ID",
    "reply_found_exact": $REPLY_FOUND,
    "reply_id": "$REPLY_ID",
    "reply_name": "$ESCAPED_NAME",
    "reply_mailbox_id": "$REPLY_MAILBOX_ID",
    "reply_text": "$ESCAPED_TEXT",
    "reply_created_timestamp": ${REPLY_CREATED_TS:-0},
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="