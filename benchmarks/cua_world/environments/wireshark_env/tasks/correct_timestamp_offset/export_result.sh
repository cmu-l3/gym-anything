#!/bin/bash
set -e

echo "=== Exporting correct_timestamp_offset result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Paths
EXPECTED_OUTPUT="/home/ga/Documents/captures/http_corrected.pcapng"
# Check alternate extensions just in case
if [ ! -f "$EXPECTED_OUTPUT" ] && [ -f "/home/ga/Documents/captures/http_corrected.pcap" ]; then
    EXPECTED_OUTPUT="/home/ga/Documents/captures/http_corrected.pcap"
fi

# Gather Results
OUTPUT_EXISTS="false"
OUTPUT_PACKET_COUNT=0
OUTPUT_START_TIME=0
FILE_CREATED_DURING_TASK="false"
IS_VALID_PCAP="false"

if [ -f "$EXPECTED_OUTPUT" ]; then
    OUTPUT_EXISTS="true"
    
    # Check creation time for anti-gaming
    FILE_MTIME=$(stat -c %Y "$EXPECTED_OUTPUT" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # validate pcap and get metrics
    if tshark -r "$EXPECTED_OUTPUT" -c 1 >/dev/null 2>&1; then
        IS_VALID_PCAP="true"
        OUTPUT_PACKET_COUNT=$(tshark -r "$EXPECTED_OUTPUT" 2>/dev/null | wc -l)
        OUTPUT_START_TIME=$(tshark -r "$EXPECTED_OUTPUT" -c 1 -T fields -e frame.time_epoch 2>/dev/null || echo "0")
    fi
fi

# Retrieve baseline metrics
ORIG_PACKET_COUNT=$(cat /tmp/baseline_packet_count.txt 2>/dev/null || echo "0")
ORIG_START_TIME=$(cat /tmp/baseline_start_time.txt 2>/dev/null || echo "0")

# Check if app is running
APP_RUNNING=$(pgrep -f "wireshark" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json
import sys

data = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'output_exists': str('$OUTPUT_EXISTS').lower() == 'true',
    'output_path': '$EXPECTED_OUTPUT',
    'file_created_during_task': str('$FILE_CREATED_DURING_TASK').lower() == 'true',
    'is_valid_pcap': str('$IS_VALID_PCAP').lower() == 'true',
    'metrics': {
        'original_packet_count': int('$ORIG_PACKET_COUNT'),
        'original_start_time': float('$ORIG_START_TIME') if '$ORIG_START_TIME' else 0.0,
        'output_packet_count': int('$OUTPUT_PACKET_COUNT'),
        'output_start_time': float('$OUTPUT_START_TIME') if '$OUTPUT_START_TIME' else 0.0
    },
    'app_was_running': str('$APP_RUNNING').lower() == 'true'
}

with open('$TEMP_JSON', 'w') as f:
    json.dump(data, f, indent=4)
"

# Save result with permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="