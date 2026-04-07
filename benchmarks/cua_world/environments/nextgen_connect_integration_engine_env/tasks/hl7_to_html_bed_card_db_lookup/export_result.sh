#!/bin/bash
echo "=== Exporting hl7_to_html_bed_card_db_lookup result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Take Agent Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Get Channel Info
CHANNEL_NAME="Bed_Card_Generator"
CHANNEL_ID=$(get_channel_id "$CHANNEL_NAME")
CHANNEL_STATUS=$(get_channel_status_api "$CHANNEL_ID" 2>/dev/null)

echo "Channel ID: $CHANNEL_ID"
echo "Channel Status: $CHANNEL_STATUS"

# 3. PERFORM ACTIVE VERIFICATION TEST
# We send a specific message that the agent wouldn't know to hardcode.
# We use DOC202 (Dr. Lisa Cuddy) and a specific MRN/Name.

TEST_LAST_NAME="TESTPATIENT"
TEST_FIRST_NAME="VERONICA"
TEST_MRN="MRN99999"
TEST_DOC_ID="DOC202" # Should map to Dr. Lisa Cuddy
TEST_FILE_NAME="${TEST_LAST_NAME}_${TEST_MRN}.html"
TEST_FILE_PATH="/home/ga/bed_cards/$TEST_FILE_NAME"

# Clean up any previous test file
rm -f "$TEST_FILE_PATH"

echo "Sending verification HL7 message..."
# Construct HL7 message
# Note: MLLP framing \x0b ... \x1c\x0d
# PV1-7 is formatted as ID^NAME... we put the ID in first component
MSG="MSH|^~\\&|VERIFIER|HOSP|MIRTH|PC|$(date +%Y%m%d%H%M)||ADT^A01|VERIFY001|P|2.3
PID|||$TEST_MRN^^^HOSP^MR||$TEST_LAST_NAME^$TEST_FIRST_NAME||19900101|F
PV1||I|3N^301^A||||$TEST_DOC_ID^IGNORE^THIS||||||||||||||||||||||||||||||||||||$(date +%Y%m%d%H%M)"

# Send via netcat to localhost 6661
printf "\x0b${MSG}\x1c\x0d" | nc -w 5 localhost 6661 2>/dev/null

# Wait for processing
sleep 5

# 4. Check Test Output
TEST_FILE_EXISTS="false"
TEST_FILE_CONTENT=""
DOCTOR_NAME_FOUND="false"
HTML_VALID="false"

if [ -f "$TEST_FILE_PATH" ]; then
    TEST_FILE_EXISTS="true"
    TEST_FILE_CONTENT=$(cat "$TEST_FILE_PATH")
    
    # Check for DB Enrichment (Dr. Lisa Cuddy)
    if echo "$TEST_FILE_CONTENT" | grep -q "Dr. Lisa Cuddy"; then
        DOCTOR_NAME_FOUND="true"
    fi
    
    # Check for HTML structure
    if echo "$TEST_FILE_CONTENT" | grep -qi "<html>\|<div\|<body"; then
        HTML_VALID="true"
    fi
fi

# 5. Extract Channel Configuration (for static analysis)
CHANNEL_XML=""
if [ -n "$CHANNEL_ID" ]; then
    CHANNEL_XML=$(query_postgres "SELECT channel FROM channel WHERE id='$CHANNEL_ID';" 2>/dev/null)
fi

# 6. Create Result JSON
JSON_CONTENT=$(cat <<EOF
{
    "channel_found": $([ -n "$CHANNEL_ID" ] && echo "true" || echo "false"),
    "channel_id": "$CHANNEL_ID",
    "channel_status": "$CHANNEL_STATUS",
    "test_file_created": $TEST_FILE_EXISTS,
    "test_file_path": "$TEST_FILE_PATH",
    "doctor_name_found_in_html": $DOCTOR_NAME_FOUND,
    "html_structure_valid": $HTML_VALID,
    "channel_xml_snippet": "$(echo "$CHANNEL_XML" | head -n 20 | sed 's/"/\\"/g')",
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/task_result.json" "$JSON_CONTENT"

echo "Verification Test Result:"
echo "  File Created: $TEST_FILE_EXISTS"
echo "  Doctor Lookup Success: $DOCTOR_NAME_FOUND"
echo "  Status: $CHANNEL_STATUS"

cat /tmp/task_result.json
echo "=== Export complete ==="