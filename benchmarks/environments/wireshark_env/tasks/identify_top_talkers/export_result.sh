#!/bin/bash
set -e

echo "=== Exporting identify_top_talkers result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end.png

# Get ground truth
GROUND_TRUTH=$(cat /tmp/ground_truth_top_talker 2>/dev/null || echo "")
ALL_RANKED=$(cat /tmp/all_senders_ranked.txt 2>/dev/null || echo "")

# Check if the user created the output file
USER_ANSWER=""
FILE_EXISTS="false"

for loc in /home/ga/Documents/captures/top_talker.txt /home/ga/Desktop/top_talker.txt /home/ga/top_talker.txt /tmp/top_talker.txt /home/ga/Documents/top_talker.txt; do
    if [ -f "$loc" ]; then
        FILE_EXISTS="true"
        USER_ANSWER=$(cat "$loc" 2>/dev/null | tr -d '[:space:]')
        break
    fi
done

# Check if user answer matches any top IP
USER_RANK=""
if [ -n "$USER_ANSWER" ] && [ -f /tmp/all_senders_ranked.txt ]; then
    USER_RANK=$(grep -n "$USER_ANSWER" /tmp/all_senders_ranked.txt 2>/dev/null | head -1 | cut -d: -f1 || echo "")
fi

# Create result JSON safely using python3
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json, sys
data = {
    'ground_truth_top_talker': sys.argv[1],
    'output_file_exists': sys.argv[2] == 'true',
    'user_answer': sys.argv[3],
    'user_rank': sys.argv[4],
    'timestamp': sys.argv[5]
}
with open(sys.argv[6], 'w') as f:
    json.dump(data, f, indent=4)
" "$GROUND_TRUTH" "$FILE_EXISTS" "$USER_ANSWER" "$USER_RANK" "$(date -Iseconds)" "$TEMP_JSON"

rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="
