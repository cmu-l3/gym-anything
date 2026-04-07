#!/bin/bash
echo "=== Exporting HL7 Canonical XML Transformer Result ==="

source /workspace/scripts/task_utils.sh

# 1. Basic Task Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_CHANNEL_COUNT=$(cat /tmp/initial_channel_count.txt 2>/dev/null || echo "0")
CURRENT_CHANNEL_COUNT=$(get_channel_count)

# 2. Check Channel Existence & Status
CHANNEL_NAME="Canonical_XML_Transformer"
CHANNEL_ID=$(get_channel_id "$CHANNEL_NAME")
CHANNEL_STATUS="UNKNOWN"
LISTEN_PORT=""
SOURCE_DATATYPE=""
DEST_DATATYPE=""

if [ -n "$CHANNEL_ID" ]; then
    # Get status via API
    CHANNEL_STATUS=$(get_channel_status_api "$CHANNEL_ID")
    
    # Get Config from DB
    CHANNEL_XML=$(query_postgres "SELECT channel FROM channel WHERE id='$CHANNEL_ID'")
    
    # Extract Port
    LISTEN_PORT=$(echo "$CHANNEL_XML" | python3 -c "import sys, re; print(re.search(r'<port>(\d+)</port>', sys.stdin.read()).group(1) if re.search(r'<port>(\d+)</port>', sys.stdin.read()) else '')" 2>/dev/null)
    
    # Extract Datatypes
    SOURCE_DATATYPE=$(echo "$CHANNEL_XML" | grep -o "<inboundDataType>.*</inboundDataType>" | head -1 | sed 's/<[^>]*>//g')
    DEST_DATATYPE=$(echo "$CHANNEL_XML" | grep -o "<outboundDataType>.*</outboundDataType>" | tail -1 | sed 's/<[^>]*>//g')
fi

# 3. FUNCTIONAL VERIFICATION: Send Test Messages
# We will send 2 messages to the listener port and check the output files
# This proves the channel actually works and implements the logic

VERIFY_TEST_RUN="false"
TEST_M_CONTENT=""
TEST_F_CONTENT=""

if [ "$CHANNEL_STATUS" == "STARTED" ] && [ "$LISTEN_PORT" == "6661" ]; then
    echo "Channel is running on port 6661. Sending verification messages..."
    VERIFY_TEST_RUN="true"
    
    # Clean output dir specifically for our verification (preserve agent's work in backup)
    mkdir -p /home/ga/xml_out_backup
    cp /home/ga/xml_out/* /home/ga/xml_out_backup/ 2>/dev/null || true
    rm -f /home/ga/xml_out/* 2>/dev/null || true
    mkdir -p /home/ga/xml_out
    chmod 777 /home/ga/xml_out

    # Test 1: Male
    # Wrap in MLLP: 0x0b ... 0x1c 0x0d
    printf '\x0bMSH|^~\\&|TEST|VERIFY|REC|APP|20240101000000||ADT^A01|VERIFY001|P|2.3\rEVN|A01|20240101000000\rPID|1||TEST_M_999^^^HOSP||TEST^MALE||19800101|M\r\x1c\r' | nc -w 2 localhost 6661
    
    sleep 2
    
    # Test 2: Female
    printf '\x0bMSH|^~\\&|TEST|VERIFY|REC|APP|20240101000000||ADT^A01|VERIFY002|P|2.3\rEVN|A01|20240101000000\rPID|1||TEST_F_888^^^HOSP||TEST^FEMALE||19800101|F\r\x1c\r' | nc -w 2 localhost 6661
    
    sleep 3
    
    # Capture output contents
    # Find file containing the Male MRN
    FILE_M=$(grep -l "TEST_M_999" /home/ga/xml_out/* 2>/dev/null | head -1)
    if [ -n "$FILE_M" ]; then
        TEST_M_CONTENT=$(cat "$FILE_M")
    fi
    
    # Find file containing the Female MRN
    FILE_F=$(grep -l "TEST_F_888" /home/ga/xml_out/* 2>/dev/null | head -1)
    if [ -n "$FILE_F" ]; then
        TEST_F_CONTENT=$(cat "$FILE_F")
    fi
    
    # Restore agent files for visual inspection if needed
    cp /home/ga/xml_out_backup/* /home/ga/xml_out/ 2>/dev/null || true
else
    echo "Channel not suitable for functional testing (Status: $CHANNEL_STATUS, Port: $LISTEN_PORT)"
fi

# 4. Agent's manual work check
# Check if there were files before we wiped them or in backup
AGENT_FILE_COUNT=$(ls -1 /home/ga/xml_out_backup/ 2>/dev/null | wc -l)
if [ "$AGENT_FILE_COUNT" -eq 0 ]; then
    AGENT_FILE_COUNT=$(ls -1 /home/ga/xml_out/ 2>/dev/null | wc -l)
fi


# 5. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 6. Generate Result JSON
JSON_CONTENT=$(cat <<EOF
{
    "task_start_timestamp": $TASK_START,
    "initial_channel_count": $INITIAL_CHANNEL_COUNT,
    "current_channel_count": $CURRENT_CHANNEL_COUNT,
    "channel_found": $([ -n "$CHANNEL_ID" ] && echo "true" || echo "false"),
    "channel_name": "$CHANNEL_NAME",
    "channel_status": "$CHANNEL_STATUS",
    "listen_port": "$LISTEN_PORT",
    "source_datatype": "$SOURCE_DATATYPE",
    "dest_datatype": "$DEST_DATATYPE",
    "verify_test_run": $VERIFY_TEST_RUN,
    "agent_files_created_count": $AGENT_FILE_COUNT,
    "test_result_male_content": $(echo "$TEST_M_CONTENT" | jq -R -s '.'),
    "test_result_female_content": $(echo "$TEST_F_CONTENT" | jq -R -s '.')
}
EOF
)

write_result_json "/tmp/task_result.json" "$JSON_CONTENT"
echo "Export complete. Result:"
cat /tmp/task_result.json