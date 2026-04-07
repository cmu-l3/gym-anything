#!/bin/bash
echo "=== Exporting tcp_sender_queue_config task result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Initialize result variables
CHANNEL_FOUND="false"
CHANNEL_ID=""
CHANNEL_XML=""
RECV_STATS=""
DEST_STATS=""
DOWNSTREAM_RECV_COUNT=0

# Find the channel by name "ADT_Message_Relay"
echo "Searching for channel 'ADT_Message_Relay'..."
CHANNEL_LIST_XML=$(api_call "GET" "/channels")

# Parse XML to find channel ID (using simple grep/cut as fallback to python)
# We need to find the ID associated with the name "ADT_Message_Relay"
# The XML structure is <list><channel><id>...</id><name>...</name>...
# Using python for reliable XML parsing
CHANNEL_ID=$(python3 -c "
import sys, xml.etree.ElementTree as ET
try:
    tree = ET.parse(sys.stdin)
    root = tree.getroot()
    for channel in root.findall('channel'):
        name = channel.find('name').text
        if name == 'ADT_Message_Relay':
            print(channel.find('id').text)
            break
except Exception as e:
    pass
" <<< "$CHANNEL_LIST_XML")

if [ -n "$CHANNEL_ID" ]; then
    echo "Found channel ID: $CHANNEL_ID"
    CHANNEL_FOUND="true"
    
    # Get full channel XML configuration
    CHANNEL_XML=$(api_call "GET" "/channels/$CHANNEL_ID")
    
    # Get channel statistics
    STATS_JSON=$(api_call_json "GET" "/channels/$CHANNEL_ID/statistics")
    RECV_STATS=$(echo "$STATS_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('channelStatistics',{}).get('received',0))" 2>/dev/null || echo "0")
    
    # Get status
    STATUS=$(get_channel_status_api "$CHANNEL_ID")
    echo "Channel Status: $STATUS, Messages Received: $RECV_STATS"
    
else
    echo "Channel 'ADT_Message_Relay' not found."
fi

# Get downstream receiver stats
RECV_CHANNEL_ID=$(get_channel_id "Downstream_ADT_Receiver")
if [ -n "$RECV_CHANNEL_ID" ]; then
    DOWN_STATS_JSON=$(api_call_json "GET" "/channels/$RECV_CHANNEL_ID/statistics")
    DOWNSTREAM_RECV_COUNT=$(echo "$DOWN_STATS_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('channelStatistics',{}).get('received',0))" 2>/dev/null || echo "0")
    echo "Downstream received count: $DOWNSTREAM_RECV_COUNT"
fi

# Get initial channel count
INITIAL_COUNT=$(cat /tmp/initial_channel_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(get_channel_count)

# Create JSON result file
# We embed the raw XML of the channel to let the verifier parse detailed settings
cat > /tmp/task_result.json << EOF
{
    "channel_found": $CHANNEL_FOUND,
    "channel_id": "$CHANNEL_ID",
    "channel_status": "$STATUS",
    "received_count": $RECV_STATS,
    "downstream_received_count": $DOWNSTREAM_RECV_COUNT,
    "initial_channel_count": $INITIAL_COUNT,
    "current_channel_count": $CURRENT_COUNT,
    "timestamp": $(date +%s)
}
EOF

# Save channel XML to a separate file for the verifier to read
if [ -n "$CHANNEL_XML" ]; then
    echo "$CHANNEL_XML" > /tmp/channel_config.xml
fi

# Set permissions
chmod 666 /tmp/task_result.json /tmp/channel_config.xml 2>/dev/null || true

echo "=== Export complete ==="