#!/bin/bash
set -e
echo "=== Exporting annotate_http_packets result ==="

source /workspace/scripts/task_utils.sh

# Record task end info
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
ORIGINAL_COUNT=$(cat /tmp/original_packet_count.txt 2>/dev/null || echo "43")

# Take final screenshot
take_screenshot /tmp/task_final.png

OUTPUT_FILE="/home/ga/Documents/captures/http_annotated.pcapng"
FILE_EXISTS="false"
FILE_TYPE="unknown"
PACKET_COUNT=0
COMMENTS_JSON="[]"
FILE_TIMESTAMP=0

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_TIMESTAMP=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    
    # Check file type using capinfos
    FILE_TYPE_RAW=$(capinfos -t "$OUTPUT_FILE" 2>/dev/null | grep "File type" || echo "unknown")
    if echo "$FILE_TYPE_RAW" | grep -q "pcapng"; then
        FILE_TYPE="pcapng"
    elif echo "$FILE_TYPE_RAW" | grep -q "Wireshark/tcpdump"; then
        FILE_TYPE="pcap"
    else
        FILE_TYPE="other"
    fi
    
    # Get packet count
    PACKET_COUNT=$(tshark -r "$OUTPUT_FILE" 2>/dev/null | wc -l)
    
    # Extract comments to JSON structure
    # We use tshark to extract frame number, http info, and comments
    # -Y "pkt_comment" filters to only show packets with comments for the list
    # We use python to escape the output safely into JSON
    
    COMMENTS_JSON=$(python3 -c "
import subprocess
import json
import sys

try:
    # Run tshark to get fields: frame.number | http.request.method | http.response.code | pkt_comment
    cmd = ['tshark', '-r', '$OUTPUT_FILE', '-T', 'fields', 
           '-e', 'frame.number', 
           '-e', 'http.request.method', 
           '-e', 'http.response.code', 
           '-e', 'pkt_comment', 
           '-E', 'separator=|',
           '-Y', 'pkt_comment'] # Only output packets with comments
           
    output = subprocess.check_output(cmd, stderr=subprocess.DEVNULL).decode('utf-8', errors='ignore')
    
    comments = []
    for line in output.strip().split('\n'):
        if not line: continue
        parts = line.split('|')
        if len(parts) >= 4:
            comments.append({
                'frame': parts[0].strip(),
                'method': parts[1].strip(),
                'status_code': parts[2].strip(),
                'comment': parts[3].strip()
            })
    
    print(json.dumps(comments))
except Exception as e:
    print('[]')
")
fi

# Check if Wireshark is still running
APP_RUNNING=$(pgrep -f "wireshark" > /dev/null && echo "true" || echo "false")

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_path": "$OUTPUT_FILE",
    "file_timestamp": $FILE_TIMESTAMP,
    "file_type": "$FILE_TYPE",
    "packet_count": $PACKET_COUNT,
    "original_packet_count": $ORIGINAL_COUNT,
    "extracted_comments": $COMMENTS_JSON,
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result with proper permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="