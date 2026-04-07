#!/bin/bash
echo "=== Exporting JSON to HL7 REST Gateway Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check Channel Existence
CHANNEL_NAME="JSON_to_HL7_Gateway"
CHANNEL_ID=$(get_channel_id "$CHANNEL_NAME")
CHANNEL_EXISTS="false"
CHANNEL_STATUS="UNKNOWN"
PORT_OPEN="false"

if [ -n "$CHANNEL_ID" ]; then
    CHANNEL_EXISTS="true"
    CHANNEL_STATUS=$(get_channel_status_api "$CHANNEL_ID")
else
    # Fallback search if name isn't exact
    CHANNEL_ID=$(query_postgres "SELECT id FROM channel WHERE LOWER(name) LIKE '%json%' AND LOWER(name) LIKE '%hl7%' LIMIT 1;")
    if [ -n "$CHANNEL_ID" ]; then
        CHANNEL_EXISTS="true"
        CHANNEL_STATUS=$(get_channel_status_api "$CHANNEL_ID")
        CHANNEL_NAME=$(query_postgres "SELECT name FROM channel WHERE id='$CHANNEL_ID';")
    fi
fi

# 2. Check if port 6661 is listening
if netstat -tuln | grep -q ":6661 "; then
    PORT_OPEN="true"
fi

# 3. Functional Verification: Send Verification Payload
# We use a distinct payload from the sample to ensure dynamic mapping
echo "Running functional verification test..."
VERIFY_MRN="MRN-TEST-999"
VERIFY_VISIT="V-TEST-999"

# Clean output dir before test to identify our specific file
docker exec nextgen-connect rm -f /tmp/hl7_output/*_verify.hl7 2>/dev/null || true

# Verification Payload
TEST_PAYLOAD='{
  "patient": {
    "mrn": "MRN-TEST-999",
    "lastName": "Verify",
    "firstName": "Agent",
    "dateOfBirth": "1990-01-01",
    "sex": "M",
    "address": { "street": "123 Test St", "city": "TestCity", "state": "TS", "zip": "12345" },
    "phone": "555-0000"
  },
  "visit": {
    "visitNumber": "V-TEST-999",
    "patientClass": "O",
    "attendingDoctor": { "id": "DOC1", "lastName": "Doc", "firstName": "Test" }
  }
}'

HTTP_RESPONSE_CODE="000"
TEST_PASSED="false"
OUTPUT_CONTENT=""

if [ "$PORT_OPEN" = "true" ]; then
    # Send request
    HTTP_RESPONSE_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: application/json" -d "$TEST_PAYLOAD" http://localhost:6661)
    
    # Wait for processing
    sleep 3
    
    # Check for output file
    # We look for the most recently modified file in the output directory
    LATEST_FILE=$(docker exec nextgen-connect ls -t /tmp/hl7_output/ | head -n 1)
    
    if [ -n "$LATEST_FILE" ]; then
        # Read content
        OUTPUT_CONTENT=$(docker exec nextgen-connect cat "/tmp/hl7_output/$LATEST_FILE")
        TEST_PASSED="true"
    fi
fi

# 4. Gather Channel Statistics
STATS_RECEIVED=0
STATS_SENT=0
if [ -n "$CHANNEL_ID" ]; then
    STATS=$(get_channel_stats_api "$CHANNEL_ID")
    if [ -n "$STATS" ]; then
        STATS_RECEIVED=$(echo "$STATS" | python3 -c "import sys, json; print(json.load(sys.stdin).get('channelStatistics', {}).get('received', 0))" 2>/dev/null || echo "0")
        STATS_SENT=$(echo "$STATS" | python3 -c "import sys, json; print(json.load(sys.stdin).get('channelStatistics', {}).get('sent', 0))" 2>/dev/null || echo "0")
    fi
fi

# 5. Create Result JSON
# Escaping output content for JSON safety
SAFE_OUTPUT_CONTENT=$(echo "$OUTPUT_CONTENT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')

cat > /tmp/task_result.json <<EOF
{
    "channel_exists": $CHANNEL_EXISTS,
    "channel_name": "$CHANNEL_NAME",
    "channel_id": "$CHANNEL_ID",
    "channel_status": "$CHANNEL_STATUS",
    "port_6661_open": $PORT_OPEN,
    "http_response_code": "$HTTP_RESPONSE_CODE",
    "functional_test_file_created": $TEST_PASSED,
    "output_content": $SAFE_OUTPUT_CONTENT,
    "stats_received": $STATS_RECEIVED,
    "stats_sent": $STATS_SENT,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Set permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json