#!/bin/bash
echo "=== Exporting HL7 ADT to CSV Export Results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_CHANNEL_COUNT=$(cat /tmp/initial_channel_count.txt 2>/dev/null || echo "0")
OUTPUT_FILE="/home/ga/output/patient_demographics.csv"
TEST_PORT=6661

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check Channel State via API
CURRENT_CHANNEL_COUNT=$(get_channel_count)
CHANNEL_ID=$(get_channel_id "ADT_CSV_Export")
CHANNEL_STATUS="UNKNOWN"
LISTENER_PORT_CHECK="FALSE"

if [ -n "$CHANNEL_ID" ]; then
    CHANNEL_STATUS=$(get_channel_status_api "$CHANNEL_ID")
    
    # Verify port configuration from XML
    CHANNEL_XML=$(query_postgres "SELECT channel FROM channel WHERE id='$CHANNEL_ID';" 2>/dev/null || true)
    if echo "$CHANNEL_XML" | grep -q "<port>6661</port>"; then
        LISTENER_PORT_CHECK="TRUE"
    fi
fi

# 2. Run Functional Test: Send HL7 Messages
TEST_RESULT_1="FAILED"
TEST_RESULT_2="FAILED"
TEST_RESULT_3="FAILED"
MESSAGES_SENT=0

if [ "$CHANNEL_STATUS" == "STARTED" ] && [ "$LISTENER_PORT_CHECK" == "TRUE" ]; then
    echo "Channel is running on port 6661. Sending test messages..."
    
    # Wait a moment for channel to be fully ready
    sleep 2
    
    # Message 1
    MSG1="MSH|^~\\&|EPIC|HOSPITAL1|BILLING|LEGACY|20240115120000||ADT^A01|MSG001|P|2.3\rEVN|A01|20240115120000\rPID|1||MRN10045^^^HOSPITAL1^MR||JOHNSON^ROBERT^A||19650312|M||W|456 OAK AVE^^SPRINGFIELD^IL^62704||2175551234|||S|123456789\rPV1|1|I|ICU^101^A|E|||1234^SMITH^JAMES|||MED||||7|||1234^SMITH^JAMES|I|||||||||||||||||||HOSPITAL1|||20240115120000\r"
    printf '\x0b%b\x1c\x0d' "$MSG1" | nc -w 2 localhost 6661
    if [ $? -eq 0 ]; then MESSAGES_SENT=$((MESSAGES_SENT+1)); fi
    sleep 1

    # Message 2
    MSG2="MSH|^~\\&|EPIC|HOSPITAL1|BILLING|LEGACY|20240115130000||ADT^A01|MSG002|P|2.3\rEVN|A01|20240115130000\rPID|1||MRN20078^^^HOSPITAL1^MR||MARTINEZ^MARIA^L||19780925|F||H|789 PINE ST^^CHICAGO^IL^60601||3125559876|||M|987654321\rPV1|1|I|MED^205^B|U|||5678^DOE^JANE|||SUR||||7|||5678^DOE^JANE|I|||||||||||||||||||HOSPITAL1|||20240115130000\r"
    printf '\x0b%b\x1c\x0d' "$MSG2" | nc -w 2 localhost 6661
    if [ $? -eq 0 ]; then MESSAGES_SENT=$((MESSAGES_SENT+1)); fi
    sleep 1
    
    # Message 3
    MSG3="MSH|^~\\&|EPIC|HOSPITAL1|BILLING|LEGACY|20240115140000||ADT^A01|MSG003|P|2.3\rEVN|A01|20240115140000\rPID|1||MRN30112^^^HOSPITAL1^MR||CHEN^WILLIAM^T||19900508|M||A|321 MAPLE DR^^PEORIA^IL^61602||3095554567|||S|456789123\rPV1|1|I|SURG^302^A|E|||9012^BROWN^LISA|||ORT||||7|||9012^BROWN^LISA|I|||||||||||||||||||HOSPITAL1|||20240115140000\r"
    printf '\x0b%b\x1c\x0d' "$MSG3" | nc -w 2 localhost 6661
    if [ $? -eq 0 ]; then MESSAGES_SENT=$((MESSAGES_SENT+1)); fi
    sleep 2
else
    echo "Channel not started or port wrong. Skipping test messages."
fi

# 3. Verify Output File
FILE_EXISTS="false"
FILE_CONTENT=""
FILE_TIMESTAMP=0
HEADER_FOUND="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_CONTENT=$(cat "$OUTPUT_FILE" | head -n 10) # Capture first 10 lines
    FILE_TIMESTAMP=$(stat -c %Y "$OUTPUT_FILE")
    
    # Check Header
    if grep -q "PatientID,LastName,FirstName,DOB,Gender,Street,City,State,Zip,Phone,SSN" "$OUTPUT_FILE"; then
        HEADER_FOUND="true"
    fi
fi

# 4. Generate Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "initial_channel_count": $INITIAL_CHANNEL_COUNT,
    "current_channel_count": $CURRENT_CHANNEL_COUNT,
    "channel_id": "$CHANNEL_ID",
    "channel_status": "$CHANNEL_STATUS",
    "listener_port_check": "$LISTENER_PORT_CHECK",
    "messages_sent": $MESSAGES_SENT,
    "output_file_exists": $FILE_EXISTS,
    "output_file_timestamp": $FILE_TIMESTAMP,
    "header_found": $HEADER_FOUND,
    "file_content_preview": $(echo "$FILE_CONTENT" | jq -R -s '.')
}
EOF

write_result_json "/tmp/task_result.json" "$(cat $TEMP_JSON)"
rm "$TEMP_JSON"

echo "=== Export Complete ==="
cat /tmp/task_result.json