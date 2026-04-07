#!/bin/bash
echo "=== Exporting HTTP Sender Patient Notification Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check Channel Configuration via DB
CHANNEL_EXISTS="false"
CHANNEL_ID=""
CHANNEL_NAME=""
SOURCE_PORT=""
DEST_URL=""
DEST_TYPE=""
TRANSFORMER_SCRIPT=""

# Find channel by name
CHANNEL_DATA=$(query_postgres "SELECT id, name, channel FROM channel WHERE LOWER(name) LIKE '%patient%notification%';" 2>/dev/null || true)

if [ -n "$CHANNEL_DATA" ]; then
    CHANNEL_EXISTS="true"
    # Extract ID (first column before pipe)
    CHANNEL_ID=$(echo "$CHANNEL_DATA" | cut -d'|' -f1)
    CHANNEL_NAME=$(echo "$CHANNEL_DATA" | cut -d'|' -f2)
    # Extract full XML (everything after the second pipe)
    # Note: The psql output format might be tricky with pipes in XML. 
    # Safer to query XML separately once we have ID.
fi

if [ "$CHANNEL_EXISTS" = "true" ]; then
    echo "Found channel: $CHANNEL_NAME ($CHANNEL_ID)"
    
    # Get XML config safely
    CHANNEL_XML=$(query_postgres "SELECT channel FROM channel WHERE id='$CHANNEL_ID';" 2>/dev/null)
    
    # Check Source Port (TCP Listener)
    SOURCE_PORT=$(echo "$CHANNEL_XML" | python3 -c "import sys, re; m = re.search(r'<listenerConnectorProperties>.*?<port>(\d+)</port>', sys.stdin.read(), re.DOTALL); print(m.group(1) if m else '')" 2>/dev/null)
    
    # Check Destination Type and URL
    # Look for HttpDispatcherProperties
    if echo "$CHANNEL_XML" | grep -q "HttpDispatcherProperties"; then
        DEST_TYPE="HTTP Sender"
        # Extract URL
        DEST_URL=$(echo "$CHANNEL_XML" | python3 -c "import sys, re; m = re.search(r'<url>(.*?)</url>', sys.stdin.read(), re.DOTALL); print(m.group(1) if m else '')" 2>/dev/null)
    fi
    
    # Check for Transformer Script (looking for JSON fields)
    TRANSFORMER_SCRIPT=$(echo "$CHANNEL_XML" | python3 -c "import sys, re; m = re.search(r'<script>(.*?)</script>', sys.stdin.read(), re.DOTALL); print(m.group(1) if m else '')" 2>/dev/null)
    
    # Check Deployment Status
    STATUS_JSON=$(curl -sk -u admin:admin -H "X-Requested-With: OpenAPI" "https://localhost:8443/api/channels/$CHANNEL_ID/status" 2>/dev/null)
    CHANNEL_STATE=$(echo "$STATUS_JSON" | python3 -c "import sys, json; print(json.load(sys.stdin).get('dashboardStatus', {}).get('state', 'UNKNOWN'))" 2>/dev/null)
else
    echo "Channel not found."
fi

# 2. Check Webhook Logs
WEBHOOK_RECEIVED="false"
PAYLOAD_CORRECT="false"
RECEIVED_PAYLOAD=""

LOG_FILE="/tmp/webhook_data/payloads.log"
if [ -f "$LOG_FILE" ]; then
    # Read the last line
    LAST_LOG=$(tail -n 1 "$LOG_FILE")
    if [ -n "$LAST_LOG" ]; then
        WEBHOOK_RECEIVED="true"
        # Extract body from log JSON
        RECEIVED_PAYLOAD=$(echo "$LAST_LOG" | python3 -c "import sys, json; print(json.load(sys.stdin).get('body', ''))" 2>/dev/null)
    fi
fi

# 3. Create Result JSON
# Use python to construct JSON to avoid escaping issues
python3 -c "
import json
import os

result = {
    'channel_exists': '$CHANNEL_EXISTS' == 'true',
    'channel_name': '$CHANNEL_NAME',
    'channel_id': '$CHANNEL_ID',
    'source_port': '$SOURCE_PORT',
    'dest_type': '$DEST_TYPE',
    'dest_url': '$DEST_URL',
    'channel_state': '$CHANNEL_STATE',
    'webhook_received': '$WEBHOOK_RECEIVED' == 'true',
    'received_payload': '''$RECEIVED_PAYLOAD''',
    'transformer_snippet': '''${TRANSFORMER_SCRIPT:0:200}'''
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Set permissions
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="