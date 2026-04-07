#!/bin/bash
echo "=== Exporting Preprocessor Message Normalizer result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Get Channel Info via API
# We need to find the channel named "Pharmacy_Message_Normalizer"
CHANNEL_LIST_XML=$(api_call GET "/channels" 2>/dev/null)

# Python script to parse XML and extract specific channel details
# Extracts: ID, Preprocessing Script, Status
CHANNEL_INFO=$(echo "$CHANNEL_LIST_XML" | python3 -c "
import sys, xml.etree.ElementTree as ET, json

try:
    tree = ET.parse(sys.stdin)
    root = tree.getroot()
    
    found = False
    data = {
        'exists': False, 
        'id': '', 
        'script': '', 
        'status': 'UNKNOWN',
        'received': 0
    }
    
    for channel in root.iter('channel'):
        name = channel.find('name').text if channel.find('name') is not None else ''
        if 'Pharmacy_Message_Normalizer' in name:
            found = True
            data['exists'] = True
            data['id'] = channel.find('id').text
            
            # Get preprocessor script
            # Path: channel -> preprocessingScript
            script = channel.find('preprocessingScript')
            data['script'] = script.text if script is not None else ''
            break
            
    print(json.dumps(data))
except Exception as e:
    print(json.dumps({'exists': False, 'error': str(e)}))
")

CHANNEL_ID=$(echo "$CHANNEL_INFO" | jq -r '.id')
CHANNEL_EXISTS=$(echo "$CHANNEL_INFO" | jq -r '.exists')
SCRIPT_CONTENT=$(echo "$CHANNEL_INFO" | jq -r '.script')

# 3. Get Channel Statistics and Status if channel exists
CHANNEL_STATUS="UNKNOWN"
RECEIVED_COUNT=0

if [ "$CHANNEL_EXISTS" == "true" ] && [ -n "$CHANNEL_ID" ]; then
    # Get Status
    STATUS_JSON=$(get_channel_status_api "$CHANNEL_ID")
    CHANNEL_STATUS="$STATUS_JSON" # Assuming get_channel_status_api returns string state
    
    # Get Stats
    STATS_JSON=$(api_call_json GET "/channels/${CHANNEL_ID}/statistics")
    # Parse received count
    RECEIVED_COUNT=$(echo "$STATS_JSON" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    # Handle potentially different structure or direct map
    if 'channelStatistics' in d:
        print(d['channelStatistics'].get('received', 0))
    else:
        print(d.get('received', 0))
except:
    print(0)
")
fi

# 4. Check Output Files
# Check host path (mounted/shared) and container path
OUTPUT_DIR="/tmp/normalized_messages"
OUTPUT_FILE_COUNT=$(find "$OUTPUT_DIR" -name "*.hl7" -type f 2>/dev/null | wc -l)
LAST_OUTPUT_FILE=$(find "$OUTPUT_DIR" -name "*.hl7" -type f -printf '%T@ %p\n' | sort -n | tail -1 | cut -f2- -d" ")

# 5. Analyze Output File Content (Validation)
CONTENT_VALID="false"
HAS_CR="false"
NO_TRAILING_SPACE="false"

if [ -n "$LAST_OUTPUT_FILE" ] && [ -f "$LAST_OUTPUT_FILE" ]; then
    # Check for Carriage Returns (OD -c outputs \r)
    if od -c "$LAST_OUTPUT_FILE" | grep -q '\\r'; then
        HAS_CR="true"
    fi
    
    # Check for Trailing Whitespace
    # We look for lines ending in space/tab. 
    # Since proper HL7 uses \r as segment delimiter (which is not \n), 
    # standard grep line matching might treat the whole file as one line if \n is absent.
    # We use tr to convert \r to \n for inspection.
    
    # Logic: Convert \r to \n, then check each line for trailing spaces
    if cat "$LAST_OUTPUT_FILE" | tr '\r' '\n' | grep -q '[ \t]$'; then
        NO_TRAILING_SPACE="false"
    else
        NO_TRAILING_SPACE="true"
    fi
    
    if [ "$HAS_CR" == "true" ] && [ "$NO_TRAILING_SPACE" == "true" ]; then
        CONTENT_VALID="true"
    fi
fi

# 6. Construct Final Result JSON
cat > /tmp/task_result.json << EOF
{
    "channel_exists": $CHANNEL_EXISTS,
    "channel_id": "$CHANNEL_ID",
    "preprocessor_script": $(echo "$SCRIPT_CONTENT" | jq -R .),
    "channel_status": "$CHANNEL_STATUS",
    "received_count": ${RECEIVED_COUNT:-0},
    "output_file_count": $OUTPUT_FILE_COUNT,
    "output_content_valid": $CONTENT_VALID,
    "has_cr": $HAS_CR,
    "no_trailing_space": $NO_TRAILING_SPACE,
    "task_timestamp": "$(date -Iseconds)"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json