#!/bin/bash
echo "=== Exporting process_hl7_message task result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Initialize tracking variables
MESSAGE_PROCESSED="false"
CHANNEL_COUNT=0
RECEIVED_COUNT=0
SENT_COUNT=0
INITIAL_RECEIVED=0
NEW_MESSAGES=0
EVIDENCE_FOUND=""

# Get initial received count from setup
INITIAL_RECEIVED=$(cat /tmp/initial_received_count 2>/dev/null || echo "0")

# Get channel count (channels must exist to process messages)
CHANNEL_COUNT=$(query_postgres "SELECT COUNT(*) FROM channel;" 2>/dev/null || echo "0")
echo "Channel count: $CHANNEL_COUNT"

# Check if any channels exist
if [ "$CHANNEL_COUNT" -gt 0 ]; then
    echo "Channels exist, checking for message processing evidence..."

    # Get channel ID
    CHANNEL_ID=$(query_postgres "SELECT id FROM channel LIMIT 1;" 2>/dev/null || true)
    CHANNEL_NAME=$(query_postgres "SELECT name FROM channel LIMIT 1;" 2>/dev/null || true)
    echo "Channel: $CHANNEL_NAME (ID: $CHANNEL_ID)"

    # Method 1: Check REST API statistics (most reliable)
    if [ -n "$CHANNEL_ID" ]; then
        STATS_JSON=$(curl -sk -u admin:admin \
            -H "X-Requested-With: OpenAPI" \
            -H "Accept: application/json" \
            "https://localhost:8443/api/channels/$CHANNEL_ID/statistics" 2>/dev/null)

        if [ -n "$STATS_JSON" ]; then
            RECEIVED_COUNT=$(echo "$STATS_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('channelStatistics',{}).get('received',0))" 2>/dev/null || echo "0")
            SENT_COUNT=$(echo "$STATS_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('channelStatistics',{}).get('sent',0))" 2>/dev/null || echo "0")

            # Delta-based check: compare to initial count
            NEW_MESSAGES=$((RECEIVED_COUNT - INITIAL_RECEIVED))
            echo "API Statistics - Received: $RECEIVED_COUNT (initial: $INITIAL_RECEIVED, new: $NEW_MESSAGES), Sent: $SENT_COUNT"

            if [ "$NEW_MESSAGES" -gt 0 ] 2>/dev/null; then
                MESSAGE_PROCESSED="true"
                EVIDENCE_FOUND="api_statistics"
                echo "New messages confirmed received via API statistics"
            fi
        fi
    fi

    # Method 2: Check d_m1 table (NextGen creates d_m1, d_m2 etc for message metadata)
    D_M1_COUNT=$(query_postgres "SELECT COUNT(*) FROM d_m1;" 2>/dev/null || echo "0")
    if [ "$D_M1_COUNT" -gt 0 ] 2>/dev/null; then
        MESSAGE_PROCESSED="true"
        EVIDENCE_FOUND="${EVIDENCE_FOUND:+$EVIDENCE_FOUND,}message_tables"
        echo "Found $D_M1_COUNT message(s) in d_m1 table"
    fi

    # Method 3: Check for output files inside Docker container
    OUTPUT_COUNT=$(docker exec nextgen-connect ls /tmp/hl7_output/ 2>/dev/null | wc -l || echo "0")
    if [ "$OUTPUT_COUNT" -gt 0 ] 2>/dev/null; then
        MESSAGE_PROCESSED="true"
        EVIDENCE_FOUND="${EVIDENCE_FOUND:+$EVIDENCE_FOUND,}output_files"
        echo "Found $OUTPUT_COUNT output file(s) in docker container"
    fi
else
    echo "No channels exist - cannot process messages without channels"
fi

# Create JSON result
JSON_CONTENT=$(cat <<EOF
{
    "channel_count": $CHANNEL_COUNT,
    "message_processed": "$MESSAGE_PROCESSED",
    "received_count": $RECEIVED_COUNT,
    "sent_count": $SENT_COUNT,
    "initial_received": $INITIAL_RECEIVED,
    "new_messages": $NEW_MESSAGES,
    "evidence_found": "$EVIDENCE_FOUND",
    "timestamp": "$(date -Iseconds)"
}
EOF
)

# Write result with permission handling
write_result_json "/tmp/process_hl7_message_result.json" "$JSON_CONTENT"

echo "Result saved to /tmp/process_hl7_message_result.json"
cat /tmp/process_hl7_message_result.json
echo "=== Export complete ==="
