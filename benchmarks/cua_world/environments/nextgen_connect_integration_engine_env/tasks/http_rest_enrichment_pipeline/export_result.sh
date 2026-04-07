#!/bin/bash
echo "=== Exporting HTTP REST Enrichment Pipeline results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Initialize results
MOCK_SERVICE_STATUS="fail"
MOCK_EAST_TEST="fail"
MOCK_WEST_TEST="fail"
ENRICHMENT_CHANNEL_STATUS="fail"
ENRICHMENT_FILE_CREATED="false"
ENRICHMENT_LOGIC_TEST="fail"

# --- VERIFICATION STEP 1: Check Mock Service (Port 6666) ---
echo "Verifying Mock Service on port 6666..."
if netstat -tuln | grep -q ":6666 "; then
    MOCK_SERVICE_STATUS="listening"
    
    # Test EAST logic (Zip 10001 starts with 1)
    RESP_EAST=$(curl -s "http://localhost:6666?zip=10001")
    if echo "$RESP_EAST" | grep -qi "EAST"; then
        MOCK_EAST_TEST="pass"
    fi
    
    # Test WEST logic (Zip 90210 starts with 9)
    RESP_WEST=$(curl -s "http://localhost:6666?zip=90210")
    if echo "$RESP_WEST" | grep -qi "WEST"; then
        MOCK_WEST_TEST="pass"
    fi
else
    MOCK_SERVICE_STATUS="not_listening"
fi

# --- VERIFICATION STEP 2: Check Enrichment Channel (Port 6661) ---
echo "Verifying Enrichment Channel on port 6661..."
if netstat -tuln | grep -q ":6661 "; then
    ENRICHMENT_CHANNEL_STATUS="listening"
    
    # Perform End-to-End Test
    # Clear output dir first to ensure we catch NEW files
    rm -rf /tmp/verification_output
    mkdir -p /tmp/verification_output
    
    # We can't easily change the destination of the agent's channel without reconfiguring it.
    # Instead, we will send a message and check the agent's configured output directory: /tmp/enriched_output/
    # We assume the agent followed instructions.
    
    # Clean up agent's output dir to isolate this test run
    rm -f /tmp/enriched_output/* 2>/dev/null
    
    # Send Test Message (Zip 90210 -> Expect WEST)
    # Construct HL7 message with MLLP framing
    MSG="MSH|^~\\&|TEST|FAC|REC|FAC|20240101||ADT^A01|VERIFY01|P|2.5\rPID|1||123^^^MRN||TEST^PATIENT||19800101|M|||123 ST^^CITY^STATE^90210|||||||"
    printf "\x0b${MSG}\x1c\r" | nc -w 2 localhost 6661
    
    # Wait for processing
    sleep 3
    
    # Check if file exists
    if ls /tmp/enriched_output/* >/dev/null 2>&1; then
        ENRICHMENT_FILE_CREATED="true"
        
        # Check content of the generated file
        # We expect the PID segment to have 'WEST' in the 19th field? 
        # Wait, PID.11 is Address. PID.11.5 is Zip. PID.11.9 is County/Parish.
        # Structure: 123 ST^^CITY^STATE^90210^^^^WEST
        # PID|...|...|...|...|...|...|...|...|...|...|123 ST^^CITY^STATE^90210^^^^WEST|...
        
        LATEST_FILE=$(ls -t /tmp/enriched_output/* | head -1)
        FILE_CONTENT=$(cat "$LATEST_FILE")
        
        # Look for WEST in the file
        if echo "$FILE_CONTENT" | grep -q "WEST"; then
            # stricter check: make sure it's in the PID segment context if possible, 
            # but grep is usually sufficient for this specific string in this specific context
            if echo "$FILE_CONTENT" | grep -q "\^90210\^"; then
                 ENRICHMENT_LOGIC_TEST="pass"
            fi
        fi
    fi
else
    ENRICHMENT_CHANNEL_STATUS="not_listening"
fi

# --- COLLECT METADATA ---
CURRENT_COUNT=$(get_channel_count)
INITIAL_COUNT=$(cat /tmp/initial_channel_count.txt 2>/dev/null || echo "0")

# Create JSON Result
JSON_CONTENT=$(cat <<EOF
{
    "mock_service_status": "$MOCK_SERVICE_STATUS",
    "mock_east_test": "$MOCK_EAST_TEST",
    "mock_west_test": "$MOCK_WEST_TEST",
    "enrichment_channel_status": "$ENRICHMENT_CHANNEL_STATUS",
    "enrichment_file_created": $ENRICHMENT_FILE_CREATED,
    "enrichment_logic_test": "$ENRICHMENT_LOGIC_TEST",
    "initial_channel_count": $INITIAL_COUNT,
    "current_channel_count": $CURRENT_COUNT,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/task_result.json" "$JSON_CONTENT"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="