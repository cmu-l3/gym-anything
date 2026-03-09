#!/bin/bash
set -e

echo "=== Exporting export_protocol_hierarchy result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Get ground truth
GROUND_TRUTH=$(cat /tmp/ground_truth_protocols.json 2>/dev/null || echo "{}")

# Check if the user created the output file
OUTPUT_FILE=""
FILE_EXISTS="false"
CONTENT=""
CONTENT_LENGTH=0

for loc in /home/ga/Documents/captures/protocol_hierarchy.txt /home/ga/Desktop/protocol_hierarchy.txt /home/ga/protocol_hierarchy.txt /tmp/protocol_hierarchy.txt /home/ga/Documents/protocol_hierarchy.txt; do
    if [ -f "$loc" ]; then
        FILE_EXISTS="true"
        OUTPUT_FILE="$loc"
        CONTENT=$(cat "$loc" 2>/dev/null || echo "")
        CONTENT_LENGTH=${#CONTENT}
        break
    fi
done

# Also check for CSV variants
for loc in /home/ga/Documents/captures/protocol_hierarchy.csv /home/ga/Desktop/protocol_hierarchy.csv; do
    if [ -f "$loc" ] && [ "$FILE_EXISTS" = "false" ]; then
        FILE_EXISTS="true"
        OUTPUT_FILE="$loc"
        CONTENT=$(cat "$loc" 2>/dev/null || echo "")
        CONTENT_LENGTH=${#CONTENT}
        break
    fi
done

# Check for protocol names in user's output
HAS_ETHERNET="false"
HAS_IP="false"
HAS_TCP="false"
HAS_HTTP="false"
HAS_PERCENTAGES="false"

if [ -n "$CONTENT" ]; then
    echo "$CONTENT" | grep -qi "ethernet\|eth" && HAS_ETHERNET="true"
    echo "$CONTENT" | grep -qi "internet protocol\|ipv4\| ip \|^ip " && HAS_IP="true"
    echo "$CONTENT" | grep -qi "transmission control\|tcp" && HAS_TCP="true"
    echo "$CONTENT" | grep -qi "hypertext transfer\|http" && HAS_HTTP="true"
    echo "$CONTENT" | grep -q '%\|percent\|[0-9][0-9]*\.[0-9]\|frames:\|bytes:' && HAS_PERCENTAGES="true"
fi

# Create result JSON safely using python3
GROUND_TRUTH_FILE="/tmp/ground_truth_protocols.json"
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json, sys
gt = {}
try:
    with open(sys.argv[9], 'r') as f:
        gt = json.load(f)
except: pass
data = {
    'output_file_exists': sys.argv[1] == 'true',
    'output_file_path': sys.argv[2],
    'content_length': int(sys.argv[3]),
    'mentions_ethernet': sys.argv[4] == 'true',
    'mentions_ip': sys.argv[5] == 'true',
    'mentions_tcp': sys.argv[6] == 'true',
    'mentions_http': sys.argv[7] == 'true',
    'has_percentages': sys.argv[8] == 'true',
    'ground_truth': gt,
    'timestamp': sys.argv[10]
}
with open(sys.argv[11], 'w') as f:
    json.dump(data, f, indent=4)
" "$FILE_EXISTS" "$OUTPUT_FILE" "$CONTENT_LENGTH" "$HAS_ETHERNET" "$HAS_IP" "$HAS_TCP" "$HAS_HTTP" "$HAS_PERCENTAGES" "$GROUND_TRUTH_FILE" "$(date -Iseconds)" "$TEMP_JSON"

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
