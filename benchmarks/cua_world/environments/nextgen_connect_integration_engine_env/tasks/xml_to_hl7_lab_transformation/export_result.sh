#!/bin/bash
echo "=== Exporting Task Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check for Channel Existence and Status via API
CHANNEL_ID=""
CHANNEL_STATUS="UNKNOWN"
CHANNEL_NAME_MATCH="false"

# Get all channels
CHANNELS_JSON=$(curl -sk -u admin:admin \
    -H "X-Requested-With: OpenAPI" \
    -H "Accept: application/json" \
    "https://localhost:8443/api/channels" 2>/dev/null)

# Find channel ID for "XML_to_HL7_Lab"
if [ -n "$CHANNELS_JSON" ]; then
    CHANNEL_ID=$(echo "$CHANNELS_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
channels = data.get('list', []) if isinstance(data, dict) else data
found = next((c for c in channels if c.get('name') == 'XML_to_HL7_Lab'), None)
if found:
    print(found.get('id'))
" 2>/dev/null)
fi

if [ -n "$CHANNEL_ID" ]; then
    CHANNEL_NAME_MATCH="true"
    # Get status
    STATUS_JSON=$(curl -sk -u admin:admin \
        -H "X-Requested-With: OpenAPI" \
        -H "Accept: application/json" \
        "https://localhost:8443/api/channels/${CHANNEL_ID}/status" 2>/dev/null)
    
    CHANNEL_STATUS=$(echo "$STATUS_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data.get('dashboardStatus', {}).get('state', 'UNKNOWN'))
" 2>/dev/null)
fi

# 2. Check Output Files in Container
OUTPUT_FILE_EXISTS="false"
OUTPUT_FILENAME=""
OUTPUT_CONTENT_B64=""

# List files in output dir
FILES=$(docker exec nextgen-connect ls -1 /opt/mirthdata/hl7_out/ 2>/dev/null)

if [ -n "$FILES" ]; then
    OUTPUT_FILE_EXISTS="true"
    # Pick the first file
    OUTPUT_FILENAME=$(echo "$FILES" | head -n 1)
    
    # Read content from container
    OUTPUT_CONTENT=$(docker exec nextgen-connect cat "/opt/mirthdata/hl7_out/$OUTPUT_FILENAME")
    
    # Base64 encode for safe transport in JSON
    OUTPUT_CONTENT_B64=$(echo "$OUTPUT_CONTENT" | base64 -w 0)
fi

# 3. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "channel_found": $CHANNEL_NAME_MATCH,
    "channel_id": "$CHANNEL_ID",
    "channel_status": "$CHANNEL_STATUS",
    "output_file_exists": $OUTPUT_FILE_EXISTS,
    "output_filename": "$OUTPUT_FILENAME",
    "output_content_b64": "$OUTPUT_CONTENT_B64",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="