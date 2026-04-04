#!/bin/bash
echo "=== Exporting Model Config Report Result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

OUTPUT_PATH="/home/ga/Documents/hec_ras_results/model_config.json"
GROUND_TRUTH_PATH="/tmp/.ground_truth.json"

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check Output File
OUTPUT_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
AGENT_CONTENT="{}"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    
    # Check modification time
    OUTPUT_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Read content safely
    AGENT_CONTENT=$(cat "$OUTPUT_PATH")
fi

# 2. Get Ground Truth
GROUND_TRUTH="{}"
if [ -f "$GROUND_TRUTH_PATH" ]; then
    GROUND_TRUTH=$(cat "$GROUND_TRUTH_PATH")
fi

# 3. Take final screenshot
take_screenshot /tmp/task_final.png

# 4. Create Result JSON
# We combine agent output and ground truth into one JSON for the verifier
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "output_exists": $OUTPUT_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "agent_output": $AGENT_CONTENT,
    "ground_truth": $GROUND_TRUTH,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export Complete ==="