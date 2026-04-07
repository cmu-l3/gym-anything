#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 1. Get Channel Status and Configuration via API
# We use python to query the API and parse XML/JSON
cat > /tmp/check_channels.py << 'PYTHON_SCRIPT'
import requests
import json
import xml.etree.ElementTree as ET
import sys

auth = ('admin', 'admin')
headers = {'X-Requested-With': 'OpenAPI', 'Accept': 'application/json'}
base_url = 'https://localhost:8443/api'

result = {
    "channel_found": False,
    "channel_name": "",
    "channel_state": "UNKNOWN",
    "source_type": "",
    "destination_type": "",
    "batch_processing_enabled": False,
    "source_dir": "",
    "dest_dir": ""
}

try:
    # Get all channels
    r = requests.get(f"{base_url}/channels", auth=auth, headers=headers, verify=False)
    if r.status_code == 200:
        channels = r.json().get('list', [])
        if isinstance(channels, dict): channels = [channels] # Handle single entry case
        
        # Find our channel
        target_channel = None
        for ch in channels:
            name = ch.get('name', '').lower()
            if 'batch' in name or 'split' in name:
                target_channel = ch
                break
        
        if target_channel:
            result["channel_found"] = True
            result["channel_name"] = target_channel.get('name')
            channel_id = target_channel.get('id')
            
            # Check Status
            r_status = requests.get(f"{base_url}/channels/{channel_id}/status", auth=auth, headers=headers, verify=False)
            if r_status.status_code == 200:
                # API returns complex object, simplify
                status_data = r_status.json()
                # Dashboard status is often inside 'dashboardStatus'
                result["channel_state"] = status_data.get('dashboardStatus', {}).get('state', 'UNKNOWN')

            # Parse XML for detailed config (Source Connector)
            # We fetch the channel again as XML to parse properties easily or stick to JSON structure
            # JSON structure for connectors is deeply nested
            source_connector = target_channel.get('sourceConnector', {})
            result["source_type"] = source_connector.get('transportName')
            
            # Check for batch properties in source
            # Properties are usually a map. In JSON: properties -> pluginProperties
            props = source_connector.get('properties', {})
            process_batch = props.get('processBatch', 'false') # This might vary by version/connector
            
            # For File Reader, batch is usually in 'processBatch' boolean
            if str(process_batch).lower() == 'true':
                result["batch_processing_enabled"] = True
            
            # Check Source Dir
            file_props = props.get('fileReceiverProperties', {}) # If using JSON
            # Note: JSON structure varies, might be better to check flat strings in XML
            
            # Destinations
            dests = target_channel.get('destinationConnectors', [])
            if dests:
                if isinstance(dests, dict): dests = [dests]
                result["destination_type"] = dests[0].get('transportName')

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYTHON_SCRIPT

# Execute python check
CHANNEL_INFO=$(python3 /tmp/check_channels.py 2>/dev/null)

# 2. Check Output Files in Container
# We copy the output directory from the container to the host for analysis
rm -rf /tmp/verify_output
mkdir -p /tmp/verify_output
docker cp nextgen-connect:/var/hl7_output/. /tmp/verify_output/ 2>/dev/null || true

# Count files
OUTPUT_FILE_COUNT=$(ls -1 /tmp/verify_output/ | wc -l)

# Check content of files
# We expect 5 files, each with 1 MSH segment
VALID_MSG_COUNT=0
MSG_IDS_FOUND=""

for f in /tmp/verify_output/*; do
    if [ -f "$f" ]; then
        # Check for MSH
        if grep -q "^MSH" "$f"; then
            # Check MSH count (should be 1 per file)
            MSH_COUNT=$(grep -c "^MSH" "$f")
            if [ "$MSH_COUNT" -eq 1 ]; then
                VALID_MSG_COUNT=$((VALID_MSG_COUNT + 1))
            fi
            
            # Extract Message ID (MSH-10)
            # MSH|^~\&|...|...|...|...|...||ORU^R01|MSG001|...
            # Field 10 is the ID
            ID=$(grep "^MSH" "$f" | awk -F'|' '{print $10}')
            MSG_IDS_FOUND="${MSG_IDS_FOUND},${ID}"
        fi
    fi
done

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "channel_info": $CHANNEL_INFO,
    "output_file_count": $OUTPUT_FILE_COUNT,
    "valid_message_file_count": $VALID_MSG_COUNT,
    "found_message_ids": "$MSG_IDS_FOUND",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="