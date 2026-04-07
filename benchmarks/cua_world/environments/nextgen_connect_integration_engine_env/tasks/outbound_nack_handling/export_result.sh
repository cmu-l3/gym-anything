#!/bin/bash
echo "=== Exporting outbound_nack_handling task result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Initialize variables
CHANNEL_FOUND="false"
CHANNEL_ID=""
CHANNEL_NAME=""
MESSAGE_STATUS="UNKNOWN"
LOG_EXISTS="false"
LOG_CONTENT_MATCH="false"
LOG_FILE_PATH="/home/ga/lab_rejections.log"
EXPECTED_ERROR="Simulated Patient ID Error"
DESTINATION_CONNECTED="false"

# 1. Find the channel
echo "Searching for Lab_Order_Sender channel..."
CHANNEL_ID=$(get_channel_id "Lab_Order_Sender")

if [ -n "$CHANNEL_ID" ]; then
    CHANNEL_FOUND="true"
    CHANNEL_NAME="Lab_Order_Sender"
    echo "Found Channel ID: $CHANNEL_ID"
    
    # 2. Check Message Status via API
    # We want to see if the LAST message processed has a status of ERROR
    echo "Checking message status..."
    
    # Get stats first to see if any messages were sent
    STATS_JSON=$(curl -sk -u admin:admin \
        -H "X-Requested-With: OpenAPI" \
        -H "Accept: application/json" \
        "https://localhost:8443/api/channels/${CHANNEL_ID}/statistics" 2>/dev/null)
        
    RECEIVED=$(echo "$STATS_JSON" | python3 -c "import sys,json; print(json.load(sys.stdin).get('channelStatistics',{}).get('received',0))" 2>/dev/null || echo "0")
    
    if [ "$RECEIVED" -gt 0 ]; then
        # Fetch the actual messages to check status
        # Note: In NextGen Connect API, we search messages. includeContent=false to save bandwidth
        MESSAGES_JSON=$(curl -sk -u admin:admin \
            -H "X-Requested-With: OpenAPI" \
            -H "Accept: application/json" \
            "https://localhost:8443/api/channels/${CHANNEL_ID}/messages?limit=1&includeContent=false" 2>/dev/null)
            
        # Parse the status of the destination connector
        # Structure: list of messages -> message -> connectorMessages -> values -> status
        MESSAGE_STATUS=$(echo "$MESSAGES_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    msg = data['list'][0]
    # connectorMessages is a map, 0 is usually source, destination IDs start at 1
    # We look for any destination that isn't the source
    statuses = []
    for k, v in msg['connectorMessages'].items():
        if v['metaDataId'] > 0: # Destination
            statuses.append(v['status'])
    
    # If any destination is ERROR, we count it as ERROR for this task
    if 'ERROR' in statuses:
        print('ERROR')
    elif 'SENT' in statuses:
        print('SENT')
    else:
        print(statuses[0] if statuses else 'UNKNOWN')
except Exception as e:
    print('UNKNOWN')
" 2>/dev/null)
    fi
else
    # Try fuzzy search if exact name not found
    echo "Exact name not found, trying fuzzy search..."
    CHANNEL_ID=$(query_postgres "SELECT id FROM channel WHERE LOWER(name) LIKE '%lab%order%' LIMIT 1;" 2>/dev/null)
    if [ -n "$CHANNEL_ID" ]; then
        CHANNEL_FOUND="true"
        CHANNEL_NAME=$(query_postgres "SELECT name FROM channel WHERE id='$CHANNEL_ID';" 2>/dev/null)
        # Repeat status check (simplified)
        MESSAGES_JSON=$(curl -sk -u admin:admin \
            -H "X-Requested-With: OpenAPI" \
            -H "Accept: application/json" \
            "https://localhost:8443/api/channels/${CHANNEL_ID}/messages?limit=1&includeContent=false" 2>/dev/null)
        MESSAGE_STATUS=$(echo "$MESSAGES_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    msg = data['list'][0]
    for k, v in msg['connectorMessages'].items():
        if v['metaDataId'] > 0:
            if v['status'] == 'ERROR':
                print('ERROR'); sys.exit()
    print('SENT')
except: print('UNKNOWN')
" 2>/dev/null)
    fi
fi

echo "Message Status: $MESSAGE_STATUS"

# 3. Check Log File
if [ -f "$LOG_FILE_PATH" ]; then
    LOG_EXISTS="true"
    if grep -q "$EXPECTED_ERROR" "$LOG_FILE_PATH"; then
        LOG_CONTENT_MATCH="true"
    fi
    LOG_SIZE=$(stat -c%s "$LOG_FILE_PATH")
    echo "Log file found ($LOG_SIZE bytes). Content match: $LOG_CONTENT_MATCH"
else
    echo "Log file not found at $LOG_FILE_PATH"
fi

# 4. Check connectivity (Anti-gaming: did they actually talk to the simulator?)
# We can check the simulator logs
if grep -q "Connected by" /tmp/nack_server.log 2>/dev/null; then
    DESTINATION_CONNECTED="true"
fi

# Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "channel_found": $CHANNEL_FOUND,
    "channel_name": "$CHANNEL_NAME",
    "message_status": "$MESSAGE_STATUS",
    "log_exists": $LOG_EXISTS,
    "log_content_match": $LOG_CONTENT_MATCH,
    "destination_connected": $DESTINATION_CONNECTED,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result exported:"
cat /tmp/task_result.json
echo "=== Export complete ==="