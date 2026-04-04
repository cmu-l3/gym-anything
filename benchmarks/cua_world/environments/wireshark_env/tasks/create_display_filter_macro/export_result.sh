#!/bin/bash
set -euo pipefail

echo "=== Exporting create_display_filter_macro result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PCAP_FILE="/home/ga/Documents/captures/200722_tcp_anon.pcapng"

# 1. Calculate Ground Truth using tshark
# We calculate the count of packets matching the required filter expression
echo "Calculating ground truth..."
EXPECTED_FILTER="tcp.analysis.retransmission || tcp.analysis.fast_retransmission || tcp.analysis.spurious_retransmission"
GROUND_TRUTH_COUNT=$(tshark -r "$PCAP_FILE" -Y "$EXPECTED_FILTER" 2>/dev/null | wc -l)
echo "Ground Truth Count: $GROUND_TRUTH_COUNT"

# 2. Check User Output File
OUTPUT_FILE="/home/ga/Documents/packet_count.txt"
USER_COUNT="-1"
FILE_EXISTS="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    # Extract first number found in file
    USER_COUNT=$(grep -oE '[0-9]+' "$OUTPUT_FILE" | head -1 || echo "-1")
fi

# 3. Check User Macro Configuration
MACRO_FILE="/home/ga/.config/wireshark/dfilter_macros"
MACRO_CONTENT=""
MACRO_EXISTS="false"

if [ -f "$MACRO_FILE" ]; then
    MACRO_EXISTS="true"
    MACRO_CONTENT=$(cat "$MACRO_FILE")
fi

# 4. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json, sys

data = {
    'ground_truth_count': int(sys.argv[1]),
    'user_count': int(sys.argv[2]),
    'output_file_exists': sys.argv[3] == 'true',
    'macro_file_exists': sys.argv[4] == 'true',
    'macro_content': sys.argv[5],
    'screenshot_path': '/tmp/task_final.png'
}

with open(sys.argv[6], 'w') as f:
    json.dump(data, f, indent=4)
" "$GROUND_TRUTH_COUNT" "$USER_COUNT" "$FILE_EXISTS" "$MACRO_EXISTS" "$MACRO_CONTENT" "$TEMP_JSON"

# Move result to standard location
safe_json_write "$(cat $TEMP_JSON)" "/tmp/task_result.json"
rm "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="