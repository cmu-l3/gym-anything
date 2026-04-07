#!/bin/bash
echo "=== Exporting Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# 1. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Dynamic Verification Test (The "Black Box" Test)
# We inject a NEW file that the agent hasn't seen to verify the logic works generically.
echo "Starting dynamic verification test..."

TEST_PATIENT="VerifyBot User"
TEST_SUBSTANCE="Kryptonite"
TEST_REACTION="Weakness"
TEST_FILE="/tmp/verification_test.xml"
TEST_OUTPUT_PATTERN="verification_test"

# Generate Test XML
cat > "$TEST_FILE" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<ClinicalDocument xmlns="urn:hl7-org:v3" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <realmCode code="US"/>
    <typeId root="2.16.840.1.113883.1.3" extension="POCD_HD000040"/>
    <recordTarget>
        <patientRole>
            <id root="2.16.840.1.113883.4.1" extension="987654321"/>
            <patient>
                <name>
                    <given>VerifyBot</given>
                    <family>User</family>
                </name>
            </patient>
        </patientRole>
    </recordTarget>
    <component>
        <structuredBody>
            <component>
                <section>
                    <templateId root="2.16.840.1.113883.10.20.22.2.6.1"/>
                    <code code="48765-2" codeSystem="2.16.840.1.113883.6.1"/>
                    <title>Allergies</title>
                    <entry>
                        <act classCode="ACT" moodCode="EVN">
                            <templateId root="2.16.840.1.113883.10.20.22.4.30"/>
                            <statusCode code="active"/>
                            <entryRelationship typeCode="SUBJ">
                                <observation classCode="OBS" moodCode="EVN">
                                    <participant typeCode="CSM">
                                        <participantRole classCode="MANU">
                                            <playingEntity classCode="MMAT">
                                                <name>$TEST_SUBSTANCE</name>
                                            </playingEntity>
                                        </participantRole>
                                    </participant>
                                    <entryRelationship typeCode="MFST" inversionInd="true">
                                        <observation classCode="OBS" moodCode="EVN">
                                            <value xsi:type="CD" displayName="$TEST_REACTION"/>
                                        </observation>
                                    </entryRelationship>
                                </observation>
                            </entryRelationship>
                        </act>
                    </entry>
                </section>
            </component>
        </structuredBody>
    </component>
</ClinicalDocument>
EOF

# Ensure permissions
chmod 666 "$TEST_FILE"

# Inject the file into the input directory
cp "$TEST_FILE" /home/ga/ccda_input/verification_test.xml

# Wait for processing (15 seconds)
echo "Waiting 15 seconds for processing..."
sleep 15

# Check for output
# We search for any file in output dir created in the last minute containing expected data
# But simplest is to check if *any* new file appeared or specific name if task required it.
# Task description said: "${originalFilename}_parsed.json" (implied naming convention, but flexible)

OUTPUT_FOUND="false"
OUTPUT_CONTENT=""
GENERATED_FILE=""

# Look for files in output dir
# We use `find` to get the most recent file
GENERATED_FILE=$(find /home/ga/allergy_output -type f -name "*json" -mmin -1 | head -n 1)

if [ -n "$GENERATED_FILE" ]; then
    OUTPUT_FOUND="true"
    OUTPUT_CONTENT=$(cat "$GENERATED_FILE")
    echo "Found output file: $GENERATED_FILE"
else
    echo "No output file found in /home/ga/allergy_output"
fi

# 3. Check Channel Status
CHANNEL_STATUS="unknown"
CHANNEL_ID=""
CHANNEL_DATA=$(query_postgres "SELECT id, name FROM channel WHERE LOWER(name) LIKE '%ccda%' OR LOWER(name) LIKE '%allergy%';" 2>/dev/null || true)

if [ -n "$CHANNEL_DATA" ]; then
    CHANNEL_ID=$(echo "$CHANNEL_DATA" | head -1 | cut -d'|' -f1)
    CHANNEL_NAME=$(echo "$CHANNEL_DATA" | head -1 | cut -d'|' -f2)
    
    # Get status via API
    API_STATUS=$(get_channel_status_api "$CHANNEL_ID" 2>/dev/null || echo "UNKNOWN")
    CHANNEL_STATUS="$API_STATUS"
fi

# 4. Generate Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "channel_found": $([ -n "$CHANNEL_ID" ] && echo "true" || echo "false"),
    "channel_name": "$CHANNEL_NAME",
    "channel_status": "$CHANNEL_STATUS",
    "test_file_injected": "true",
    "output_file_found": $OUTPUT_FOUND,
    "output_file_path": "$GENERATED_FILE",
    "output_content_raw": $(echo "$OUTPUT_CONTENT" | jq -R -s '.' 2>/dev/null || echo "\"\""),
    "expected_patient": "$TEST_PATIENT",
    "expected_substance": "$TEST_SUBSTANCE",
    "expected_reaction": "$TEST_REACTION",
    "timestamp": $(date +%s)
}
EOF

# Save and clean up
write_result_json "/tmp/task_result.json" "$(cat $TEMP_JSON)"
rm "$TEMP_JSON"
rm -f "$TEST_FILE"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="