#!/bin/bash
echo "=== Exporting HL7v2 to FHIR Patient result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check Channel Status via API
CHANNEL_ID=""
CHANNEL_NAME=""
CHANNEL_STATUS="UNKNOWN"
CONFIG_XML=""

# Find channel by name
CHANNELS_JSON=$(get_channels_api)
CHANNEL_ID=$(echo "$CHANNELS_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    channels = data.get('list', []) if isinstance(data, dict) else data
    for c in channels:
        if 'ADT_to_FHIR_Patient' in c.get('name', ''):
            print(c.get('id'))
            break
except: pass
" 2>/dev/null)

if [ -n "$CHANNEL_ID" ]; then
    CHANNEL_NAME="ADT_to_FHIR_Patient"
    # Get status
    CHANNEL_STATUS=$(get_channel_status_api "$CHANNEL_ID")
    # Get Config
    CONFIG_XML=$(api_call GET "/channels/${CHANNEL_ID}")
fi

# 2. Check for Output File
OUTPUT_DIR="/tmp/fhir_output"
OUTPUT_FILE=$(ls -t "$OUTPUT_DIR"/*.json 2>/dev/null | head -1)

# IF NO OUTPUT FILE: Attempt to send test message as fallback
# This handles cases where agent built the channel but didn't trigger the test
if [ -z "$OUTPUT_FILE" ] && [ -n "$CHANNEL_ID" ] && [ "$CHANNEL_STATUS" == "STARTED" ]; then
    echo "No output file found. Attempting to send test message..."
    
    # Read test message (handling newlines for printf)
    # Using python to send MLLP is safer than printf/nc pipeline sometimes
    python3 -c "
import socket
msg = open('/home/ga/test_adt.hl7', 'rb').read()
try:
    # MLLP wrapping: 0x0B + msg + 0x1C + 0x0D
    mllp_msg = b'\x0b' + msg + b'\x1c\r'
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(5)
    s.connect(('localhost', 6661))
    s.sendall(mllp_msg)
    # Wait for ACK
    ack = s.recv(1024)
    s.close()
    print('Message sent')
except Exception as e:
    print(f'Failed to send: {e}')
" 
    # Give it a moment to process
    sleep 3
    OUTPUT_FILE=$(ls -t "$OUTPUT_DIR"/*.json 2>/dev/null | head -1)
fi

# 3. Read Output Content
FILE_CONTENT=""
FILE_TIMESTAMP=0
if [ -n "$OUTPUT_FILE" ]; then
    FILE_CONTENT=$(cat "$OUTPUT_FILE")
    FILE_TIMESTAMP=$(stat -c %Y "$OUTPUT_FILE")
fi

# 4. Get Task Start Time
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 5. Extract specific config details (Port, Dir) from XML using Python
# (Doing it here to simplify verifier)
CONFIG_DETAILS=$(python3 -c "
import sys, xml.etree.ElementTree as ET
try:
    xml_data = '''$CONFIG_XML'''
    if not xml_data:
        print('{}')
        sys.exit(0)
        
    root = ET.fromstring(xml_data)
    
    # Find Source Port
    port = ''
    for prop in root.findall('.//listenerConnectorProperties'):
        p = prop.find('port')
        if p is not None: port = p.text
        
    # Find Destination Dir
    dest_dir = ''
    for prop in root.findall('.//properties[@class=\"com.mirth.connect.connectors.file.FileDispatcherProperties\"]'):
        h = prop.find('host')
        if h is not None: dest_dir = h.text
        
    print(f'{{\"port\": \"{port}\", \"dest_dir\": \"{dest_dir}\"}}')
except Exception as e:
    print(f'{{\"error\": \"{str(e)}\"}}')
")

# 6. Create Result JSON
# Embed the file content directly so verifier.py doesn't need to read the file
# Use python to safely construct JSON to avoid escaping hell
python3 -c "
import json, os, sys

result = {
    'channel_found': bool('$CHANNEL_ID'),
    'channel_id': '$CHANNEL_ID',
    'channel_status': '$CHANNEL_STATUS',
    'config': $CONFIG_DETAILS,
    'output_file_exists': bool('$OUTPUT_FILE'),
    'file_timestamp': int('$FILE_TIMESTAMP'),
    'task_start_time': int('$START_TIME'),
    'file_content': '''$FILE_CONTENT'''
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Set permissions
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="