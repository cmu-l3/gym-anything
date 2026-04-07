#!/bin/bash
echo "=== Exporting Webhook Notification Integration Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/webhook_notification_start_ts 2>/dev/null || echo "0")
INITIAL_CMDS=$(cat /tmp/webhook_initial_cmds 2>/dev/null || echo "0")
INITIAL_TLM=$(cat /tmp/webhook_initial_tlm 2>/dev/null || echo "0")

# Fetch current COSMOS state
CURRENT_CMDS=$(cosmos_api "get_cmd_cnt" '"INST","COLLECT"' 2>/dev/null | jq -r '.result // 0' 2>/dev/null || echo "$INITIAL_CMDS")
CURRENT_TLM=$(cosmos_tlm "INST HEALTH_STATUS COLLECTS" 2>/dev/null || echo "$INITIAL_TLM")

echo "Commands sent (INST COLLECT): $INITIAL_CMDS -> $CURRENT_CMDS"
echo "Telemetry count (COLLECTS): $INITIAL_TLM -> $CURRENT_TLM"

# Process webhook payload logs
PAYLOADS_JSON="[]"
if [ -f /tmp/webhook_receipts.json ]; then
    # Use jq to slurp the JSON Lines file into a proper JSON array
    PAYLOADS_JSON=$(jq -c -s '.' /tmp/webhook_receipts.json 2>/dev/null || echo "[]")
    NUM_PAYLOADS=$(echo "$PAYLOADS_JSON" | jq 'length' 2>/dev/null || echo "0")
    echo "Found $NUM_PAYLOADS webhook POST payloads logged."
else
    echo "No webhook POST payloads were received by the server."
fi

# Take final screenshot
DISPLAY=:1 import -window root /tmp/webhook_notification_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/webhook_notification_end.png 2>/dev/null || true

# Construct final export result file
cat > /tmp/webhook_notification_result.json << EOF
{
    "task_start": $TASK_START,
    "initial_cmds": $INITIAL_CMDS,
    "current_cmds": $CURRENT_CMDS,
    "initial_tlm": $INITIAL_TLM,
    "current_tlm": $CURRENT_TLM,
    "payloads": $PAYLOADS_JSON
}
EOF

# Kill the mock webhook server to free up port
fuser -k 8080/tcp 2>/dev/null || true

echo "Result JSON written to /tmp/webhook_notification_result.json"
echo "=== Export Complete ==="