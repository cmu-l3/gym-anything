#!/bin/bash
echo "=== Exporting Scheduled Bed Census CSV Task Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_COUNT=$(cat /tmp/initial_channel_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(get_channel_count)

OUTPUT_FILE="/home/ga/reports/census_report.csv"

# 1. Check File Existence and Timing
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE_BYTES=0

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE_BYTES=$(stat -c %s "$OUTPUT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Copy file to temp location for verifier to download
    cp "$OUTPUT_FILE" /tmp/census_report_export.csv
    chmod 644 /tmp/census_report_export.csv
fi

# 2. Check Channel Configuration via API
CHANNEL_FOUND="false"
CHANNEL_ID=""
CHANNEL_NAME=""
CHANNEL_STATUS="UNKNOWN"
SOURCE_CONNECTOR_TYPE=""
DESTINATION_CONNECTOR_TYPE=""

# Query API for channel list
CHANNELS_JSON=$(get_channels_api)

# Parse JSON to find Bed_Census_Reporter (using python as jq might be minimal/absent)
CHANNEL_INFO=$(echo "$CHANNELS_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    channels = data.get('list', {}).get('channel', [])
    if isinstance(channels, dict): channels = [channels]
    
    found = None
    for c in channels:
        if c.get('name') == 'Bed_Census_Reporter':
            found = c
            break
            
    if found:
        print(json.dumps({
            'id': found.get('id'),
            'name': found.get('name'),
            'sourceType': found.get('sourceConnector', {}).get('transportName'),
            'destType': found.get('destinationConnectors', {}).get('connector', {}).get('transportName')
        }))
    else:
        print('{}')
except:
    print('{}')
")

if [ "$CHANNEL_INFO" != "{}" ]; then
    CHANNEL_FOUND="true"
    CHANNEL_ID=$(echo "$CHANNEL_INFO" | python3 -c "import sys, json; print(json.load(sys.stdin).get('id'))")
    CHANNEL_NAME=$(echo "$CHANNEL_INFO" | python3 -c "import sys, json; print(json.load(sys.stdin).get('name'))")
    SOURCE_CONNECTOR_TYPE=$(echo "$CHANNEL_INFO" | python3 -c "import sys, json; print(json.load(sys.stdin).get('sourceType'))")
    # Note: destination could be a list, simplifying here assuming single dest or taking first
    DESTINATION_CONNECTOR_TYPE=$(echo "$CHANNEL_INFO" | python3 -c "import sys, json; print(json.load(sys.stdin).get('destType'))")
    
    # Get Status
    CHANNEL_STATUS=$(get_channel_status_api "$CHANNEL_ID")
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Prepare result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_channel_count": $INITIAL_COUNT,
    "current_channel_count": $CURRENT_COUNT,
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_size_bytes": $FILE_SIZE_BYTES,
    "channel_found": $CHANNEL_FOUND,
    "channel_id": "$CHANNEL_ID",
    "channel_name": "$CHANNEL_NAME",
    "channel_status": "$CHANNEL_STATUS",
    "source_type": "$SOURCE_CONNECTOR_TYPE",
    "destination_type": "$DESTINATION_CONNECTOR_TYPE",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="
cat /tmp/task_result.json