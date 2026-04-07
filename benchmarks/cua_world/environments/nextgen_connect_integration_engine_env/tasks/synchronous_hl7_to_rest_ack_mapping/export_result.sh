#!/bin/bash
echo "=== Exporting Synchronous HL7-to-REST Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Functional Test: Send HL7 Message and Capture ACK
echo "Running functional test..."
TEST_MRN="MRN$(date +%s)"
TEST_MSG="MSH|^~\\&|HIS|HOSP|MPI|MIE|$(date +%Y%m%d%H%M%S)||ADT^A04|MSG001|P|2.3\rEVN|A04|$(date +%Y%m%d%H%M%S)\rPID|1||$TEST_MRN||Doe^John||19800101|M\rPV1|1|O"

# Send via netcat and capture response (with timeout)
# MLLP wrapping: 0x0B [msg] 0x1C 0x0D
RESPONSE_HEX=$(printf "\x0b${TEST_MSG}\x1c\r" | timeout 5 nc localhost 6661 | xxd -p | tr -d '\n')
RESPONSE_TEXT=$(echo "$RESPONSE_HEX" | xxd -r -p 2>/dev/null || echo "")

echo "Sent MRN: $TEST_MRN"
echo "Received Response: $RESPONSE_TEXT"

# 3. Check Mock Server Log
SERVER_LOG="/tmp/mock_mpi_server.log"
API_RECEIVED="false"
GENERATED_UUID=""

if [ -f "$SERVER_LOG" ]; then
    # Look for the log entry corresponding to our test MRN
    LOG_ENTRY=$(grep "$TEST_MRN" "$SERVER_LOG" | tail -1)
    if [ -n "$LOG_ENTRY" ]; then
        API_RECEIVED="true"
        # Extract the UUID the server returned
        GENERATED_UUID=$(echo "$LOG_ENTRY" | python3 -c "import sys, json; print(json.load(sys.stdin)['response']['mpi_uuid'])" 2>/dev/null)
        echo "Mock API processed MRN. Generated UUID: $GENERATED_UUID"
    fi
else
    echo "Mock server log not found."
fi

# 4. Analyze Channel State
CHANNEL_EXISTS="false"
CHANNEL_STATUS="unknown"
CHANNEL_ID=""
CONFIG_CORRECT="false"

# Find channel
CHANNEL_DATA=$(query_postgres "SELECT id, name FROM channel WHERE LOWER(name) LIKE '%mpi%' OR LOWER(name) LIKE '%facade%';" 2>/dev/null || true)
if [ -n "$CHANNEL_DATA" ]; then
    CHANNEL_EXISTS="true"
    CHANNEL_ID=$(echo "$CHANNEL_DATA" | head -1 | cut -d'|' -f1)
    CHANNEL_NAME=$(echo "$CHANNEL_DATA" | head -1 | cut -d'|' -f2)
    
    # Check status
    STATUS=$(get_channel_status_api "$CHANNEL_ID")
    CHANNEL_STATUS="$STATUS"
    
    # Check "Response" setting (Source Connector responseVariable)
    # Ideally should be "Destination 1" (which maps to 'd1' or similar in XML, typically stored as 'responseVariable')
    CHANNEL_XML=$(query_postgres "SELECT channel FROM channel WHERE id='$CHANNEL_ID';" 2>/dev/null || true)
    
    # Simple check for HTTP sender and port 6661
    if echo "$CHANNEL_XML" | grep -q "6661" && echo "$CHANNEL_XML" | grep -qi "HttpDispatcherProperties"; then
        CONFIG_CORRECT="true"
    fi
fi

# 5. Export JSON
cat > /tmp/task_result.json << EOF
{
    "channel_exists": $CHANNEL_EXISTS,
    "channel_name": "$CHANNEL_NAME",
    "channel_status": "$CHANNEL_STATUS",
    "api_received_request": $API_RECEIVED,
    "test_mrn": "$TEST_MRN",
    "generated_uuid": "$GENERATED_UUID",
    "raw_ack_response": "$(echo "$RESPONSE_TEXT" | sed 's/"/\\"/g' | sed ':a;N;$!ba;s/\n/\\n/g')",
    "config_looks_correct": $CONFIG_CORRECT,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Permissions
chmod 666 /tmp/task_result.json

echo "Export complete."
cat /tmp/task_result.json