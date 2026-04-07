#!/bin/bash
echo "=== Exporting Heartbeat Monitor Results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check Channel Configuration via Database/API
CHANNEL_NAME="Heartbeat_Monitor"
CHANNEL_EXISTS="false"
CHANNEL_ID=""
SOURCE_TYPE=""
POLLING_FREQ=""
DEST_TYPE=""
DEST_DIR=""
CHANNEL_STATE="UNKNOWN"

# Find channel by name
CHANNEL_DATA=$(query_postgres "SELECT id, name, channel FROM channel WHERE LOWER(name) = LOWER('$CHANNEL_NAME');" 2>/dev/null)

if [ -n "$CHANNEL_DATA" ]; then
    CHANNEL_EXISTS="true"
    CHANNEL_ID=$(echo "$CHANNEL_DATA" | cut -d'|' -f1)
    # Extract XML (everything after the second pipe)
    # Note: simple cut might fail if XML contains pipes, but NextGen XML usually doesn't in structural tags
    # Better to fetch just the XML column in a separate query if ID is known
    CHANNEL_XML=$(query_postgres "SELECT channel FROM channel WHERE id='$CHANNEL_ID';" 2>/dev/null)
    
    # Analyze XML using Python
    CONFIG_JSON=$(python3 -c "
import sys, re, json
xml_content = sys.stdin.read()
config = {
    'source_type': 'unknown',
    'polling_freq': '0',
    'dest_type': 'unknown',
    'dest_dir': ''
}

# Check Source Type
if 'com.mirth.connect.connectors.js.JavaScriptReceiverProperties' in xml_content:
    config['source_type'] = 'JavaScript Reader'
elif 'JavaScriptReceiverProperties' in xml_content:
    config['source_type'] = 'JavaScript Reader'

# Check Polling Frequency
poll_match = re.search(r'<pollingFrequency>(\d+)</pollingFrequency>', xml_content)
if poll_match:
    config['polling_freq'] = poll_match.group(1)

# Check Destination Type
if 'com.mirth.connect.connectors.file.FileDispatcherProperties' in xml_content:
    config['dest_type'] = 'File Writer'
elif 'FileDispatcherProperties' in xml_content:
    config['dest_type'] = 'File Writer'

# Check Destination Directory
dir_match = re.search(r'<host>(.*?)</host>', xml_content)
if dir_match:
    config['dest_dir'] = dir_match.group(1)

print(json.dumps(config))
" <<< "$CHANNEL_XML")
    
    SOURCE_TYPE=$(echo "$CONFIG_JSON" | jq -r .source_type)
    POLLING_FREQ=$(echo "$CONFIG_JSON" | jq -r .polling_freq)
    DEST_TYPE=$(echo "$CONFIG_JSON" | jq -r .dest_type)
    DEST_DIR=$(echo "$CONFIG_JSON" | jq -r .dest_dir)

    # Check Channel Status via API
    CHANNEL_STATE=$(get_channel_status_api "$CHANNEL_ID")
fi

# 2. Check Output Files
OUTPUT_DIR="/opt/heartbeat_output"
FILE_COUNT=0
FILES_CREATED_DURING_TASK="false"
VALID_CONTENT="false"
SAMPLE_CONTENT=""
MSG_TYPE=""
SENDER_APP=""
PID_ID=""

if [ -d "$OUTPUT_DIR" ]; then
    # Count files ending in .hl7 or no extension (exclude hidden)
    FILE_COUNT=$(ls -1 "$OUTPUT_DIR" 2>/dev/null | wc -l)
    
    if [ "$FILE_COUNT" -gt 0 ]; then
        # Check timestamps of the newest file
        NEWEST_FILE=$(ls -t "$OUTPUT_DIR"/* | head -1)
        FILE_MTIME=$(stat -c %Y "$NEWEST_FILE" 2>/dev/null || echo "0")
        
        if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
            FILES_CREATED_DURING_TASK="true"
        fi
        
        # Check content of newest file
        SAMPLE_CONTENT=$(cat "$NEWEST_FILE" | head -c 500) # Read first 500 chars
        
        # Simple content checks
        if [[ "$SAMPLE_CONTENT" == *"MSH|"* ]]; then
            # Extract fields using Python for reliability
            CONTENT_METRICS=$(python3 -c "
import sys, json
content = sys.stdin.read()
metrics = {'valid': False, 'type': '', 'sender': '', 'pid': ''}
try:
    segments = content.split('\r')
    msh = next((s for s in segments if s.startswith('MSH|')), None)
    pid = next((s for s in segments if s.startswith('PID|')), None)
    
    if msh:
        fields = msh.split('|')
        if len(fields) > 8:
            metrics['valid'] = True
            metrics['sender'] = fields[2] # MSH-3
            metrics['type'] = fields[8]   # MSH-9
            
    if pid:
        fields = pid.split('|')
        if len(fields) > 3:
            metrics['pid'] = fields[3] # PID-3
            
except Exception:
    pass
print(json.dumps(metrics))
" <<< "$SAMPLE_CONTENT")
            
            VALID_CONTENT=$(echo "$CONTENT_METRICS" | jq -r .valid)
            MSG_TYPE=$(echo "$CONTENT_METRICS" | jq -r .type)
            SENDER_APP=$(echo "$CONTENT_METRICS" | jq -r .sender)
            PID_ID=$(echo "$CONTENT_METRICS" | jq -r .pid)
        fi
    fi
fi

# Prepare result JSON
cat > /tmp/task_result.json << EOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "channel_exists": $CHANNEL_EXISTS,
  "channel_id": "$CHANNEL_ID",
  "channel_name": "$CHANNEL_NAME",
  "source_type": "$SOURCE_TYPE",
  "polling_freq_ms": "$POLLING_FREQ",
  "dest_type": "$DEST_TYPE",
  "dest_dir": "$DEST_DIR",
  "channel_state": "$CHANNEL_STATE",
  "output_dir_exists": $([ -d "$OUTPUT_DIR" ] && echo "true" || echo "false"),
  "file_count": $FILE_COUNT,
  "files_created_during_task": $FILES_CREATED_DURING_TASK,
  "sample_content_valid": $VALID_CONTENT,
  "msg_type": "$MSG_TYPE",
  "sender_app": "$SENDER_APP",
  "pid_id": "$PID_ID"
}
EOF

# Output for debugging log
cat /tmp/task_result.json

echo "=== Export complete ==="