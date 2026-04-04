#!/bin/bash
set -e
echo "=== Exporting bulk close conversations result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot immediately
take_screenshot /tmp/task_final.png

RESULT_DIR="/tmp/task_result_temp"
rm -rf "$RESULT_DIR"
mkdir -p "$RESULT_DIR"

# Get task start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
MAILBOX_ID=$(cat /tmp/task_mailbox_id.txt 2>/dev/null || echo "0")

# Read conversation IDs
C_CLOSE_1=$(cat /tmp/conv_to_close_1.txt 2>/dev/null || echo "")
C_CLOSE_2=$(cat /tmp/conv_to_close_2.txt 2>/dev/null || echo "")
C_CLOSE_3=$(cat /tmp/conv_to_close_3.txt 2>/dev/null || echo "")
C_KEEP_1=$(cat /tmp/conv_keep_open_1.txt 2>/dev/null || echo "")
C_KEEP_2=$(cat /tmp/conv_keep_open_2.txt 2>/dev/null || echo "")

# Helper to get conversation details JSON object
get_conv_json() {
    local id="$1"
    local label="$2"
    if [ -z "$id" ]; then
        echo "\"$label\": null,"
        return
    fi
    
    # Get status and updated_at timestamp
    # updated_at is stored as 'YYYY-MM-DD HH:MM:SS', we convert to unix timestamp
    local data
    data=$(fs_query "SELECT status, UNIX_TIMESTAMP(updated_at) FROM conversations WHERE id=$id" 2>/dev/null)
    
    local status=$(echo "$data" | awk '{print $1}')
    local updated=$(echo "$data" | awk '{print $2}')
    
    echo "\"$label\": { \"id\": $id, \"status\": \"$status\", \"updated_at\": \"$updated\" },"
}

# Collect details for all conversations
echo "Collecting conversation states..."
JSON_PARTS=""
JSON_PARTS+="$(get_conv_json "$C_CLOSE_1" "target_1")"
JSON_PARTS+="$(get_conv_json "$C_CLOSE_2" "target_2")"
JSON_PARTS+="$(get_conv_json "$C_CLOSE_3" "target_3")"
JSON_PARTS+="$(get_conv_json "$C_KEEP_1" "keep_1")"
JSON_PARTS+="$(get_conv_json "$C_KEEP_2" "keep_2")"

# Get global counts for mailbox
CLOSED_COUNT=$(fs_query "SELECT COUNT(*) FROM conversations WHERE mailbox_id=$MAILBOX_ID AND status=3" 2>/dev/null || echo "0")
ACTIVE_COUNT=$(fs_query "SELECT COUNT(*) FROM conversations WHERE mailbox_id=$MAILBOX_ID AND status=1" 2>/dev/null || echo "0")

# Check if Firefox is running
APP_RUNNING=$(pgrep -f firefox > /dev/null && echo "true" || echo "false")

# Build JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "mailbox_id": $MAILBOX_ID,
    "mailbox_counts": {
        "closed": $CLOSED_COUNT,
        "active": $ACTIVE_COUNT
    },
    "conversations": {
        ${JSON_PARTS%?}
    },
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="