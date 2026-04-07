#!/bin/bash
echo "=== Exporting sidecar_xml_manifest_generation result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. SEND VERIFICATION MESSAGE
# We send a specific controlled message to verify the logic definitively
echo "Sending verification message..."
VERIFY_MSG_ID="VERIFY001"
# MLLP framed message
# MSH|^~\&|TEST|TEST|TEST|TEST|20230101120000||ADT^A01|VERIFY001|P|2.3
# EVN|A01|20230101120000
# PID|1||12345^^^MRN||Doe^John
printf '\x0bMSH|^~\\&|TEST|TEST|TEST|TEST|20230101120000||ADT^A01|VERIFY001|P|2.3\rEVN|A01|20230101120000\rPID|1||12345^^^MRN||Doe^John\r\x1c\r' | nc localhost 6661 -w 2 2>/dev/null

# Wait for processing
sleep 5

# 2. CHECK OUTPUT FILES
OUTPUT_DIR="/home/ga/archive_drop"
HL7_FILE_EXISTS="false"
XML_FILE_EXISTS="false"
HL7_FILENAME=""
XML_FILENAME=""
XML_CONTENT=""
HL7_CONTENT=""

# Find files generated for our verification message (using the ID if possible, or listing recent)
# The agent is supposed to use {MESSAGEID} in the filename.
# NextGen Connect Message IDs are sequential integers (1, 2, 3...).
# Since we just sent a message, we look for the most recent files.

# List files by time
LATEST_HL7=$(ls -t "$OUTPUT_DIR"/*.hl7 2>/dev/null | head -1)
LATEST_XML=$(ls -t "$OUTPUT_DIR"/*.xml 2>/dev/null | head -1)

if [ -f "$LATEST_HL7" ]; then
    HL7_FILE_EXISTS="true"
    HL7_FILENAME=$(basename "$LATEST_HL7")
    HL7_CONTENT=$(cat "$LATEST_HL7")
fi

if [ -f "$LATEST_XML" ]; then
    XML_FILE_EXISTS="true"
    XML_FILENAME=$(basename "$LATEST_XML")
    XML_CONTENT=$(cat "$LATEST_XML")
fi

# 3. PARSE XML CONTENT
# valid_xml, extracted_pid, extracted_name, extracted_date, extracted_file_ref
XML_VALID="false"
PARSED_PID=""
PARSED_NAME=""
PARSED_DATE=""
PARSED_FILE_REF=""

if [ "$XML_FILE_EXISTS" = "true" ]; then
    # Simple python parser for robustness
    PARSED_JSON=$(python3 -c "
import xml.etree.ElementTree as ET
import json
import sys

try:
    content = sys.stdin.read()
    if not content.strip():
        print(json.dumps({'valid': False}))
        sys.exit(0)

    # Wrap in fake root if needed or parse directly
    # The task asks for root <IndexEntry>
    try:
        root = ET.fromstring(content)
        
        data = {
            'valid': True,
            'root_tag': root.tag,
            'patient_id': root.findtext('PatientID', ''),
            'patient_name': root.findtext('PatientName', ''),
            'event_date': root.findtext('EventDate', ''),
            'original_file': root.findtext('OriginalFile', '')
        }
        print(json.dumps(data))
    except ET.ParseError:
        print(json.dumps({'valid': False}))

except Exception as e:
    print(json.dumps({'valid': False, 'error': str(e)}))
" <<< "$XML_CONTENT")

    XML_VALID=$(echo "$PARSED_JSON" | jq -r '.valid')
    if [ "$XML_VALID" = "true" ]; then
        PARSED_PID=$(echo "$PARSED_JSON" | jq -r '.patient_id')
        PARSED_NAME=$(echo "$PARSED_JSON" | jq -r '.patient_name')
        PARSED_DATE=$(echo "$PARSED_JSON" | jq -r '.event_date')
        PARSED_FILE_REF=$(echo "$PARSED_JSON" | jq -r '.original_file')
    fi
fi

# 4. CHECK CHANNEL STATUS
CHANNEL_STATUS="unknown"
# We assume the channel is the one listening on 6661
CHANNEL_ID=$(query_postgres "SELECT channel_id FROM channel_ports WHERE port=6661 LIMIT 1" 2>/dev/null || true)

if [ -z "$CHANNEL_ID" ]; then
    # Fallback search by name
    CHANNEL_ID=$(get_channel_id "Document_Archive_Feed")
fi

if [ -n "$CHANNEL_ID" ]; then
    CHANNEL_STATUS=$(get_channel_status_api "$CHANNEL_ID")
fi

# 5. EXPORT JSON
cat > /tmp/task_result.json << EOF
{
    "channel_found": $([ -n "$CHANNEL_ID" ] && echo "true" || echo "false"),
    "channel_status": "$CHANNEL_STATUS",
    "hl7_file_exists": $HL7_FILE_EXISTS,
    "xml_file_exists": $XML_FILE_EXISTS,
    "hl7_filename": "$HL7_FILENAME",
    "xml_filename": "$XML_FILENAME",
    "xml_valid": $XML_VALID,
    "parsed_pid": "$PARSED_PID",
    "parsed_name": "$PARSED_NAME",
    "parsed_date": "$PARSED_DATE",
    "parsed_file_ref": "$PARSED_FILE_REF",
    "verification_message_sent": "true",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="