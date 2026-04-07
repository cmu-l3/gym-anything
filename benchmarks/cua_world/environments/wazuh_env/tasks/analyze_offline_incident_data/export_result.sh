#!/bin/bash
echo "=== Exporting task results ==="

# 1. Timestamps for anti-gaming
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 2. Check output file
OUTPUT_PATH="/home/ga/incident_report.json"
GROUND_TRUTH_PATH="/var/lib/wazuh-task-truth.json"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_SIZE=$(stat -c %s "$OUTPUT_PATH" 2>/dev/null || echo "0")
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    else
        CREATED_DURING_TASK="false"
    fi
else
    OUTPUT_EXISTS="false"
    OUTPUT_SIZE="0"
    CREATED_DURING_TASK="false"
fi

# 3. Capture final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 4. Read content safely (for bundling into result json)
# We read the user's submission AND the ground truth here to package them
# for the verifier. This avoids complex file copying in python.
SUBMISSION_CONTENT=$(cat "$OUTPUT_PATH" 2>/dev/null || echo "{}")
TRUTH_CONTENT=$(cat "$GROUND_TRUTH_PATH" 2>/dev/null || echo "{}")

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
# Using python to safely construct JSON with embedded JSON content
python3 -c "
import json
import os

try:
    submission = json.loads('''$SUBMISSION_CONTENT''')
except:
    submission = {}

try:
    truth = json.loads('''$TRUTH_CONTENT''')
except:
    truth = {}

result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'output_exists': $OUTPUT_EXISTS,
    'created_during_task': $CREATED_DURING_TASK,
    'submission': submission,
    'ground_truth': truth,
    'screenshot_path': '/tmp/task_final.png'
}

with open('$TEMP_JSON', 'w') as f:
    json.dump(result, f)
"

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="