#!/bin/bash
echo "=== Exporting HL7 ACK/NACK Validation Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check Channel Existence & Config via DB
echo "Checking channel configuration..."
CHANNEL_QUERY="SELECT id, name, channel FROM channel WHERE name = 'ADT_Inbound_Validator';"
CHANNEL_DATA=$(query_postgres "$CHANNEL_QUERY")

CHANNEL_EXISTS="false"
CHANNEL_ID=""
CHANNEL_XML=""
LISTENING_PORT=""
SOURCE_TYPE=""

if [ -n "$CHANNEL_DATA" ]; then
    CHANNEL_EXISTS="true"
    CHANNEL_ID=$(echo "$CHANNEL_DATA" | cut -d'|' -f1)
    # Extract XML (everything after the second pipe)
    CHANNEL_XML=$(echo "$CHANNEL_DATA" | cut -d'|' -f3-)
    
    # Extract port
    LISTENING_PORT=$(echo "$CHANNEL_XML" | python3 -c "import sys, re; print(re.search(r'<port>(\d+)</port>', sys.stdin.read()).group(1))" 2>/dev/null || echo "")
    
    # Check source type
    if echo "$CHANNEL_XML" | grep -q "TcpReceiverProperties"; then
        SOURCE_TYPE="TCP Listener"
    fi
fi

# 2. Check Channel Status (via API)
CHANNEL_STATUS="STOPPED"
if [ -n "$CHANNEL_ID" ]; then
    API_STATUS=$(get_channel_status_api "$CHANNEL_ID")
    if [ -n "$API_STATUS" ]; then
        CHANNEL_STATUS="$API_STATUS"
    fi
fi

# 3. Check File Output
OUTPUT_FILES_COUNT=$(ls /home/ga/hl7_outbound/ 2>/dev/null | wc -l)
LAST_FILE_TIME=0
if [ "$OUTPUT_FILES_COUNT" -gt 0 ]; then
    LAST_FILE=$(ls -t /home/ga/hl7_outbound/ | head -1)
    LAST_FILE_TIME=$(stat -c %Y "/home/ga/hl7_outbound/$LAST_FILE" 2>/dev/null || echo "0")
fi

# 4. Check for Validation Logic in XML (Heuristic)
# Look for conditional logic checking PID.3 or PID.5 and setting 'AE' or response status
VALIDATION_LOGIC_DETECTED="false"
if [ -n "$CHANNEL_XML" ]; then
    # Check for Javascript or Rule Builder referencing PID
    if echo "$CHANNEL_XML" | grep -iE "PID.*3|PID.*5|msg\['PID'\]" | grep -iE "AE|Application Error|responseStatus|MSA" > /dev/null; then
        VALIDATION_LOGIC_DETECTED="true"
    fi
fi

# Create JSON result
JSON_CONTENT=$(cat <<EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "channel_exists": $CHANNEL_EXISTS,
    "channel_id": "$CHANNEL_ID",
    "channel_status": "$CHANNEL_STATUS",
    "listening_port": "$LISTENING_PORT",
    "source_type": "$SOURCE_TYPE",
    "output_file_count": $OUTPUT_FILES_COUNT,
    "last_output_time": $LAST_FILE_TIME,
    "validation_logic_detected": $VALIDATION_LOGIC_DETECTED
}
EOF
)

write_result_json "/tmp/task_result.json" "$JSON_CONTENT"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="