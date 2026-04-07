#!/bin/bash
echo "=== Exporting normalize_audit_ack results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if audit file exists
AUDIT_FILE="/home/ga/ack_audit.log"
AUDIT_EXISTS="false"
AUDIT_CONTENT=""
AUDIT_SIZE_BYTES=0

if [ -f "$AUDIT_FILE" ]; then
    AUDIT_EXISTS="true"
    AUDIT_SIZE_BYTES=$(stat -c%s "$AUDIT_FILE" 2>/dev/null || echo "0")
    # Read last few lines (base64 encoded to avoid JSON issues)
    AUDIT_CONTENT=$(tail -n 5 "$AUDIT_FILE" | base64 -w 0)
fi

# Check if channel exists and is deployed
CHANNEL_ID=$(get_channel_id "LIS_ACK_Normalizer")
CHANNEL_DEPLOYED="false"

if [ -n "$CHANNEL_ID" ]; then
    STATUS=$(get_channel_status_api "$CHANNEL_ID")
    if [ "$STATUS" = "STARTED" ] || [ "$STATUS" = "DEPLOYED" ]; then
        CHANNEL_DEPLOYED="true"
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "audit_file_exists": $AUDIT_EXISTS,
    "audit_file_size": $AUDIT_SIZE_BYTES,
    "audit_content_b64": "$AUDIT_CONTENT",
    "channel_deployed": $CHANNEL_DEPLOYED,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result with permissions
rm -f /tmp/task_result.json 2>/dev/null
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="