#!/bin/bash
echo "=== Exporting Encrypted C2 DNS Exfiltration results ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Gather timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Check output file
OUTPUT_PATH="/home/ga/Documents/forensic_evidence.json"
OUTPUT_EXISTS="false"
OUTPUT_CONTENT=""
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    # Read content (limit to 10KB for safety)
    OUTPUT_CONTENT=$(head -c 10240 "$OUTPUT_PATH" 2>/dev/null || echo "")
fi

# 4. Read ground truth
GT_PATH="/var/lib/wireshark_ground_truth/ground_truth.json"
GROUND_TRUTH="{}"
if [ -f "$GT_PATH" ]; then
    GROUND_TRUTH=$(cat "$GT_PATH")
fi

# 5. Check Wireshark running
WIRESHARK_RUNNING=$(pgrep -f "wireshark" > /dev/null && echo "true" || echo "false")

# 6. Assemble result JSON using Python for safe escaping
python3 -c "
import json, sys

output_content = sys.argv[1]
ground_truth = json.loads(sys.argv[2])

# Try to parse the agent's output as JSON
user_json = {}
try:
    user_json = json.loads(output_content)
except:
    pass

result = {
    'task_start': int(sys.argv[3]),
    'task_end': int(sys.argv[4]),
    'output_exists': sys.argv[5] == 'true',
    'file_created_during_task': sys.argv[6] == 'true',
    'output_content_raw': output_content,
    'user_json': user_json,
    'ground_truth': ground_truth,
    'wireshark_running': sys.argv[7] == 'true',
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
" "$OUTPUT_CONTENT" "$GROUND_TRUTH" "$TASK_START" "$TASK_END" "$OUTPUT_EXISTS" "$FILE_CREATED_DURING_TASK" "$WIRESHARK_RUNNING"

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="
