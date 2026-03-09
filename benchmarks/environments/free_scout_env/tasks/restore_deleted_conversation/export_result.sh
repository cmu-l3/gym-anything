#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Verifying restore_deleted_conversation task ==="

# Record task end
TASK_END=$(date +%s)

# Load saved state
TARGET_CONV_ID=$(cat /tmp/target_conv_id.txt 2>/dev/null || echo "")
TARGET_MAILBOX_ID=$(cat /tmp/target_mailbox_id.txt 2>/dev/null || echo "")
INITIAL_STATE=$(cat /tmp/initial_conv_state.txt 2>/dev/null || echo "3")
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

echo "Target Conversation ID: $TARGET_CONV_ID"
echo "Target Mailbox ID: $TARGET_MAILBOX_ID"
echo "Initial State: $INITIAL_STATE"
echo "Task Start Time: $TASK_START_TIME"

if [ -z "$TARGET_CONV_ID" ]; then
    echo "ERROR: No target conversation ID found"
    # Create empty result to fail gracefully in verifier
    echo '{}' > /tmp/task_result.json
    exit 0
fi

# ===== Capture final screenshot =====
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# ===== Check 1: Current Conversation State =====
# State 1 = Published (Active)
# State 2 = Draft
# State 3 = Deleted
CURRENT_STATE=$(fs_query "SELECT state FROM conversations WHERE id = $TARGET_CONV_ID" 2>/dev/null | tr -cd '0-9')
echo "Current state: $CURRENT_STATE"

# ===== Check 2: Current Conversation Status =====
# Status 1 = Active
# Status 2 = Pending
# Status 3 = Closed
CURRENT_STATUS=$(fs_query "SELECT status FROM conversations WHERE id = $TARGET_CONV_ID" 2>/dev/null | tr -cd '0-9')
echo "Current status: $CURRENT_STATUS"

# ===== Check 3: Current Mailbox =====
CURRENT_MAILBOX=$(fs_query "SELECT mailbox_id FROM conversations WHERE id = $TARGET_CONV_ID" 2>/dev/null | tr -cd '0-9')
echo "Current mailbox ID: $CURRENT_MAILBOX"

# ===== Check 4: Last Updated Timestamp =====
UPDATED_AT_UNIX=$(fs_query "SELECT UNIX_TIMESTAMP(updated_at) FROM conversations WHERE id = $TARGET_CONV_ID" 2>/dev/null | tr -cd '0-9')
echo "Updated at (unix): $UPDATED_AT_UNIX"

# Check if application was running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START_TIME,
    "task_end_time": $TASK_END,
    "conversation_id": "$TARGET_CONV_ID",
    "initial_state": "$INITIAL_STATE",
    "current_state": "$CURRENT_STATE",
    "current_status": "$CURRENT_STATUS",
    "current_mailbox_id": "$CURRENT_MAILBOX",
    "expected_mailbox_id": "$TARGET_MAILBOX_ID",
    "updated_at_unix": "$UPDATED_AT_UNIX",
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
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