#!/bin/bash
set -e
echo "=== Exporting save_filtered_packets result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Load ground truth values
EXPECTED_SYN_COUNT=$(cat /tmp/expected_syn_count.txt 2>/dev/null || echo "0")
ORIGINAL_TOTAL=$(cat /tmp/total_packet_count.txt 2>/dev/null || echo "0")

# Locate output file (check alternatives)
OUTPUT_FILE="/home/ga/Documents/captures/syn_packets.pcapng"
FOUND_FILE=""
FILE_EXISTS="false"

# Check priority list of possible filenames
for f in "$OUTPUT_FILE" \
         "/home/ga/Documents/captures/syn_packets.pcap" \
         "/home/ga/Documents/captures/syn_packets.cap" \
         "/home/ga/Desktop/syn_packets.pcapng"; do
    if [ -s "$f" ]; then
        FOUND_FILE="$f"
        FILE_EXISTS="true"
        break
    fi
done

# Analyze output file if it exists
OUTPUT_COUNT=0
SYN_IN_OUTPUT=0
NON_SYN_COUNT=0
FILE_MTIME=0

if [ "$FILE_EXISTS" = "true" ]; then
    FILE_MTIME=$(stat -c %Y "$FOUND_FILE" 2>/dev/null || echo "0")
    
    # 1. Count total packets in output
    OUTPUT_COUNT=$(tshark -r "$FOUND_FILE" 2>/dev/null | wc -l)
    
    # 2. Count packets matching the required filter (SYN=1, ACK=0)
    SYN_IN_OUTPUT=$(tshark -r "$FOUND_FILE" -Y "tcp.flags.syn == 1 && tcp.flags.ack == 0" 2>/dev/null | wc -l)
    
    # 3. Count packets NOT matching the filter (contamination)
    NON_SYN_COUNT=$(tshark -r "$FOUND_FILE" -Y "!(tcp.flags.syn == 1 && tcp.flags.ack == 0)" 2>/dev/null | wc -l)
fi

# Create result JSON
# Use python for safe JSON creation
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json, sys
data = {
    'task_start': int(sys.argv[1]),
    'task_end': int(sys.argv[2]),
    'file_exists': sys.argv[3] == 'true',
    'file_path': sys.argv[4],
    'file_mtime': int(sys.argv[5]),
    'output_packet_count': int(sys.argv[6]),
    'syn_packet_count': int(sys.argv[7]),
    'non_syn_packet_count': int(sys.argv[8]),
    'expected_syn_count': int(sys.argv[9]),
    'original_total_count': int(sys.argv[10])
}
with open(sys.argv[11], 'w') as f:
    json.dump(data, f, indent=4)
" "$TASK_START" "$TASK_END" "$FILE_EXISTS" "$FOUND_FILE" "$FILE_MTIME" \
  "$OUTPUT_COUNT" "$SYN_IN_OUTPUT" "$NON_SYN_COUNT" \
  "$EXPECTED_SYN_COUNT" "$ORIGINAL_TOTAL" "$TEMP_JSON"

# Save result to standard location
safe_json_write "$(cat $TEMP_JSON)" "/tmp/task_result.json"
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="