#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting close_conversation result ==="

# Record task end
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CONV_ID=$(cat /tmp/target_conv_id.txt 2>/dev/null || echo "")
INITIAL_STATUS=$(cat /tmp/initial_conv_status.txt 2>/dev/null || echo "1")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Query Database for Final State
echo "Querying database for conversation $CONV_ID..."

if [ -n "$CONV_ID" ]; then
    # Get all relevant fields
    # Status: 1=Active, 2=Pending, 3=Closed
    # State: 1=Published, 3=Deleted
    CONV_DATA=$(fs_query "SELECT status, state, UNIX_TIMESTAMP(updated_at) FROM conversations WHERE id = $CONV_ID" 2>/dev/null)
    
    if [ -n "$CONV_DATA" ]; then
        CURRENT_STATUS=$(echo "$CONV_DATA" | cut -f1)
        CURRENT_STATE=$(echo "$CONV_DATA" | cut -f2)
        UPDATED_AT=$(echo "$CONV_DATA" | cut -f3)
        CONV_EXISTS="true"
    else
        CONV_EXISTS="false"
        CURRENT_STATUS="0"
        CURRENT_STATE="0"
        UPDATED_AT="0"
    fi
else
    CONV_EXISTS="false"
    CURRENT_STATUS="0"
    CURRENT_STATE="0"
    UPDATED_AT="0"
fi

echo "Status: $CURRENT_STATUS (Initial: $INITIAL_STATUS)"
echo "State: $CURRENT_STATE"
echo "Updated: $UPDATED_AT (Task Start: $TASK_START)"

# Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "conversation_exists": $CONV_EXISTS,
    "initial_status": $INITIAL_STATUS,
    "final_status": $CURRENT_STATUS,
    "conversation_state": $CURRENT_STATE,
    "updated_at_timestamp": $UPDATED_AT,
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="