#!/bin/bash
echo "=== Exporting HL7 Enrichment Results ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final State
take_screenshot /tmp/task_final.png

# 2. Basic Channel Checks
INITIAL_COUNT=$(cat /tmp/initial_channel_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(get_channel_count)
CHANNEL_ID=$(get_channel_id "HL7_Enricher")
CHANNEL_STATUS=$(get_channel_status_api "$CHANNEL_ID")

echo "Channel ID: $CHANNEL_ID"
echo "Channel Status: $CHANNEL_STATUS"

# 3. LIVE VERIFICATION TEST (The "Enrichment" Check)
# We run this INSIDE the container to ensure connectivity to localhost/DB
echo "Running live verification test..."

VERIFICATION_PASSED="false"
VERIFICATION_DETAILS="Test failed to start"
TEST_MRN="PAT_VERIFY_$(date +%s)"
TEST_EMAIL="verify_$(date +%s)@checker.com"
TEST_FILE_PREFIX="verify_$(date +%s)"

# A. Insert unique test data into DB
echo "Inserting test record: $TEST_MRN -> $TEST_EMAIL"
docker exec nextgen-postgres psql -U postgres -d mirthdb -c "INSERT INTO patient_contacts (mrn, email) VALUES ('$TEST_MRN', '$TEST_EMAIL');"

# B. Construct HL7 Message
# Minimal ADT message with the Test MRN in PID-3.1
HL7_MSG="MSH|^~\\&|SEND|FAC|REC|FAC|$(date +%Y%m%d%H%M%S)||ADT^A01|${TEST_FILE_PREFIX}|P|2.3\rEVN|A01|$(date +%Y%m%d%H%M%S)\rPID|1||${TEST_MRN}||TESTPAT^VERIFY||19800101|M|||123 Main St^^City^ST^12345|||||||\r"

# C. Send Message to Port 6661
if nc -z localhost 6661; then
    echo "Port 6661 is open. Sending message..."
    # Wrap in MLLP (0x0B ... 0x1C 0x0D)
    printf '\x0b%s\x1c\x0d' "$HL7_MSG" | nc localhost 6661
    
    # Wait for processing
    sleep 5
    
    # D. Check Output
    # Look for a file containing the TEST_MRN created recently
    FOUND_FILE=$(grep -l "$TEST_MRN" /home/ga/enriched_output/*.hl7 2>/dev/null | head -1)
    
    if [ -n "$FOUND_FILE" ]; then
        echo "Found output file: $FOUND_FILE"
        CONTENT=$(cat "$FOUND_FILE")
        
        # Check if the email was injected
        if [[ "$CONTENT" == *"$TEST_EMAIL"* ]]; then
            VERIFICATION_PASSED="true"
            VERIFICATION_DETAILS="Success: Email $TEST_EMAIL found in output message."
            echo "SUCCESS: Enrichment verified."
        else
            VERIFICATION_PASSED="false"
            VERIFICATION_DETAILS="Failed: Output file found but email $TEST_EMAIL NOT present."
            echo "FAILURE: Email missing."
        fi
    else
        VERIFICATION_PASSED="false"
        VERIFICATION_DETAILS="Failed: No output file generated for MRN $TEST_MRN."
        echo "FAILURE: No output file."
    fi
else
    VERIFICATION_PASSED="false"
    VERIFICATION_DETAILS="Failed: Port 6661 is not open."
    echo "FAILURE: Port closed."
fi

# 4. Generate JSON Result
cat > /tmp/task_result.json <<EOF
{
  "initial_count": $INITIAL_COUNT,
  "current_count": $CURRENT_COUNT,
  "channel_id": "$CHANNEL_ID",
  "channel_status": "$CHANNEL_STATUS",
  "live_verification_passed": $VERIFICATION_PASSED,
  "verification_details": "$VERIFICATION_DETAILS",
  "test_mrn": "$TEST_MRN",
  "test_email": "$TEST_EMAIL",
  "timestamp": "$(date -Iseconds)"
}
EOF

# Set permissions for the verifier to read
chmod 666 /tmp/task_result.json

echo "=== Export Complete ==="
cat /tmp/task_result.json