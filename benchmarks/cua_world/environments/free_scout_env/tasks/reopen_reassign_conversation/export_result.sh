#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Verifying reopen_reassign_conversation task ==="

RESULT_FILE="/tmp/task_result.json"

# Load task data
CONV_ID=$(cat /tmp/task_conv_id.txt 2>/dev/null | tr -cd '0-9')
MARCUS_ID=$(cat /tmp/task_marcus_id.txt 2>/dev/null | tr -cd '0-9')
PRIYA_ID=$(cat /tmp/task_priya_id.txt 2>/dev/null | tr -cd '0-9')
MAILBOX_ID=$(cat /tmp/task_mailbox_id.txt 2>/dev/null | tr -cd '0-9')
INITIAL_STATUS=$(cat /tmp/task_initial_status.txt 2>/dev/null | tr -cd '0-9')
INITIAL_USER=$(cat /tmp/task_initial_user_id.txt 2>/dev/null | tr -cd '0-9')

if [ -z "$CONV_ID" ] || [ -z "$PRIYA_ID" ]; then
    echo '{"error": "Task setup data not found"}' > "$RESULT_FILE"
    chmod 666 "$RESULT_FILE" 2>/dev/null || true
    exit 0
fi

echo "Checking Conversation ID: $CONV_ID"
echo "Marcus (original) ID: $MARCUS_ID"
echo "Priya (expected new) ID: $PRIYA_ID"

# Take final screenshot for evidence
take_screenshot /tmp/task_final.png

# ===== Check 1: Conversation integrity =====
CONV_EXISTS=$(fs_query "SELECT COUNT(*) FROM conversations WHERE id = $CONV_ID" 2>/dev/null | tr -cd '0-9')

# ===== Check 2: Conversation status =====
CURRENT_STATUS=$(fs_query "SELECT status FROM conversations WHERE id = $CONV_ID" 2>/dev/null | tr -cd '0-9')
echo "Current status: $CURRENT_STATUS (1=Active, 2=Pending, 3=Closed)"

# ===== Check 3: Conversation assignment =====
CURRENT_USER=$(fs_query "SELECT user_id FROM conversations WHERE id = $CONV_ID" 2>/dev/null | tr -cd '0-9')
echo "Current user_id: $CURRENT_USER"

# ===== Check 4: Subject integrity =====
CURRENT_SUBJECT=$(fs_query "SELECT subject FROM conversations WHERE id = $CONV_ID" 2>/dev/null)
SUBJECT_INTACT="false"
if echo "$CURRENT_SUBJECT" | grep -qi "VPN connection drops"; then
    SUBJECT_INTACT="true"
fi

# ===== Check 5: Folder updated =====
CURRENT_FOLDER=$(fs_query "SELECT folder_id FROM conversations WHERE id = $CONV_ID" 2>/dev/null | tr -cd '0-9')
CLOSED_FOLDER=$(fs_query "SELECT id FROM folders WHERE mailbox_id = $MAILBOX_ID AND type = 3 LIMIT 1" 2>/dev/null | tr -cd '0-9')
FOLDER_CHANGED="false"
if [ -n "$CURRENT_FOLDER" ] && [ -n "$CLOSED_FOLDER" ] && [ "$CURRENT_FOLDER" != "$CLOSED_FOLDER" ]; then
    FOLDER_CHANGED="true"
fi

# Write result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "conversation_exists": $([ "$CONV_EXISTS" = "1" ] && echo "true" || echo "false"),
    "conversation_id": "$CONV_ID",
    "initial_status": "$INITIAL_STATUS",
    "current_status": "$CURRENT_STATUS",
    "initial_user_id": "$INITIAL_USER",
    "current_user_id": "$CURRENT_USER",
    "expected_user_id": "$PRIYA_ID",
    "subject_intact": $SUBJECT_INTACT,
    "folder_changed": $FOLDER_CHANGED,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with permission handling
rm -f "$RESULT_FILE" 2>/dev/null || sudo rm -f "$RESULT_FILE" 2>/dev/null || true
cp "$TEMP_JSON" "$RESULT_FILE" 2>/dev/null || sudo cp "$TEMP_JSON" "$RESULT_FILE"
chmod 666 "$RESULT_FILE" 2>/dev/null || sudo chmod 666 "$RESULT_FILE" 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="