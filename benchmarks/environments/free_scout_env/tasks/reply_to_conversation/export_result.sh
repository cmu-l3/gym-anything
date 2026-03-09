#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting reply_to_conversation task result ==="

# Take final screenshot
take_screenshot /tmp/task_final.png

# Load task metadata
TARGET_CONV_ID=$(cat /tmp/task_target_conv_id.txt 2>/dev/null || echo "0")
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_THREAD_COUNT=$(cat /tmp/task_initial_thread_count.txt 2>/dev/null || echo "0")
INITIAL_STATUS=$(cat /tmp/task_initial_status.txt 2>/dev/null || echo "1")

# If TARGET_CONV_ID is missing (unlikely), try to find it dynamically
if [ "$TARGET_CONV_ID" = "0" ]; then
    CONV_DATA=$(find_conversation_by_subject "VPN Connection Dropping Intermittently")
    TARGET_CONV_ID=$(echo "$CONV_DATA" | cut -f1)
fi

echo "Target conversation ID: $TARGET_CONV_ID"
echo "Task start time: $TASK_START_TIME"

# Convert task start time to MySQL datetime
TASK_START_DT=$(date -d "@$TASK_START_TIME" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "2000-01-01 00:00:00")

# 1. Check for new threads
# Thread types: 1=customer, 2=note, 3=message (reply from user)
NEW_THREAD_COUNT=$(fs_query "SELECT COUNT(*) FROM threads WHERE conversation_id=$TARGET_CONV_ID AND created_at > '$TASK_START_DT'" 2>/dev/null || echo "0")
CURRENT_THREAD_COUNT=$(fs_query "SELECT COUNT(*) FROM threads WHERE conversation_id=$TARGET_CONV_ID" 2>/dev/null || echo "0")

REPLY_EXISTS="false"
if [ "$NEW_THREAD_COUNT" -gt 0 ]; then
    REPLY_EXISTS="true"
fi

# 2. Get the content of the reply
REPLY_BODY=""
REPLY_USER_ID=""
if [ "$REPLY_EXISTS" = "true" ]; then
    # Get the body of the newest thread created after task start
    REPLY_DATA=$(fs_query "SELECT body, created_by_user_id FROM threads WHERE conversation_id=$TARGET_CONV_ID AND created_at > '$TASK_START_DT' ORDER BY id DESC LIMIT 1" 2>/dev/null)
    REPLY_BODY=$(echo "$REPLY_DATA" | cut -f1)
    REPLY_USER_ID=$(echo "$REPLY_DATA" | cut -f2)
fi

# 3. Get current conversation status
CURRENT_STATUS=$(fs_query "SELECT status FROM conversations WHERE id=$TARGET_CONV_ID" 2>/dev/null || echo "0")
CONV_SUBJECT=$(fs_query "SELECT subject FROM conversations WHERE id=$TARGET_CONV_ID" 2>/dev/null || echo "")

# Escape fields for JSON
REPLY_BODY_ESC=$(echo "$REPLY_BODY" | sed 's/"/\\"/g' | tr -d '\n' | sed 's/\r//g')
CONV_SUBJECT_ESC=$(echo "$CONV_SUBJECT" | sed 's/"/\\"/g')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "target_conversation_id": "${TARGET_CONV_ID}",
    "conversation_subject": "${CONV_SUBJECT_ESC}",
    "reply_exists": ${REPLY_EXISTS},
    "reply_body": "${REPLY_BODY_ESC}",
    "reply_user_id": "${REPLY_USER_ID}",
    "current_status": ${CURRENT_STATUS},
    "initial_status": ${INITIAL_STATUS},
    "new_thread_count": ${NEW_THREAD_COUNT},
    "current_thread_count": ${CURRENT_THREAD_COUNT},
    "initial_thread_count": ${INITIAL_THREAD_COUNT},
    "task_start_time": ${TASK_START_TIME},
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="