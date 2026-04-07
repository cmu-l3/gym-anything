#!/bin/bash
echo "=== Exporting HL7 De-identification Result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check Channel Status (API)
CHANNEL_NAME_QUERY="PHI_Deidentification_Pipeline"
CHANNEL_ID=""
CHANNEL_STATUS="UNKNOWN"
CHANNEL_EXISTS="false"
DEPLOYED="false"

# Find channel ID by name
CHANNEL_LIST=$(get_channels_api)
CHANNEL_ID=$(echo "$CHANNEL_LIST" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    channels = data.get('list', {}).get('channel', [])
    if isinstance(channels, dict): channels = [channels]
    for c in channels:
        if '$CHANNEL_NAME_QUERY'.lower() in c.get('name', '').lower():
            print(c.get('id'))
            break
except: pass
")

if [ -n "$CHANNEL_ID" ]; then
    CHANNEL_EXISTS="true"
    # Check deployment status
    STATUS_JSON=$(get_channel_status_api "$CHANNEL_ID")
    if [ "$STATUS_JSON" = "STARTED" ] || [ "$STATUS_JSON" = "STOPPED" ] || [ "$STATUS_JSON" = "PAUSED" ]; then
        DEPLOYED="true"
        CHANNEL_STATUS="$STATUS_JSON"
    fi
    
    # Get statistics (messages sent)
    STATS_JSON=$(get_channel_stats_api "$CHANNEL_ID")
    MSG_SENT=$(echo "$STATS_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('channelStatistics',{}).get('sent',0))" 2>/dev/null || echo "0")
else
    MSG_SENT="0"
fi

# 3. Analyze Output Files
OUTPUT_DIR="/home/ga/hl7_output"
OUTPUT_FILE_COUNT=$(ls -1 "$OUTPUT_DIR"/*.hl7 2>/dev/null | wc -l)
FILES_ANALYSIS="[]"

if [ "$OUTPUT_FILE_COUNT" -gt 0 ]; then
    # Read files content into JSON structure for the verifier to analyze
    # Warning: Be careful with special characters in HL7 (newlines, pipes)
    FILES_ANALYSIS=$(python3 -c "
import os, json
files = []
directory = '$OUTPUT_DIR'
try:
    for filename in os.listdir(directory):
        if filename.endswith('.hl7'):
            path = os.path.join(directory, filename)
            with open(path, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
                files.append({'filename': filename, 'content': content})
    print(json.dumps(files))
except Exception as e:
    print('[]')
")
fi

# 4. Check timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILES_CREATED_DURING_TASK="false"
if [ "$OUTPUT_FILE_COUNT" -gt 0 ]; then
    # Check the oldest file in output
    OLDEST_FILE_TIME=$(stat -c %Y "$OUTPUT_DIR"/*.hl7 2>/dev/null | sort -n | head -1)
    if [ -n "$OLDEST_FILE_TIME" ] && [ "$OLDEST_FILE_TIME" -ge "$TASK_START" ]; then
        FILES_CREATED_DURING_TASK="true"
    fi
fi

# 5. Create Result JSON
cat > /tmp/task_result.json <<EOF
{
    "channel_exists": $CHANNEL_EXISTS,
    "channel_id": "$CHANNEL_ID",
    "channel_status": "$CHANNEL_STATUS",
    "is_deployed": $DEPLOYED,
    "messages_sent_count": $MSG_SENT,
    "output_file_count": $OUTPUT_FILE_COUNT,
    "files_created_during_task": $FILES_CREATED_DURING_TASK,
    "output_files": $FILES_ANALYSIS,
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Set permissions
chmod 666 /tmp/task_result.json

echo "Result export complete."
cat /tmp/task_result.json