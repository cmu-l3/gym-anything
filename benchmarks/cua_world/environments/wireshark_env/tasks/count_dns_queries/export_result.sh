#!/bin/bash
set -e

echo "=== Exporting count_dns_queries result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Get ground truth
GROUND_TRUTH=$(cat /tmp/ground_truth_dns_queries 2>/dev/null || echo "0")
TOTAL_PACKETS=$(cat /tmp/initial_total_packets 2>/dev/null || echo "0")

# Check if the user created the output file
OUTPUT_FILE="/home/ga/Documents/captures/dns_query_count.txt"
USER_ANSWER=""
FILE_EXISTS="false"

# Search multiple possible locations
for loc in "$OUTPUT_FILE" /home/ga/Desktop/dns_query_count.txt /home/ga/dns_query_count.txt /tmp/dns_query_count.txt /home/ga/Documents/dns_query_count.txt; do
    if [ -f "$loc" ]; then
        FILE_EXISTS="true"
        OUTPUT_FILE="$loc"
        USER_ANSWER=$(cat "$loc" 2>/dev/null | tr -d '[:space:]')
        break
    fi
done

# Create result JSON safely using python3
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json, sys
data = {
    'ground_truth_dns_queries': int(sys.argv[1]) if sys.argv[1].isdigit() else 0,
    'total_packets': int(sys.argv[2]) if sys.argv[2].isdigit() else 0,
    'output_file_exists': sys.argv[3] == 'true',
    'output_file_path': sys.argv[4],
    'user_answer': sys.argv[5],
    'timestamp': sys.argv[6]
}
with open(sys.argv[7], 'w') as f:
    json.dump(data, f, indent=4)
" "$GROUND_TRUTH" "$TOTAL_PACKETS" "$FILE_EXISTS" "$OUTPUT_FILE" "$USER_ANSWER" "$(date -Iseconds)" "$TEMP_JSON"

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
