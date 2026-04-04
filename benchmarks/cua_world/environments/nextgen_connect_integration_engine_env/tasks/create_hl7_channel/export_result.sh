#!/bin/bash
echo "=== Exporting create_hl7_channel task result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Get initial and current channel counts
INITIAL=$(cat /tmp/initial_channel_count 2>/dev/null || echo "0")
CURRENT=$(get_channel_count)

echo "Initial channel count: $INITIAL"
echo "Current channel count: $CURRENT"

# Check if the specific channel exists in database
CHANNEL_EXISTS="false"
CHANNEL_ID=""
CHANNEL_NAME=""
CHANNEL_STATUS="unknown"
SOURCE_TYPE=""
LISTEN_PORT=""
DEST_TYPE=""

# Query for channels with "Patient" and "Admission" in the name
CHANNEL_DATA=$(query_postgres "SELECT id, name FROM channel WHERE LOWER(name) LIKE '%patient%' AND LOWER(name) LIKE '%admission%';" 2>/dev/null || true)

if [ -n "$CHANNEL_DATA" ]; then
    CHANNEL_EXISTS="true"
    CHANNEL_ID=$(echo "$CHANNEL_DATA" | head -1 | cut -d'|' -f1)
    CHANNEL_NAME=$(echo "$CHANNEL_DATA" | head -1 | cut -d'|' -f2)
    echo "Found channel: $CHANNEL_NAME (ID: $CHANNEL_ID)"
fi

# If exact match not found, try broader search
if [ "$CHANNEL_EXISTS" = "false" ]; then
    CHANNEL_DATA2=$(query_postgres "SELECT id, name FROM channel WHERE LOWER(name) LIKE '%patient%' OR LOWER(name) LIKE '%admission%' ORDER BY id DESC LIMIT 1;" 2>/dev/null || true)
    if [ -n "$CHANNEL_DATA2" ]; then
        CHANNEL_EXISTS="true"
        CHANNEL_ID=$(echo "$CHANNEL_DATA2" | head -1 | cut -d'|' -f1)
        CHANNEL_NAME=$(echo "$CHANNEL_DATA2" | head -1 | cut -d'|' -f2)
        echo "Found channel (partial match): $CHANNEL_NAME (ID: $CHANNEL_ID)"
    fi
fi

# If still not found, check if ANY new channel was created
if [ "$CHANNEL_EXISTS" = "false" ] && [ "$CURRENT" -gt "$INITIAL" ]; then
    echo "New channel detected, fetching latest..."
    LATEST_DATA=$(query_postgres "SELECT id, name FROM channel ORDER BY revision DESC LIMIT 1;" 2>/dev/null || true)
    if [ -n "$LATEST_DATA" ]; then
        CHANNEL_EXISTS="true"
        CHANNEL_ID=$(echo "$LATEST_DATA" | head -1 | cut -d'|' -f1)
        CHANNEL_NAME=$(echo "$LATEST_DATA" | head -1 | cut -d'|' -f2)
        echo "Found latest channel: $CHANNEL_NAME (ID: $CHANNEL_ID)"
    fi
fi

# Extract channel configuration details from XML
if [ -n "$CHANNEL_ID" ]; then
    CHANNEL_XML=$(query_postgres "SELECT channel FROM channel WHERE id='$CHANNEL_ID';" 2>/dev/null || true)

    # Check source connector type
    if echo "$CHANNEL_XML" | grep -qi "TcpReceiverProperties\|TCP Listener"; then
        SOURCE_TYPE="TCP Listener"
    elif echo "$CHANNEL_XML" | grep -qi "HttpReceiverProperties\|HTTP Listener"; then
        SOURCE_TYPE="HTTP Listener"
    fi

    # Extract listening port
    LISTEN_PORT=$(echo "$CHANNEL_XML" | python3 -c "
import sys, re
xml = sys.stdin.read()
m = re.search(r'<port>(\d+)</port>', xml)
if m: print(m.group(1))
else: print('')
" 2>/dev/null || true)

    # Check destination connector type
    if echo "$CHANNEL_XML" | grep -qi "FileDispatcherProperties\|File Writer"; then
        DEST_TYPE="File Writer"
    elif echo "$CHANNEL_XML" | grep -qi "DatabaseDispatcher\|Database Writer"; then
        DEST_TYPE="Database Writer"
    elif echo "$CHANNEL_XML" | grep -qi "Channel Writer"; then
        DEST_TYPE="Channel Writer"
    fi

    # Check deployment status via d_channels table
    DEPLOYED_CHECK=$(query_postgres "SELECT COUNT(*) FROM d_channels WHERE channel_id='$CHANNEL_ID';" 2>/dev/null || echo "0")
    if [ "$DEPLOYED_CHECK" -gt 0 ] 2>/dev/null; then
        CHANNEL_STATUS="deployed"
        echo "Channel is deployed (found in d_channels)"
    fi

    # Also try API status check
    API_STATUS=$(get_channel_status_api "$CHANNEL_ID" 2>/dev/null || echo "UNKNOWN")
    if [ "$API_STATUS" != "UNKNOWN" ] && [ -n "$API_STATUS" ]; then
        CHANNEL_STATUS="$API_STATUS"
        echo "Channel API status: $API_STATUS"
    fi
fi

echo "Source type: $SOURCE_TYPE, Port: $LISTEN_PORT, Dest type: $DEST_TYPE"

# Create JSON result
JSON_CONTENT=$(cat <<EOF
{
    "initial_count": $INITIAL,
    "current_count": $CURRENT,
    "channel_exists": $CHANNEL_EXISTS,
    "channel_id": "$CHANNEL_ID",
    "channel_name": "$CHANNEL_NAME",
    "channel_status": "$CHANNEL_STATUS",
    "source_type": "$SOURCE_TYPE",
    "listen_port": "$LISTEN_PORT",
    "dest_type": "$DEST_TYPE",
    "timestamp": "$(date -Iseconds)"
}
EOF
)

# Write result with permission handling
write_result_json "/tmp/create_hl7_channel_result.json" "$JSON_CONTENT"

echo "Result saved to /tmp/create_hl7_channel_result.json"
cat /tmp/create_hl7_channel_result.json
echo "=== Export complete ==="
