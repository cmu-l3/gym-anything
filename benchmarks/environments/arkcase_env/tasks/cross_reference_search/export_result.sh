#!/bin/bash
echo "=== Exporting Cross-Reference Search Result ==="

# Source utils
source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take Final Screenshot
take_screenshot /tmp/task_final.png
SCREENSHOT_EXISTS=$([ -f /tmp/task_final.png ] && echo "true" || echo "false")

# 2. Check Agent Output File
OUTPUT_PATH="/home/ga/falcon_report.json"
OUTPUT_EXISTS="false"
OUTPUT_CONTENT="{}"
FILE_CREATED_DURING_TASK="false"

if [ -f "$OUTPUT_PATH" ]; then
    OUTPUT_EXISTS="true"
    # Read content safely
    OUTPUT_CONTENT=$(cat "$OUTPUT_PATH")
    
    # Check timestamp
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# 3. Read Ground Truth (Hidden)
GROUND_TRUTH="{}"
if [ -f "/home/ga/.hidden/ground_truth.json" ]; then
    GROUND_TRUTH=$(cat "/home/ga/.hidden/ground_truth.json")
fi

# 4. Construct Result JSON
# We embed both the agent's output and the ground truth for the python verifier
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
jq -n \
    --argjson agent_output "$OUTPUT_CONTENT" \
    --argjson ground_truth "$GROUND_TRUTH" \
    --arg task_start "$TASK_START" \
    --arg task_end "$TASK_END" \
    --arg output_exists "$OUTPUT_EXISTS" \
    --arg file_created "$FILE_CREATED_DURING_TASK" \
    --arg screenshot_path "/tmp/task_final.png" \
    '{
        task_start: $task_start,
        task_end: $task_end,
        output_exists: ($output_exists == "true"),
        file_created_during_task: ($file_created == "true"),
        agent_output: $agent_output,
        ground_truth: $ground_truth,
        screenshot_path: $screenshot_path
    }' > "$TEMP_JSON"

# 5. Save to final location with permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result saved to /tmp/task_result.json"