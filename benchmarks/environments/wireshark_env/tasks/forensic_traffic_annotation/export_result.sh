#!/bin/bash
set -e

echo "=== Exporting forensic_traffic_annotation result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Load Task Start Time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Input/Output paths
INPUT_PCAP="/home/ga/Documents/captures/200722_tcp_anon.pcapng"
OUTPUT_PCAP="/home/ga/Documents/captures/evidence_annotated.pcapng"
GROUND_TRUTH_FILE="/tmp/ground_truth.json"

# Check if output file exists
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
OUTPUT_FORMAT_VALID="false"
OUTPUT_PACKET_COUNT=0
OUTPUT_STREAM_COUNT=0
FIRST_PACKET_COMMENT=""
LAST_PACKET_COMMENT=""

if [ -f "$OUTPUT_PCAP" ]; then
    OUTPUT_EXISTS="true"
    
    # Check timestamp
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PCAP" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Check if it's a valid capture file and get packet count
    if CAPINFO=$(capinfos -t -M "$OUTPUT_PCAP" 2>/dev/null); then
        OUTPUT_FORMAT_VALID="true"
        OUTPUT_PACKET_COUNT=$(tshark -r "$OUTPUT_PCAP" 2>/dev/null | wc -l)
        
        # Check how many streams are in the output (should ideally be 1)
        # We count unique tcp.stream values
        OUTPUT_STREAM_COUNT=$(tshark -r "$OUTPUT_PCAP" -T fields -e tcp.stream 2>/dev/null | sort -u | wc -l)
        
        # Extract comments
        # We look at the first and last packet specifically
        FIRST_PACKET_COMMENT=$(tshark -r "$OUTPUT_PCAP" -c 1 -T fields -e frame.comment 2>/dev/null || echo "")
        
        # For the last packet, we can't easily use tail with tshark -T fields efficiently on large files, 
        # but here the file should be small (one stream).
        # We'll get all comments and take the last one.
        LAST_PACKET_COMMENT=$(tshark -r "$OUTPUT_PCAP" -T fields -e frame.comment 2>/dev/null | tail -n 1 || echo "")
    fi
fi

# Load Ground Truth Data
GT_STREAM_ID=-1
GT_PACKET_COUNT=0

if [ -f "$GROUND_TRUTH_FILE" ]; then
    GT_STREAM_ID=$(python3 -c "import json; print(json.load(open('$GROUND_TRUTH_FILE')).get('target_stream_id', -1))")
    GT_PACKET_COUNT=$(python3 -c "import json; print(json.load(open('$GROUND_TRUTH_FILE')).get('target_packet_count', 0))")
fi

# Prepare JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json
import sys

data = {
    'output_exists': '$OUTPUT_EXISTS' == 'true',
    'file_created_during_task': '$FILE_CREATED_DURING_TASK' == 'true',
    'output_format_valid': '$OUTPUT_FORMAT_VALID' == 'true',
    'output_packet_count': int('$OUTPUT_PACKET_COUNT'),
    'output_stream_count': int('$OUTPUT_STREAM_COUNT'),
    'first_packet_comment': sys.argv[1],
    'last_packet_comment': sys.argv[2],
    'ground_truth': {
        'target_stream_id': int('$GT_STREAM_ID'),
        'target_packet_count': int('$GT_PACKET_COUNT')
    }
}

with open('$TEMP_JSON', 'w') as f:
    json.dump(data, f)
" "$FIRST_PACKET_COMMENT" "$LAST_PACKET_COMMENT"

# Move result to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="