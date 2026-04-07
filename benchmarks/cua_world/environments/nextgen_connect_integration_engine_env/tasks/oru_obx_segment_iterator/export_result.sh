#!/bin/bash
echo "=== Exporting ORU OBX Segment Iterator Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Initialize variables
CHANNEL_FOUND="false"
CHANNEL_ID=""
CHANNEL_NAME=""
CHANNEL_STATUS="unknown"
TEST_SENT="false"
OUTPUT_EXISTS="false"
OUTPUT_CONTENT=""
LINE_COUNT=0
APPEND_TEST_PASSED="false"

# 1. Find the channel
echo "Searching for channel..."
CHANNEL_DATA=$(query_postgres "SELECT id, name FROM channel WHERE LOWER(name) LIKE '%lab_results_obx_extractor%';" 2>/dev/null || true)

if [ -z "$CHANNEL_DATA" ]; then
    # Try fuzzy match
    CHANNEL_DATA=$(query_postgres "SELECT id, name FROM channel WHERE LOWER(name) LIKE '%obx%';" 2>/dev/null || true)
fi

if [ -n "$CHANNEL_DATA" ]; then
    CHANNEL_FOUND="true"
    CHANNEL_ID=$(echo "$CHANNEL_DATA" | head -1 | cut -d'|' -f1)
    CHANNEL_NAME=$(echo "$CHANNEL_DATA" | head -1 | cut -d'|' -f2)
    echo "Found channel: $CHANNEL_NAME ($CHANNEL_ID)"
    
    # Check status
    API_STATUS=$(get_channel_status_api "$CHANNEL_ID" 2>/dev/null)
    if [ -n "$API_STATUS" ]; then
        CHANNEL_STATUS="$API_STATUS"
    fi
    echo "Channel Status: $CHANNEL_STATUS"
fi

# 2. Perform Functional Test (Send HL7 Message)
if [ "$CHANNEL_FOUND" = "true" ] && [ "$CHANNEL_STATUS" = "STARTED" ]; then
    echo "Channel is started. Sending test message..."
    
    # Test Message 1 (8 OBX segments)
    HL7_MSG=$(printf 'MSH|^~\\&|LAB_SYSTEM|MEMORIAL_HOSP|EHR_SYSTEM|MEMORIAL_HOSP|20240115103000||ORU^R01^ORU_R01|MSG00001|P|2.5.1|||AL|NE\rPID|1||MRN123456^^^MEMORIAL_HOSP^MR||DOE^JANE^M||19780422|F|||456 OAK AVE^^SPRINGFIELD^IL^62704||2175551234\rPV1|1|O|LAB^^^^||||1234^SMITH^ROBERT^J^MD\rORC|RE|ORD789|LAB456||CM\rOBR|1|ORD789|LAB456|58410-2^CBC WITH DIFFERENTIAL^LN|||20240115090000|||||||20240115093000||1234^SMITH^ROBERT^J^MD||||||20240115103000|||F\rOBX|1|NM|6690-2^WBC^LN||7.5|10*3/uL|4.5-11.0|N|||F\rOBX|2|NM|789-8^RBC^LN||4.82|10*6/uL|4.00-5.50|N|||F\rOBX|3|NM|718-7^HGB^LN||14.2|g/dL|12.0-16.0|N|||F\rOBX|4|NM|4544-3^HCT^LN||42.1|%%|36.0-46.0|N|||F\rOBX|5|NM|787-2^MCV^LN||87.3|fL|80.0-100.0|N|||F\rOBX|6|NM|785-6^MCH^LN||29.5|pg|27.0-33.0|N|||F\rOBX|7|NM|786-4^MCHC^LN||33.7|g/dL|32.0-36.0|N|||F\rOBX|8|NM|777-3^PLT^LN||245|10*3/uL|150-400|N|||F\r')
    
    # Send via MLLP
    printf "\x0b${HL7_MSG}\x1c\x0d" | nc -w 5 localhost 6661 2>/dev/null
    TEST_SENT="true"
    
    # Wait for processing
    sleep 5
    
    # Check output file
    echo "Checking for output file..."
    DOCKER_CONTENT=$(docker exec nextgen-connect cat /tmp/lab_results/obx_results.txt 2>/dev/null || true)
    
    if [ -n "$DOCKER_CONTENT" ]; then
        OUTPUT_EXISTS="true"
        OUTPUT_CONTENT="$DOCKER_CONTENT"
        LINE_COUNT=$(echo "$OUTPUT_CONTENT" | grep -c '[^[:space:]]' || echo "0")
        echo "Output found: $LINE_COUNT lines"
        
        # 3. Test Append Mode
        echo "Testing append mode..."
        HL7_MSG2=$(printf 'MSH|^~\\&|LAB|HOSP|EHR|HOSP|20240115110000||ORU^R01^ORU_R01|MSG002|P|2.5.1\rPID|1||MRN2||SMITH\rOBR|1|||PNL|||||||||||||||||F\rOBX|1|NM|TEST1||100|u|||N\r')
        printf "\x0b${HL7_MSG2}\x1c\x0d" | nc -w 5 localhost 6661 2>/dev/null
        sleep 5
        
        NEW_CONTENT=$(docker exec nextgen-connect cat /tmp/lab_results/obx_results.txt 2>/dev/null || true)
        NEW_LINE_COUNT=$(echo "$NEW_CONTENT" | grep -c '[^[:space:]]' || echo "0")
        
        if [ "$NEW_LINE_COUNT" -gt "$LINE_COUNT" ]; then
            APPEND_TEST_PASSED="true"
            echo "Append confirmed ($LINE_COUNT -> $NEW_LINE_COUNT lines)"
            # Update content to full content for verification
            OUTPUT_CONTENT="$NEW_CONTENT"
            LINE_COUNT="$NEW_LINE_COUNT"
        else
            echo "Append failed ($LINE_COUNT -> $NEW_LINE_COUNT lines)"
        fi
    else
        echo "No output file found inside container."
    fi
else
    echo "Channel not found or not started. Skipping functional test."
fi

# Get initial counts
INITIAL_COUNT=$(cat /tmp/initial_channel_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(get_channel_count)

# Escape content for JSON
OUTPUT_CONTENT_JSON=$(echo "$OUTPUT_CONTENT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')

# Create JSON result
JSON_FILE="/tmp/task_result.json"
cat > "$JSON_FILE" << EOF
{
    "channel_found": $CHANNEL_FOUND,
    "channel_id": "$CHANNEL_ID",
    "channel_name": "$CHANNEL_NAME",
    "channel_status": "$CHANNEL_STATUS",
    "initial_count": $INITIAL_COUNT,
    "current_count": $CURRENT_COUNT,
    "test_sent": $TEST_SENT,
    "output_exists": $OUTPUT_EXISTS,
    "output_content": $OUTPUT_CONTENT_JSON,
    "line_count": $LINE_COUNT,
    "append_test_passed": $APPEND_TEST_PASSED,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Ensure permissions
chmod 666 "$JSON_FILE" 2>/dev/null || true

echo "Result saved to $JSON_FILE"
cat "$JSON_FILE"
echo "=== Export complete ==="