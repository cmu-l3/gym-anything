#!/bin/bash
set -e
echo "=== Exporting set_conversation_pending result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot immediately
take_screenshot /tmp/task_final.png

# Load saved state
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_ID=$(cat /tmp/target_conversation_id.txt 2>/dev/null || echo "0")
INITIAL_STATUS=$(cat /tmp/initial_status.txt 2>/dev/null || echo "1")

echo "Checking status for Conversation ID: $TARGET_ID"

# 1. Get Current Status
CURRENT_STATUS=$(fs_query "SELECT status FROM conversations WHERE id = $TARGET_ID" | tr -cd '0-9')

# 2. Get Update Timestamp
UPDATED_AT_RAW=$(fs_query "SELECT updated_at FROM conversations WHERE id = $TARGET_ID")
UPDATED_AT_TS=$(date -d "$UPDATED_AT_RAW" +%s 2>/dev/null || echo "0")

# 3. Check for Anti-Gaming (Did they mess up other tickets?)
# Count how many OTHER conversations in this mailbox are Pending (Status 2)
# We assume there were 0 pending initially based on setup script.
# We need to get the mailbox ID for the target first to scope the check.
MAILBOX_ID=$(fs_query "SELECT mailbox_id FROM conversations WHERE id = $TARGET_ID" | tr -cd '0-9')
OTHER_PENDING_COUNT=$(fs_query "SELECT COUNT(*) FROM conversations WHERE mailbox_id = $MAILBOX_ID AND status = 2 AND id != $TARGET_ID" | tr -cd '0-9')

echo "Current Status: $CURRENT_STATUS"
echo "Updated At: $UPDATED_AT_RAW ($UPDATED_AT_TS)"
echo "Task Start: $TASK_START"
echo "Other Pending: $OTHER_PENDING_COUNT"

# 4. JSON Export
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "target_conversation_id": ${TARGET_ID:-0},
  "initial_status": ${INITIAL_STATUS:-1},
  "current_status": ${CURRENT_STATUS:-0},
  "updated_at_ts": ${UPDATED_AT_TS:-0},
  "task_start_ts": ${TASK_START:-0},
  "other_pending_count": ${OTHER_PENDING_COUNT:-0},
  "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
safe_write_result "$TEMP_JSON" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="