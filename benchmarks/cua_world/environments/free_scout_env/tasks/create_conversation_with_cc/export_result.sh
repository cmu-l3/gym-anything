#!/bin/bash
set -e
echo "=== Exporting create_conversation_with_cc result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Get Counts
INITIAL_CONV_COUNT=$(cat /tmp/initial_conv_count.txt 2>/dev/null || echo "0")
CURRENT_CONV_COUNT=$(get_conversation_count)
EXPECTED_MAILBOX_ID=$(cat /tmp/av_mailbox_id.txt 2>/dev/null || echo "0")
EXPECTED_CUSTOMER_ID=$(cat /tmp/customer_id.txt 2>/dev/null || echo "0")

# Find conversation by subject
SUBJECT_QUERY="Projector Maintenance Request"
CONV_DATA=$(find_conversation_by_subject "$SUBJECT_QUERY")

CONV_FOUND="false"
CONV_ID=""
CONV_SUBJECT=""
CONV_MAILBOX_ID=""
CONV_CUSTOMER_ID=""
THREAD_CC=""
THREAD_BODY=""
THREAD_TO=""

if [ -n "$CONV_DATA" ]; then
    CONV_FOUND="true"
    CONV_ID=$(echo "$CONV_DATA" | cut -f1)
    CONV_SUBJECT=$(echo "$CONV_DATA" | cut -f3)
    CONV_MAILBOX_ID=$(echo "$CONV_DATA" | cut -f5)
    CONV_CUSTOMER_ID=$(echo "$CONV_DATA" | cut -f7)
    
    # Get thread details (first thread usually contains the CCs and initial body)
    THREAD_DATA=$(fs_query "SELECT cc, body, \`to\` FROM threads WHERE conversation_id=$CONV_ID ORDER BY id ASC LIMIT 1" 2>/dev/null)
    
    if [ -n "$THREAD_DATA" ]; then
        THREAD_CC=$(echo "$THREAD_DATA" | cut -f1)
        THREAD_BODY=$(echo "$THREAD_DATA" | cut -f2)
        THREAD_TO=$(echo "$THREAD_DATA" | cut -f3)
        
        # If cut logic is fragile due to content, try specific queries
        THREAD_CC=$(fs_query "SELECT cc FROM threads WHERE conversation_id=$CONV_ID ORDER BY id ASC LIMIT 1" 2>/dev/null)
        THREAD_BODY=$(fs_query "SELECT body FROM threads WHERE conversation_id=$CONV_ID ORDER BY id ASC LIMIT 1" 2>/dev/null)
        THREAD_TO=$(fs_query "SELECT \`to\` FROM threads WHERE conversation_id=$CONV_ID ORDER BY id ASC LIMIT 1" 2>/dev/null)
    fi
fi

# Escape JSON strings
clean_json_string() {
    echo "$1" | sed 's/\\/\\\\/g' | sed 's/"/\\"/g' | sed 's/
/\\n/g' | tr -d '\r'
}

SAFE_SUBJECT=$(clean_json_string "$CONV_SUBJECT")
SAFE_CC=$(clean_json_string "$THREAD_CC")
SAFE_BODY=$(clean_json_string "$THREAD_BODY")
SAFE_TO=$(clean_json_string "$THREAD_TO")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_conv_count": ${INITIAL_CONV_COUNT},
    "current_conv_count": ${CURRENT_CONV_COUNT},
    "expected_mailbox_id": "${EXPECTED_MAILBOX_ID}",
    "expected_customer_id": "${EXPECTED_CUSTOMER_ID}",
    "conversation_found": ${CONV_FOUND},
    "conversation": {
        "id": "${CONV_ID}",
        "subject": "${SAFE_SUBJECT}",
        "mailbox_id": "${CONV_MAILBOX_ID}",
        "customer_id": "${CONV_CUSTOMER_ID}",
        "thread_cc": "${SAFE_CC}",
        "thread_body": "${SAFE_BODY}",
        "thread_to": "${SAFE_TO}"
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_result "$TEMP_JSON" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="